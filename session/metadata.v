module session

import protocol
import protocol.types

const meta_key_flags = u32(0)
const meta_key_name = u32(4)
const meta_key_always_show_name_tag = u32(80)
const entity_flag_show_name = 14
const entity_flag_always_show_name = 15
const entity_flag_can_climb = 19
const entity_flag_breathing = 35
const entity_flag_has_collision = 48
const entity_flag_affected_by_gravity = 49

fn entity_flag_bit(index int) i64 {
	return i64(1) << i64(index)
}

fn visible_name_metadata(name string) []types.MetadataEntry {
	flags := entity_flag_bit(entity_flag_breathing) | entity_flag_bit(entity_flag_can_climb) 
	| entity_flag_bit(entity_flag_has_collision) | entity_flag_bit(entity_flag_affected_by_gravity) | entity_flag_bit(entity_flag_show_name) 
	| entity_flag_bit(entity_flag_always_show_name)
	return [
		types.MetadataEntry{
			key:   meta_key_flags
			value: types.MetaLong{
				value: flags
			}
		},
		types.MetadataEntry{
			key:   meta_key_name
			value: types.MetaString{
				value: name
			}
		},
		types.MetadataEntry{
			key:   meta_key_always_show_name_tag
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
