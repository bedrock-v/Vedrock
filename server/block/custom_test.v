module block

import nbt

fn test_register_allocates_sequential_runtime_ids() {
	mut r := new_custom_registry()
	first := r.register(CustomBlockDefinition{ id: 'test:ruby_ore', texture: 'ruby_ore' })
	second := r.register(CustomBlockDefinition{ id: 'test:ruby_block', texture: 'ruby_block' })
	assert first == custom_block_runtime_id_start
	assert second == custom_block_runtime_id_start + 1
	assert r.runtime_id('test:ruby_ore')? == first
}

fn test_register_same_id_returns_existing() {
	mut r := new_custom_registry()
	first := r.register(CustomBlockDefinition{ id: 'test:ruby_ore', texture: 'a' })
	again := r.register(CustomBlockDefinition{ id: 'test:ruby_ore', texture: 'b' })
	assert first == again
	assert r.len() == 1
}

fn test_network_entry_layout() {
	mut r := new_custom_registry()
	r.register(CustomBlockDefinition{
		id:             'test:ruby_ore'
		display_name:   'Ruby Ore'
		texture:        'ruby_ore'
		break_hardness: 3.0
		light_emission: 7
	})
	def := r.all()[0]
	entry := def.network_entry()
	assert entry.name == 'test:ruby_ore'
	top := entry.properties.tag as nbt.Compound
	vanilla := top.get('vanilla_block_data')? as nbt.Compound
	assert vanilla.get('block_id')? as i32 == i32(custom_block_runtime_id_start)
	comp := top.get('components')? as nbt.Compound
	mining := comp.get('minecraft:destructible_by_mining')? as nbt.Compound
	assert mining.get('value')? as f32 == 3.0
	emission := comp.get('minecraft:light_emission')? as nbt.Compound
	assert emission.get('emission')? as i8 == 7
	materials := comp.get('minecraft:material_instances')? as nbt.Compound
	mats := materials.get('materials')? as nbt.Compound
	all_faces := mats.get('*')? as nbt.Compound
	assert all_faces.get('texture')? as string == 'ruby_ore'
	menu := top.get('menu_category')? as nbt.Compound
	assert menu.get('category')? as string == 'construction'
}

fn test_geometry_replaces_unit_cube() {
	def := CustomBlockDefinition{
		id:       'test:chair'
		texture:  'chair'
		geometry: 'geometry.chair'
	}
	entry := def.network_entry()
	top := entry.properties.tag as nbt.Compound
	comp := top.get('components')? as nbt.Compound
	geo := comp.get('minecraft:geometry')? as nbt.Compound
	assert geo.get('identifier')? as string == 'geometry.chair'
	assert comp.get('minecraft:unit_cube') == none
}
