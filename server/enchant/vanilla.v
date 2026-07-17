module enchant

pub const id_protection = 0
pub const id_fire_protection = 1
pub const id_feather_falling = 2
pub const id_blast_protection = 3
pub const id_projectile_protection = 4
pub const id_thorns = 5
pub const id_respiration = 6
pub const id_depth_strider = 7
pub const id_aqua_affinity = 8
pub const id_sharpness = 9
pub const id_smite = 10
pub const id_bane_of_arthropods = 11
pub const id_knockback = 12
pub const id_fire_aspect = 13
pub const id_looting = 14
pub const id_efficiency = 15
pub const id_silk_touch = 16
pub const id_unbreaking = 17
pub const id_fortune = 18
pub const id_power = 19
pub const id_punch = 20
pub const id_flame = 21
pub const id_infinity = 22
pub const id_luck_of_the_sea = 23
pub const id_lure = 24
pub const id_frost_walker = 25
pub const id_mending = 26
pub const id_curse_of_binding = 27
pub const id_curse_of_vanishing = 28
pub const id_impaling = 29
pub const id_riptide = 30
pub const id_loyalty = 31
pub const id_channeling = 32
pub const id_multishot = 33
pub const id_piercing = 34
pub const id_quick_charge = 35
pub const id_soul_speed = 36
pub const id_swift_sneak = 37

const armor_match = ['helmet', 'chestplate', 'leggings', 'boots']
const weapon_match = ['sword', 'axe']
const tool_match = ['pickaxe', 'shovel', 'axe', 'hoe']

