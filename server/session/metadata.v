module session

import protocol.version.v662.types as types_662
import protocol.version.v2168.packets as packets_2168
import protocol.version.v2168.types as types_2168
import protocol.version.v2168.enums as enums_2168
import server.internal.network

fn entity_flag_bit(index int) i64 {
	return i64(u64(1) << u64(index))
}

fn visible_name_metadata(name string) []types_2168.DataItem {
	flags := entity_flag_bit(network.entity_flag_breathing) | entity_flag_bit(network.entity_flag_can_climb) | entity_flag_bit(network.entity_flag_has_collision) | entity_flag_bit(network.entity_flag_affected_by_gravity) | entity_flag_bit(network.entity_flag_show_name) | entity_flag_bit(network.entity_flag_always_show_name)
	return [
		types_2168.DataItem{
			data_item_id:   network.meta_key_flags
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemInt64{
				value: flags
			})
		},
		types_2168.DataItem{
			data_item_id:   network.meta_key_color_index
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemByte{
				value: 0
			})
		},
		types_2168.DataItem{
			data_item_id:   network.meta_key_name
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemString{
				value: name
			})
		},
		types_2168.DataItem{
			data_item_id:   network.meta_key_effect_color
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemInt{
				value: 0
			})
		},
		types_2168.DataItem{
			data_item_id:   network.meta_key_effect_ambience
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemByte{
				value: 0
			})
		},
		types_2168.DataItem{
			// See entity.metadata_entries()'s own comment - every actor
			// needs an explicit scale or a real client has
			// nothing to size the model by. Players had the same gap.
			data_item_id:   network.meta_key_scale
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemFloat{
				value: f32(1.0)
			})
		},
		types_2168.DataItem{
			data_item_id:   network.meta_key_width
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemFloat{
				value: 0.6
			})
		},
		types_2168.DataItem{
			data_item_id:   network.meta_key_height
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemFloat{
				value: 1.8
			})
		},
		types_2168.DataItem{
			data_item_id:   network.meta_key_always_show_name_tag
			data_item_type: enums_2168.DataItemType(enums_2168.DataItemByte{
				value: 1
			})
		},
	]
}

fn (s &NetworkSession) set_actor_data() &packets_2168.SetActorDataPacket {
	return &packets_2168.SetActorDataPacket{
		target_runtime_id: network.actor_runtime_id(s.runtime_id)
		actor_data:        visible_name_metadata(s.player.identity.display_name)
		synced_properties: types_662.PropertySyncData{}
		tick:              0
	}
}
