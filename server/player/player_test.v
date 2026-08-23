module player

import protocol.types
import server.internal.auth

fn test_new_player_defaults() {
	p := new_player()
	assert p.health == 20.0
	assert p.game_mode == .survival
	assert p.dead == false
	assert p.snapshot_slot_stacks().len == 0
}

fn test_player_field_mutation_through_pointer() {
	mut p := new_player()
	p.health = 12.5
	p.game_mode = .creative
	p.dead = true
	net_id := p.track_stack(types.ItemStack{})
	p.set_slot(0, net_id)
	assert p.health == 12.5
	assert p.game_mode == .creative
	assert p.dead == true
	assert p.snapshot_slot_stacks().len == 1
}

fn test_name_and_has_permission() {
	mut p := new_player()
	p.identity = auth.Identity{
		display_name: 'Steve'
	}
	assert p.name() == 'Steve'
	assert p.has_permission('vedrock.some.node') == false
	p.perm.set_permission('vedrock.some.node', true)
	assert p.has_permission('vedrock.some.node') == true
}

struct ProbeHolder {
mut:
	player &Player = unsafe { nil }
}

fn test_probe_heap_field_on_plain_literal() {
	mut h := ProbeHolder{
		player: new_player()
	}
	h.player.health = 7.0
	assert h.player.health == 7.0
	net_id := h.player.track_stack(types.ItemStack{})
	h.player.set_slot(5, net_id)
	assert h.player.snapshot_slot_stacks()[5].count == 0
}
