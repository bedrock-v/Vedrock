module enchant

import nbt

fn test_defaults_registered() {
	r := new_registry()
	sharpness := r.get(id_sharpness)?
	assert sharpness.name() == 'sharpness'
	assert sharpness.max_level() == 5
	assert r.get_by_name('mending')?.id() == id_mending
	assert r.len() >= 38
}

fn test_custom_id_range_and_conflicts() {
	mut r := new_registry()
	assert r.next_custom_id() == custom_enchantment_id_start
	assert !r.register(SimpleEnchantment{ eid: id_sharpness, ident: 'my_sharpness' })
	assert !r.register(SimpleEnchantment{ eid: 999, ident: 'sharpness' })
	assert r.register(SimpleEnchantment{
		eid:   r.next_custom_id()
		ident: 'lifesteal'
	})
	assert r.get_by_name('lifesteal')?.id() == custom_enchantment_id_start
	assert r.next_custom_id() == custom_enchantment_id_start + 1
}

fn test_can_enchant_matches_items() {
	r := new_registry()
	sharpness := r.get(id_sharpness)?
	assert sharpness.can_enchant('minecraft:diamond_sword')
	assert !sharpness.can_enchant('minecraft:diamond_hoe')
	unbreaking := r.get(id_unbreaking)?
	assert unbreaking.can_enchant('minecraft:anything')
}

fn test_bonuses_sum_over_applied() {
	r := new_registry()
	applied := [
		Applied{
			eid:   id_sharpness
			level: 3
		},
	]
	assert r.attack_bonus(applied) == 3.75
	armor := [
		Applied{
			eid:   id_protection
			level: 4
		},
	]
	assert r.protection_factor(armor) == 4.0
}

fn test_ench_nbt_layout() {
	tag := ench_nbt([
		Applied{
			eid:   id_sharpness
			level: 3
		},
	])
	list := tag as nbt.List
	assert list.values.len == 1
	entry := list.values[0] as nbt.Compound
	assert entry.get('id')? as i16 == i16(id_sharpness)
	assert entry.get('lvl')? as i16 == 3
}
