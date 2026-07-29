module network

import protocol
import protocol.version
import protocol.version.v662.enums as enums_662
import protocol.version.v1001

pub const selected_protocol = 1001
pub const selected_minecraft_version = '1.26.30'
pub const selected_player_auth_input_packet = u16(144)

pub const difficulty_peaceful = int(0)
pub const difficulty_easy = int(1)
pub const difficulty_normal = int(2)
pub const difficulty_hard = int(3)

pub const game_type_survival = int(0)
pub const game_type_creative = int(1)
pub const game_type_adventure = int(2)
pub const game_type_survival_spectator = int(3)
pub const game_type_creative_spectator = int(4)
pub const game_type_default = int(5)
pub const game_type_spectator = int(6)

pub const ability_build = int(enums_662.AbilitiesIndex.build)
pub const ability_mine = int(enums_662.AbilitiesIndex.mine)
pub const ability_doors_and_switches = int(enums_662.AbilitiesIndex.doors_and_switches)
pub const ability_open_containers = int(enums_662.AbilitiesIndex.open_containers)
pub const ability_attack_players = int(enums_662.AbilitiesIndex.attack_players)
pub const ability_attack_mobs = int(enums_662.AbilitiesIndex.attack_mobs)
pub const ability_may_fly = int(enums_662.AbilitiesIndex.may_fly)
pub const ability_instabuild = int(enums_662.AbilitiesIndex.instabuild)
pub const ability_walk_speed = int(enums_662.AbilitiesIndex.walk_speed)
pub const ability_count = int(enums_662.AbilitiesIndex.ability_count)

pub const meta_key_flags = u32(0)
pub const meta_key_color_index = u32(3)
pub const meta_key_name = u32(4)
pub const meta_key_effect_color = u32(8)
pub const meta_key_effect_ambience = u32(9)
pub const meta_key_scale = u32(38)
pub const meta_key_width = u32(53)
pub const meta_key_height = u32(54)
pub const meta_key_always_show_name_tag = u32(81)

pub const entity_flag_show_name = 14
pub const entity_flag_always_show_name = 15
pub const entity_flag_can_climb = 19
pub const entity_flag_breathing = 35
pub const entity_flag_has_collision = 48
pub const entity_flag_affected_by_gravity = 49

pub const move_actor_flag_on_ground = int(1)
pub const level_event_particles_destroy_block = int(2001)

pub fn selected_proto_version() version.ProtoVersion {
	return version.ProtoVersion.v1001
}

pub fn new_selected_packet_pool() protocol.PacketPool {
	return v1001.new_pool()
}
