module session

import bedrock_v.protocol
import server.player
import bedrock_v.protocol.packets
import bedrock_v.protocol.types

fn entity_flag_bit(index int) i64 {
	return i64(u64(1) << u64(index))
}

fn visible_name_metadata(name string) []types.DataItem {
	flags := entity_flag_bit(protocol.entity_flag_breathing) | entity_flag_bit(protocol.entity_flag_can_climb) | entity_flag_bit(protocol.entity_flag_has_collision) | entity_flag_bit(protocol.entity_flag_affected_by_gravity) | entity_flag_bit(protocol.entity_flag_show_name) | entity_flag_bit(protocol.entity_flag_always_show_name)
	return [
		types.DataItem{
			data_item_id:   protocol.meta_key_flags
			data_item_type: types.DataItemInt64{
				value: flags
			}
		},
		types.DataItem{
			data_item_id:   protocol.meta_key_color_index
			data_item_type: types.DataItemByte{
				value: 0
			}
		},
		types.DataItem{
			data_item_id:   protocol.meta_key_name
			data_item_type: types.DataItemString{
				value: name
			}
		},
		types.DataItem{
			data_item_id:   protocol.meta_key_effect_color
			data_item_type: types.DataItemInt{
				value: 0
			}
		},
		types.DataItem{
			data_item_id:   protocol.meta_key_effect_ambience
			data_item_type: types.DataItemByte{
				value: 0
			}
		},
		types.DataItem{
			// See entity.metadata_entries()'s own comment - every actor
			// needs an explicit scale or a real client has
			// nothing to size the model by. Players had the same gap.
			data_item_id:   protocol.meta_key_scale
			data_item_type: types.DataItemFloat{
				value: f32(1.0)
			}
		},
		types.DataItem{
			data_item_id:   protocol.meta_key_width
			data_item_type: types.DataItemFloat{
				value: 0.6
			}
		},
		types.DataItem{
			data_item_id:   protocol.meta_key_height
			data_item_type: types.DataItemFloat{
				value: 1.8
			}
		},
		types.DataItem{
			data_item_id:   protocol.meta_key_always_show_name_tag
			data_item_type: types.DataItemByte{
				value: 1
			}
		},
	]
}

fn (mut s NetworkSession) set_actor_data(p &player.Player) &packets.SetActorDataPacket {
	return &packets.SetActorDataPacket{
		target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(p.runtime_id()))
		actor_data:        visible_name_metadata(p.identity.display_name)
		synced_properties: types.PropertySyncData{}
		tick:              0
	}
}
