module item

import server.effect

fn test_potion_meta_maps_to_effects() {
	p := potion_from_meta(21)
	effects := p.effects()

	assert p.id() == 21
	assert effects.len == 1
	assert effects[0].effect_type() == effect.instant_health
	assert effects[0].level() == 1
	assert effects[0].instant()
}

fn test_registered_potion_is_consumable_and_returns_bottle() {
	r := new_registry()
	it := r.get('minecraft:potion') or { panic('missing potion') }

	assert it.max_stack_size() == 1
	assert it is PotionItem
	assert it is ConsumableItem
	if it is PotionItem {
		result := it.consume_result(21)
		assert result.effects.len == 1
		assert result.effects[0].effect_type() == effect.instant_health
		assert result.replacement_id == 'minecraft:glass_bottle'
		assert result.replacement_count == 1
		assert result.sound == 'random.drink'
	}
}

fn test_registry_consume_result_works_for_potion() {
	r := new_registry()
	result := r.consume_result('minecraft:potion', 21) or { panic('expected ConsumeResult') }
	assert result.effects.len == 1
	assert result.sound == 'random.drink'
}

fn test_registry_consume_result_returns_none_for_non_consumable() {
	r := new_registry()
	if _ := r.consume_result('minecraft:stick', 0) {
		assert false, 'stick should not be consumable'
	}
}
