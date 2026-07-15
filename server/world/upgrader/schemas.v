module upgrader

// default_upgrader returns the upgrader seeded with a small but representative
// set of real Bedrock upgrade steps. This is a starting set - the full
// worldupgrader schema data is large, so only a handful of well-known
// transforms live here. Extend by adding more Schema entries with higher ids.
pub fn default_upgrader() Upgrader {
	return new_upgrader(seed_schemas())
}

fn seed_schemas() []Schema {
	return [
		// Step 1 - the classic grass rename. Bedrock renamed minecraft:grass to
		// minecraft:grass_block in 1.20.60.
		Schema{
			id:          17825806
			renamed_ids: {
				'minecraft:grass': 'minecraft:grass_block'
				'minecraft:scute': 'minecraft:turtle_scute'
			}
		},
		// Step 2 - stone flattening. Old stone carried a stone_type string; each
		// value became its own block. This is the meta/value -> distinct block
		// pattern, done here as a state remap that drops the property.
		Schema{
			id:              17879555
			remapped_states: {
				'minecraft:stone': [
					StateRemap{
						old_properties: {
							'stone_type': string_value('granite')
						}
						new_name:       'minecraft:granite'
					},
					StateRemap{
						old_properties: {
							'stone_type': string_value('diorite')
						}
						new_name:       'minecraft:diorite'
					},
					StateRemap{
						old_properties: {
							'stone_type': string_value('andesite')
						}
						new_name:       'minecraft:andesite'
					},
				]
			}
		},
		// Step 3 - property value remap. Old coral fan blocks stored a numeric
		// coral_direction; nothing renames, we just normalise a legacy value and
		// make sure the infiniburn flag exists on bedrock.
		Schema{
			id:               18090528
			added_properties: {
				'minecraft:bedrock': {
					'infiniburn_bit': byte_value(0)
				}
			}
			remapped_values:  {
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
	]
}
