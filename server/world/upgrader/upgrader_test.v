module upgrader

fn test_rename_schema_upgrades_block() {
	u := new_upgrader([
		Schema{
			id:          100
			renamed_ids: {
				'minecraft:grass': 'minecraft:grass_block'
			}
		},
	])
	out := u.upgrade(BlockState{
		name:    'minecraft:grass'
		version: 0
	})
	assert out.name == 'minecraft:grass_block'
	assert out.version == current_version
}

fn test_current_state_is_noop() {
	u := new_upgrader([
		Schema{
			id:          100
			renamed_ids: {
				'minecraft:grass': 'minecraft:grass_block'
			}
		},
	])
	out := u.upgrade(BlockState{
		name:    'minecraft:grass'
		version: current_version
	})
	assert out.name == 'minecraft:grass'
	assert out.version == current_version
}

fn test_ordered_multi_step_upgrade() {
	// grass -> grass_block at step 1, then grass_block -> lawn at step 2.
	// A block stored below both must end up as lawn, proving order matters.
	u := new_upgrader([
		Schema{
			id:          200
			renamed_ids: {
				'minecraft:grass_block': 'minecraft:lawn'
			}
		},
		Schema{
			id:          100
			renamed_ids: {
				'minecraft:grass': 'minecraft:grass_block'
			}
		},
	])
	out := u.upgrade(BlockState{
		name:    'minecraft:grass'
		version: 0
	})
	assert out.name == 'minecraft:lawn'
	assert out.version == current_version
}

fn test_skip_already_applied_schema() {
	// A block already at version 150 must not re-run step id 100.
	u := new_upgrader([
		Schema{
			id:          100
			renamed_ids: {
				'minecraft:grass': 'minecraft:grass_block'
			}
		},
	])
	out := u.upgrade(BlockState{
		name:    'minecraft:grass'
		version: 150
	})
	assert out.name == 'minecraft:grass'
}

fn test_state_remap_meta_to_block() {
	u := new_upgrader([
		Schema{
			id:              100
			remapped_states: {
				'minecraft:stone': [
					StateRemap{
						old_properties: {
							'stone_type': string_value('granite')
						}
						new_name:       'minecraft:granite'
					},
				]
			}
		},
	])
	mut props := map[string]StateValue{}
	props['stone_type'] = string_value('granite')
	out := u.upgrade(BlockState{
		name:       'minecraft:stone'
		properties: props
		version:    0
	})
	assert out.name == 'minecraft:granite'
	assert 'stone_type' !in out.properties
}

fn test_value_remap() {
	u := new_upgrader([
		Schema{
			id:              100
			remapped_values: {
				'minecraft:coral_fan': {
					'coral_direction': [
						ValueRemap{
							old: int_value(4)
							new: int_value(0)
						},
					]
				}
			}
		},
	])
	mut props := map[string]StateValue{}
	props['coral_direction'] = int_value(4)
	out := u.upgrade(BlockState{
		name:       'minecraft:coral_fan'
		properties: props
		version:    0
	})
	assert out.properties['coral_direction'].int_value == 0
}

fn test_default_upgrader_renames_grass() {
	u := default_upgrader()
	out := u.upgrade(BlockState{
		name:    'minecraft:grass'
		version: 0
	})
	assert out.name == 'minecraft:grass_block'
}
