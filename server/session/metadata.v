module session

import bedrock_v.protocol.current as proto

fn entity_flag_bit(index int) i64 {
	return i64(u64(1) << u64(index))
}

fn visible_name_metadata(name string) []proto.DataItem {
	flags := entity_flag_bit(proto.entity_flag_breathing) | entity_flag_bit(proto.entity_flag_can_climb) | entity_flag_bit(proto.entity_flag_has_collision) | entity_flag_bit(proto.entity_flag_affected_by_gravity) | entity_flag_bit(proto.entity_flag_show_name) | entity_flag_bit(proto.entity_flag_always_show_name)
	return [
		proto.DataItem{
			data_item_id:   proto.meta_key_flags
			data_item_type: proto.DataItemInt64{
				value: flags
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_color_index
			data_item_type: proto.DataItemByte{
				value: 0
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_name
			data_item_type: proto.DataItemString{
				value: name
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_effect_color
			data_item_type: proto.DataItemInt{
				value: 0
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_effect_ambience
			data_item_type: proto.DataItemByte{
				value: 0
			}
		},
		proto.DataItem{
			// See entity.metadata_entries()'s own comment - every actor
			// needs an explicit scale or a real client has
			// nothing to size the model by. Players had the same gap.
			data_item_id:   proto.meta_key_scale
			data_item_type: proto.DataItemFloat{
				value: f32(1.0)
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_width
			data_item_type: proto.DataItemFloat{
				value: 0.6
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_height
			data_item_type: proto.DataItemFloat{
				value: 1.8
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_always_show_name_tag
			data_item_type: proto.DataItemByte{
				value: 1
			}
		},
	]
}

fn (s &NetworkSession) set_actor_data() &proto.SetActorDataPacket {
	return &proto.SetActorDataPacket{
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		actor_data:        visible_name_metadata(s.shown_name())
		synced_properties: proto.PropertySyncData{}
		tick:              0
	}
}
