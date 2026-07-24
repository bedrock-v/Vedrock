module session

import nbt
import protocol
import protocol.types
import server.block

fn (mut s NetworkSession) handle_block_actor_data(p protocol.BlockActorDataPacket) ! {
	pos := p.block_position
	if s.player.is_dead() || !s.can_interact() {
		return
	}
	if !s.within_place_reach(pos) {
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	b := s.hub.blocks.get(old_id) or { return }
	if b !is block.SignBlock {
		return
	}
	if p.nbt.tag !is nbt.Compound {
		return
	}
	compound := p.nbt.tag as nbt.Compound
	text := extract_sign_text(compound) or { return }
	binding := s.world_binding()
	if isnil(binding.world_runtime) {
		return
	}
	mut wr := binding.world_runtime
	task := SetSignTextTask{
		x:    pos.x
		y:    pos.y
		z:    pos.z
		text: text
	}
	if wr.submit(task) {
		_ := <-task.done
	}
}

// SetSignTextTask writes a sign's block entity text and broadcasts the
// update, entirely on the owning world's own actor thread.
struct SetSignTextTask {
	x    int
	y    int
	z    int
	text string
	done chan bool = chan bool{cap: 1}
}

fn (t SetSignTextTask) run(mut tx WorldTx) {
	defer {
		t.done <- true
	}
	tx.wr.world.set_tile_text(t.x, t.y, t.z, t.text)
	tx.wr.broadcast_world(&protocol.BlockActorDataPacket{
		block_position: types.BlockPosition{t.x, t.y, t.z}
		nbt:            build_sign_nbt(t.x, t.y, t.z, t.text)
	})
}

// extract_sign_text pulls FrontText.Text out of a sign's block-entity NBT
// compound. Uses `is` checks rather than blind `as` casts since this parses
// untrusted client input, malformed NBT must be rejected.
fn extract_sign_text(compound nbt.Compound) ?string {
	front_tag := compound.get('FrontText') or { return none }
	if front_tag is nbt.Compound {
		text_tag := front_tag.get('Text') or { return none }
		if text_tag is string {
			return text_tag
		}
	}
	return none
}

// sign_text_side builds one FrontText/BackText compound.
fn sign_text_side(text string) nbt.Compound {
	mut side := nbt.new_compound()
	side.set('Text', nbt.Tag(text))
	side.set('TextOwner', nbt.Tag(''))
	side.set('SignTextColor', nbt.Tag(i32(-16777216))) // opaque black, 0xff000000
	side.set('IgnoreLighting', nbt.Tag(i8(0)))
	side.set('PersistFormatting', nbt.Tag(i8(1)))
	return side
}

fn build_sign_nbt(x int, y int, z int, text string) nbt.RootTag {
	mut root := nbt.new_compound()
	root.set('id', nbt.Tag('Sign'))
	root.set('x', nbt.Tag(i32(x)))
	root.set('y', nbt.Tag(i32(y)))
	root.set('z', nbt.Tag(i32(z)))
	root.set('IsWaxed', nbt.Tag(i8(0)))
	root.set('FrontText', nbt.Tag(sign_text_side(text)))
	root.set('BackText', nbt.Tag(sign_text_side('')))
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(root)
	}
}
