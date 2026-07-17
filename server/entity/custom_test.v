module entity

import nbt

fn test_register_allocates_ids_and_rejects_duplicates() {
	mut r := new_custom_registry()
	assert r.register(CustomEntityDefinition{ id: 'test:fire_golem' })
	assert !r.register(CustomEntityDefinition{ id: 'test:fire_golem' })
	assert r.register(CustomEntityDefinition{ id: 'test:ice_golem' })
	assert r.len() == 2
	assert r.all()[0].runtime_id == custom_entity_runtime_id_start
	assert r.all()[1].runtime_id == custom_entity_runtime_id_start + 1
}

fn test_short_name_strips_namespace() {
	def := CustomEntityDefinition{
		id: 'myplugin:fire_golem'
	}
	assert def.short_name() == 'fire_golem'
	bare := CustomEntityDefinition{
		id: 'golem'
	}
	assert bare.short_name() == 'golem'
}

fn test_identifiers_nbt_layout() {
	mut r := new_custom_registry()
	r.register(CustomEntityDefinition{
		id:            'test:fire_golem'
		has_spawn_egg: true
	})
	root := r.identifiers_nbt()
	top := root.tag as nbt.Compound
	idlist := top.get('idlist')? as nbt.List
	assert idlist.values.len == 1
	entry := idlist.values[0] as nbt.Compound
	assert entry.get('id')? as string == 'test:fire_golem'
	assert entry.get('rid')? as i32 == i32(custom_entity_runtime_id_start)
	assert entry.get('summonable')? as i8 == 1
	assert entry.get('hasspawnegg')? as i8 == 1
}