// register_defaults registers the vanilla Bedrock enchantment set with their
// numeric ids and level caps.
pub fn register_defaults(mut r Registry) {
	r.register(SimpleEnchantment{
		eid:                  id_protection
		ident:                'protection'
		max_lvl:              4
		item_match:           armor_match
		protection_per_level: 1.0
	})
	r.register(SimpleEnchantment{
		eid:                  id_fire_protection
		ident:                'fire_protection'
		max_lvl:              4
		item_match:           armor_match
		protection_per_level: 2.0
	})
	r.register(SimpleEnchantment{
		eid:                  id_feather_falling
		ident:                'feather_falling'
		max_lvl:              4
		item_match:           ['boots']
		protection_per_level: 3.0
	})
	r.register(SimpleEnchantment{
		eid:                  id_blast_protection
		ident:                'blast_protection'
		max_lvl:              4
		item_match:           armor_match
		protection_per_level: 2.0
	})
	r.register(SimpleEnchantment{
		eid:                  id_projectile_protection
		ident:                'projectile_protection'
		max_lvl:              4
		item_match:           armor_match
		protection_per_level: 2.0
	})
	r.register(SimpleEnchantment{
		eid:        id_thorns
		ident:      'thorns'
		max_lvl:    3
		item_match: armor_match
	})
	r.register(SimpleEnchantment{
		eid:        id_respiration
		ident:      'respiration'
		max_lvl:    3
		item_match: ['helmet']
	})
	r.register(SimpleEnchantment{
		eid:        id_depth_strider
		ident:      'depth_strider'
		max_lvl:    3
		item_match: ['boots']
	})
	r.register(SimpleEnchantment{
		eid:        id_aqua_affinity
		ident:      'aqua_affinity'
		item_match: ['helmet']
	})
	r.register(SimpleEnchantment{
		eid:              id_sharpness
		ident:            'sharpness'
		max_lvl:          5
		item_match:       weapon_match
		attack_per_level: 1.25
	})
	r.register(SimpleEnchantment{
		eid:              id_smite
		ident:            'smite'
		max_lvl:          5
		item_match:       weapon_match
		attack_per_level: 2.5
	})
	r.register(SimpleEnchantment{
		eid:              id_bane_of_arthropods
		ident:            'bane_of_arthropods'
		max_lvl:          5
		item_match:       weapon_match
		attack_per_level: 2.5
	})
	r.register(SimpleEnchantment{
		eid:        id_knockback
		ident:      'knockback'
		max_lvl:    2
		item_match: ['sword']
	})
	r.register(SimpleEnchantment{
		eid:        id_fire_aspect
		ident:      'fire_aspect'
		max_lvl:    2
		item_match: ['sword']
	})
	r.register(SimpleEnchantment{
		eid:        id_looting
		ident:      'looting'
		max_lvl:    3
		item_match: ['sword']
	})
	r.register(SimpleEnchantment{
		eid:        id_efficiency
		ident:      'efficiency'
		max_lvl:    5
		item_match: tool_match
	})
	r.register(SimpleEnchantment{
		eid:        id_silk_touch
		ident:      'silk_touch'
		item_match: tool_match
	})
	r.register(SimpleEnchantment{
		eid:     id_unbreaking
		ident:   'unbreaking'
		max_lvl: 3
	})
	r.register(SimpleEnchantment{
		eid:        id_fortune
		ident:      'fortune'
		max_lvl:    3
		item_match: tool_match
	})
	r.register(SimpleEnchantment{
		eid:        id_power
		ident:      'power'
		max_lvl:    5
		item_match: ['bow']
	})
	r.register(SimpleEnchantment{
		eid:        id_punch
		ident:      'punch'
		max_lvl:    2
		item_match: ['bow']
	})
	r.register(SimpleEnchantment{
		eid:        id_flame
		ident:      'flame'
		item_match: ['bow']
	})
	r.register(SimpleEnchantment{
		eid:        id_infinity
		ident:      'infinity'
		item_match: ['bow']
	})
	r.register(SimpleEnchantment{
		eid:        id_luck_of_the_sea
		ident:      'luck_of_the_sea'
		max_lvl:    3
		item_match: ['fishing_rod']
	})
	r.register(SimpleEnchantment{
		eid:        id_lure
		ident:      'lure'
		max_lvl:    3
		item_match: ['fishing_rod']
	})
	r.register(SimpleEnchantment{
		eid:        id_frost_walker
		ident:      'frost_walker'
		max_lvl:    2
		item_match: ['boots']
	})
	r.register(SimpleEnchantment{
		eid:   id_mending
		ident: 'mending'
	})
	r.register(SimpleEnchantment{
		eid:        id_curse_of_binding
		ident:      'curse_of_binding'
		item_match: armor_match
	})
	r.register(SimpleEnchantment{
		eid:   id_curse_of_vanishing
		ident: 'curse_of_vanishing'
	})
	r.register(SimpleEnchantment{
		eid:              id_impaling
		ident:            'impaling'
		max_lvl:          5
		item_match:       ['trident']
		attack_per_level: 2.5
	})
	r.register(SimpleEnchantment{
		eid:        id_riptide
		ident:      'riptide'
		max_lvl:    3
		item_match: ['trident']
	})
	r.register(SimpleEnchantment{
		eid:        id_loyalty
		ident:      'loyalty'
		max_lvl:    3
		item_match: ['trident']
	})
	r.register(SimpleEnchantment{
		eid:        id_channeling
		ident:      'channeling'
		item_match: ['trident']
	})
	r.register(SimpleEnchantment{
		eid:        id_multishot
		ident:      'multishot'
		item_match: ['crossbow']
	})
	r.register(SimpleEnchantment{
		eid:        id_piercing
		ident:      'piercing'
		max_lvl:    4
		item_match: ['crossbow']
	})
	r.register(SimpleEnchantment{
		eid:        id_quick_charge
		ident:      'quick_charge'
		max_lvl:    3
		item_match: ['crossbow']
	})
	r.register(SimpleEnchantment{
		eid:        id_soul_speed
		ident:      'soul_speed'
		max_lvl:    3
		item_match: ['boots']
	})
	r.register(SimpleEnchantment{
		eid:        id_swift_sneak
		ident:      'swift_sneak'
		max_lvl:    3
		item_match: ['leggings']
	})
}
