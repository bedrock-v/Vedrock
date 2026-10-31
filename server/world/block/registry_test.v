module block

import compress.gzip
import bedrock_v.nbt

fn test_every_state_hashes_to_its_network_id() {
	r := vanilla()
	data := gzip.decompress(palette_data)!
	root := nbt.decode(data, encoding: .big_endian)!.root.tag as nbt.Compound
	entries := (root.get('blocks')? as nbt.List).values
	assert r.len() == entries.len
	for i, entry in entries {
		want := u32((entry as nbt.Compound).get('network_id')? as i32)
		assert r.hash(u32(i)) == want, '${r.state(u32(i)).name} hashes to ${r.hash(u32(i))}, the client to ${want}'
	}
}

fn test_a_network_id_from_a_client_resolves_only_to_a_known_state() {
	r := vanilla()
	stone := r.id(State{
		name: 'minecraft:stone'
	}) or { panic('stone is not a block') }
	assert r.by_hash(r.hash(stone))? == stone
	assert r.state(r.air).name == 'minecraft:air'
	if _ := r.id(State{ name: 'minecraft:not_a_block' }) {
		assert false, 'a state that does not exist got an ID'
	}
}

fn test_a_state_is_found_whatever_order_its_properties_are_named_in() {
	r := vanilla()
	mut door := ?u32(none)
	for id in 0 .. r.len() {
		s := r.state(u32(id))
		if s.name == 'minecraft:warped_door' {
			door = u32(id)
			break
		}
	}
	id := door or { panic('no warped door') }
	s := r.state(id)
	reversed := State{
		name:       s.name
		properties: s.properties.reverse()
	}
	assert r.id(reversed)? == id, 'a door with its properties in another order was not found'
}
