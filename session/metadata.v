module session

import protocol
import protocol.types

const meta_key_flags = u32(0)
const entity_flag_can_climb = 19
const entity_flag_breathing = 35
const entity_flag_has_collision = 48
const entity_flag_affected_by_gravity = 49

fn entity_flag_bit(index int) i64 {
	return i64(1) << i64(index)
}

fn (s &NetworkSession) set_actor_data() &protocol.SetActorDataPacket {
	flags := entity_flag_bit(entity_flag_breathing) | entity_flag_bit(entity_flag_can_climb) | entity_flag_bit(entity_flag_has_collision) | entity_flag_bit(entity_flag_affected_by_gravity)
	return &protocol.SetActorDataPacket{
		actor_runtime_id:  s.runtime_id
		metadata:          [
			types.MetadataEntry{
				key:   meta_key_flags
				value: types.MetaLong{
					value: flags
				}
			},
		]
		synced_properties: types.PropertySyncData{}
		tick:              0
	}
}
