module session

import protocol
import protocol.types

fn entity_flag_bit(index int) i64 {
	return i64(u64(1) << u64(index))
}

fn visible_name_metadata(name string) []types.MetadataEntry {
	flags := entity_flag_bit(protocol.entity_flag_breathing) | entity_flag_bit(protocol.entity_flag_can_climb) | entity_flag_bit(protocol.entity_flag_has_collision) | entity_flag_bit(protocol.entity_flag_affected_by_gravity) | entity_flag_bit(protocol.entity_flag_show_name) | entity_flag_bit(protocol.entity_flag_always_show_name)
	return [
		types.MetadataEntry{
			key:   protocol.meta_key_flags
			value: types.MetaLong{
				value: flags
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_color_index
			value: types.MetaByte{
				value: 0
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_name
			value: types.MetaString{
				value: name
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_effect_color
			value: types.MetaInt{
				value: 0
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_effect_ambience
			value: types.MetaByte{
				value: 0
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_width
			value: types.MetaFloat{
				value: 0.6
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_height
			value: types.MetaFloat{
				value: 1.8
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_always_show_name_tag
			value: types.MetaByte{
				value: 1
			}
		},
	]
}

fn (s &NetworkSession) set_actor_data() &protocol.SetActorDataPacket {
	return &protocol.SetActorDataPacket{
		actor_runtime_id:  s.runtime_id
		metadata:          visible_name_metadata(s.identity.display_name)
		synced_properties: types.PropertySyncData{}
		tick:              0
	}
}
