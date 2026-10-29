module session

import math
import sync.stdatomic
import time
import bedrock_v.protocol
import bedrock_v.protocol.packets
import bedrock_v.protocol.types
import server.network
import server.world

// Transport is one client's connection, framed into packets. A session reads
// and writes packets through it and knows nothing about how they travel.
pub interface Transport {
mut:
	read() !protocol.Packet
	write(p protocol.Packet) !
	// buffered_amount is how many bytes written have not gone out yet.
	buffered_amount() u64
	close()
}

// chunks_per_tick is the most chunks sent to one client each tick.
const chunks_per_tick = 4

// max_buffered is how many bytes may wait to go out to a client before
// it is dropped.
const max_buffered = u64(8 * 1024 * 1024)

// Player is the entity a session controls. Like any entity, it belongs to a
// world and is reached through that world's transaction.
pub struct Player {
	id_   u64
	name_ string
pub mut:
	// position is where the player's feet are.
	position [3]f32
	// rotation is the pitch and the yaw.
	rotation [2]f32
	// moves counts the movement packets handled so far.
	moves int
}

// new_player builds the entity for a client that has logged in. Put it in a
// world with Tx.add before anything can reach it.
pub fn new_player(id u64, name string) &Player {
	return &Player{
		id_:   id
		name_: name
	}
}

pub fn (p &Player) id() u64 {
	return p.id_
}

// name is what the player logged in as.
pub fn (p &Player) name() string {
	return p.name_
}

// Session runs one client: it reads that client's packets and handles them on
// the world its player is in and every tick sends it the chunks it is due.
//
// Two threads share it. The one calling run reads and handles packets. The
// other ticks and is the only one that writes to the client.
pub struct Session {
mut:
	transport Transport
	handle    &world.Handle
	player    world.Ref[Player]
	// loader is what the player sees of its world. It is only touched inside
	// a transaction on that world.
	loader  &world.Loader
	stopped &stdatomic.AtomicVal[bool] = stdatomic.new_atomic[bool](false)
}

// ChunkView is what a tick found to send.
struct ChunkView {
	position [3]f32
	radius   int
	// radius_changed is set when the client has to be told its new radius.
	radius_changed bool
	// moved is set when the player is in another chunk than last tick.
	moved  bool
	chunks []world.LoadedChunk
}

// new_session builds a session for a player that is already in a world and was
// given radius chunks of view when it spawned.
pub fn new_session(mut t Transport, h &world.Handle, radius int) &Session {
	return &Session{
		transport: t
		handle:    h
		player:    world.ref[Player](h)
		loader:    world.new_loader(radius)
	}
}

// run reads and handles packets until the transport runs out of them. Each
// packet is handled before the next is read, which keeps them in the order the
// client sent them. The chunks the player sees are let go when it returns.
pub fn (mut s Session) run() {
	ticker := spawn s.tick_loop()
	for {
		p := s.transport.read() or { break }
		s.handle_packet(p) or { continue }
	}
	s.stopped.store(true)
	ticker.wait()
	mut loader := s.loader
	world.call_ref[Player, bool](s.player, 'session.close', fn [mut loader] (mut tx world.Tx, e &Player) !bool {
		loader.close(mut tx)
		return true
	}) or {}
}

// tick_loop sends the player its chunks every tick until the session stops. A
// client that can't be sent to is dropped which ends the read run is on.
fn (mut s Session) tick_loop() {
	for !s.stopped.load() {
		time.sleep(world.tick_interval)
		s.send_chunks() or {
			// TODO : again logger thing! (I'm stating them, so it will be easy to search & replace with logger one)
			eprintln('vedrock: dropping player ${s.handle.id()}: ${err}')
			s.transport.close()
			return
		}
	}
}

// send_chunks moves the player's loader to where the player is and sends what
// that brought into view, a few chunks at a time.
fn (mut s Session) send_chunks() ! {
	mut loader := s.loader
	view := world.call_ref[Player, ChunkView](s.player, 'session.chunks', fn [mut loader] (mut tx world.Tx, e &Player) !ChunkView {
		moved := loader.move(mut tx, e.position[0], e.position[2])
		changed := if _ := loader.take_radius_change() { true } else { false }
		return ChunkView{
			position:       e.position
			radius:         loader.radius()
			radius_changed: changed
			moved:          moved
			chunks:         loader.load(mut tx, chunks_per_tick)
		}
	})!
	if view.radius_changed {
		s.transport.write(&packets.ChunkRadiusUpdatedPacket{
			chunk_radius: view.radius
		})!
	}
	if view.moved || view.radius_changed {
		s.transport.write(&packets.NetworkChunkPublisherUpdatePacket{
			new_view_position: types.BlockPos{
				x: i32(view.position[0])
				y: i32(view.position[1])
				z: i32(view.position[2])
			}
			new_view_radius:   u32(view.radius * 16)
		})!
	}
	for c in view.chunks {
		s.transport.write(&packets.LevelChunkPacket{
			chunk_position:        types.ChunkPos{
				x: i32(c.pos.x)
				z: i32(c.pos.z)
			}
			serialized_chunk_data: c.encoded
		})!
	}
	buffered := s.transport.buffered_amount()
	if buffered > max_buffered {
		return error('it is not reading: ${buffered} bytes are waiting to go out')
	}
}

// handle_packet runs a packet inside a transaction on the world holding the
// player and waits for it.
//
// Chat, commands and forms act on players in other worlds, which needs a
// transaction on each of those worlds. They are handled elsewhere.
fn (mut s Session) handle_packet(p protocol.Packet) ! {
	mut loader := s.loader
	world.call_ref[Player, bool](s.player, 'session.packet', fn [p, mut loader] (mut tx world.Tx, e &Player) !bool {
		mut pl := unsafe { e }
		dispatch(mut tx, mut pl, mut loader, p)!
		return true
	})!
}

// dispatch hands a packet to its handler. It runs on the world's thread, inside
// the transaction it is given.
fn dispatch(mut tx world.Tx, mut pl Player, mut loader world.Loader, p protocol.Packet) ! {
	if p is packets.PlayerAuthInputPacket {
		pl.position = [
			coordinate_or(p.player_position[0], pl.position[0]),
			coordinate_or(p.player_position[1] - network.eye_height, pl.position[1]),
			coordinate_or(p.player_position[2], pl.position[2]),
		]!
		pl.rotation = [
			finite_or(p.player_rotation[0], pl.rotation[0]),
			finite_or(p.player_rotation[1], pl.rotation[1]),
		]!
		pl.moves++
		return
	}
	if p is packets.RequestChunkRadiusPacket {
		loader.change_radius(mut tx, network.chunk_radius(int(p.chunk_radius)))
		return
	}
	return error('no handler for ${p.name()} in world "${tx.world_name()}"')
}

// max_coordinate bounds a position the client sends in blocks.
const max_coordinate = f32(30_000_000)

// coordinate_or is a position the client sent, held to max_coordinate, or
// fallback when it is NaN or infinite.
fn coordinate_or(v f32, fallback f32) f32 {
	c := finite_or(v, fallback)
	if c > max_coordinate {
		return max_coordinate
	}
	if c < -max_coordinate {
		return -max_coordinate
	}
	return c
}

// finite_or is v or fallback when v is NaN or infinite.
fn finite_or(v f32, fallback f32) f32 {
	if math.is_nan(f64(v)) || math.is_inf(f64(v), 0) {
		return fallback
	}
	return v
}
