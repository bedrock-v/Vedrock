module item

import nbt

fn test_register_allocates_sequential_runtime_ids() {
	mut r := new_custom_registry()
	first := r.register(CustomItemDefinition{ id: 'test:ruby', texture: 'ruby' })
	second := r.register(CustomItemDefinition{ id: 'test:sapphire', texture: 'sapphire' })
	assert first == custom_item_runtime_id_start
	assert second == custom_item_runtime_id_start + 1
	assert r.len() == 2
	assert r.runtime_id('test:ruby')? == first
}

fn test_register_same_id_returns_existing() {
	mut r := new_custom_registry()
	first := r.register(CustomItemDefinition{ id: 'test:ruby', texture: 'ruby' })
	again := r.register(CustomItemDefinition{ id: 'test:ruby', texture: 'other' })
	assert first == again
	assert r.len() == 1
}

fn test_components_carry_icon_and_display_name() {
	mut r := new_custom_registry()
	r.register(CustomItemDefinition{
		id:           'test:ruby'
		display_name: 'Ruby'
		texture:      'ruby'
	})
	def := r.all()[0]
	root := def.components()
	top := root.tag as nbt.Compound
	comp := top.get('components')? as nbt.Compound
	name_tag := comp.get('minecraft:display_name')? as nbt.Compound
	assert name_tag.get('value')? as string == 'Ruby'
	icon := comp.get('minecraft:icon')? as nbt.Compound
	textures := icon.get('textures')? as nbt.Compound
	assert textures.get('default')? as string == 'ruby'
	assert top.get('name')? as string == 'test:ruby'
	assert top.get('id')? as i32 == i32(custom_item_runtime_id_start)
}

fn test_food_component_serialized_when_set() {
	def := CustomItemDefinition{
		id:      'test:pie'
		texture: 'pie'
		food:    FoodComponent{
			nutrition:  8
			saturation: 0.6
		}
	}
	root := def.components()
	top := root.tag as nbt.Compound
	comp := top.get('components')? as nbt.Compound
	food := comp.get('minecraft:food')? as nbt.Compound
	assert food.get('nutrition')? as i32 == 8
}

fn test_custom_item_class_implements_item() {
	def := CustomItemDefinition{
		id:                   'test:blade'
		texture:              'blade'
		max_stack_size:       1
		attack_damage_value:  7
		durability_component: DurabilityComponent{
			max_durability: 500
		}
	}
	c := CustomItemClass{
		def: def
	}
	assert c.identifier() == 'test:blade'
	assert c.max_stack_size() == 1
	assert c.attack_damage() == 7.0
	assert c.durability() == 500
	assert c.nutrition() == 0
}
