module session

import rand
import bedrock_v.protocol.types
import server.block
import server.entity
import server.worldrt

// award_experience gives the player points and shows them the new bar. It is
// the one entry point: every source of experience goes through here.
//
// Only spectators are turned away. Taking damage and collecting experience are
// separate things - a creative player throwing a bottle of enchanting still
// gets what it is worth - so this asks whether the player can pick anything
// up rather than whether they can be hurt.
fn (mut s NetworkSession) award_experience(points int) {
	if points <= 0 || !s.player.game_mode().collects_experience() {
		return
	}
	s.player.add_experience(points)
	s.send_experience()
}

// spawn_experience_orbs drops amount at pos, split across as many orbs as it
// takes and scattered so they do not land in one stack.
fn spawn_experience_orbs(mut tx worldrt.WorldTx, amount int, pos types.Vector3) {
	for value in entity.split_experience(amount) {
		behaviour := entity.new_experience_orb_behaviour(value, entity.orb_pickup_delay_ticks)
		mut e := tx.wr.entities.spawn(behaviour, pos)
		e.set_velocity(types.Vector3{
			x: (rand.f32() * 0.2) - 0.1
			y: 0.2
			z: (rand.f32() * 0.2) - 0.1
		})
	}
}

fn (mut h WorldEntityHost) grant_experience(runtime_id u64, amount int) bool {
	mut a := h.wr.entities.actor_by_runtime_id(runtime_id) or { return false }
	if mut a is NetworkSession {
		a.award_experience(amount)
		return true
	}
	return false
}

fn (mut h WorldEntityHost) spawn_experience_orbs(amount int, pos types.Vector3) {
	mut tx := h.tx()
	spawn_experience_orbs(mut tx, amount, pos)
}

// PlayerExperienceTask awards experience on the owning world runtime, for the
// callers that reach a player from outside their own session thread.
struct PlayerExperienceTask {
	id entity.ActorId
	points     int
	levels     int
}

fn (t PlayerExperienceTask) name() string {
	return 'PlayerExperienceTask'
}

fn (t PlayerExperienceTask) run(mut tx worldrt.WorldTx) {
	mut target := player_for_id(mut tx, t.id) or { return }
	if t.levels != 0 {
		target.player.add_experience_levels(t.levels)
	}
	if t.points != 0 {
		target.player.add_experience(t.points)
	}
	target.send_experience()
}

// give_experience is the View entry point: it takes the award to the player's
// own world runtime rather than mutating them from whichever thread asked.
pub fn (mut s NetworkSession) give_experience(points int) {
	s.submit_experience(points, 0)
}

// give_experience_levels moves the player whole levels, as /xp with an L
// suffix does.
pub fn (mut s NetworkSession) give_experience_levels(levels int) {
	s.submit_experience(0, levels)
}

pub fn (s &NetworkSession) experience_level() int {
	return s.player.experience_level()
}

fn (mut s NetworkSession) submit_experience(points int, levels int) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerExperienceTask{
		id:     s.actor_id()
		points: points
		levels: levels
	})
}

// drop_block_experience leaves what a mined block was worth on the ground.
//
// An ore only pays out when it was actually broken down into something else.
// A drop that is the ore's own block form means it came up whole - which is
// what Silk Touch does to it - and a whole ore has not given up its experience
// yet. Nothing carries Silk Touch on this branch, so today the check only ever
// passes; it is here so the rule holds the moment something does.
fn drop_block_experience(mut tx worldrt.WorldTx, mut s NetworkSession, block_id int, drop_name string, pos types.Vector3) {
	if drop_name == '' || drop_name == s.block_item_name(block_id) {
		return
	}
	b := block.get(block_id) or { return }
	reward := block.experience_for_block(b.identifier()) or { return }
	amount := entity.rand_int_range(reward.min_amount, reward.max_amount)
	if amount <= 0 {
		return
	}
	spawn_experience_orbs(mut tx, amount, pos)
}

// block_item_name is the item a block turns into when it comes up whole, empty
// when it has no item form at all.
fn (s &NetworkSession) block_item_name(block_id int) string {
	item_id := s.hub.data.item_for_block(block_id)
	if item_id == 0 {
		return ''
	}
	return s.hub.data.item_name(item_id)
}
