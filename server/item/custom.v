module item

import nbt

// Runtime ids for custom items start well above the vanilla palette so they
// never collide with it.
pub const custom_item_runtime_id_start = 10000

// FoodComponent makes a custom item edible.
pub struct FoodComponent {
pub:
	nutrition      int
	saturation     f32
	can_always_eat bool
}

// WearableComponent makes a custom item equippable as armor. Slot is a vanilla
// slot string like 'slot.armor.head', 'slot.armor.chest', 'slot.armor.legs',
// 'slot.armor.feet'.
pub struct WearableComponent {
pub:
	slot       string
	protection int
}

// CooldownComponent gives the item a use cooldown, grouped by category.
pub struct CooldownComponent {
pub:
	category string
	duration f32
}

// EnchantableComponent controls which enchantment slot the item accepts and
// its enchantability value.
pub struct EnchantableComponent {
pub:
	slot  string
	value int
}

// DurabilityComponent gives the item a durability bar.
pub struct DurabilityComponent {
pub:
	max_durability int
}

// DiggerSpeed is one block (or block tag query) the item digs faster.
pub struct DiggerSpeed {
pub:
	block string
	speed int
}

// CustomItemDefinition describes a data-driven item a plugin registers. The
// definition is turned into component NBT and shipped to the client inside the
// ItemRegistryPacket, so no resource pack code is needed server-side beyond
// the texture name.
pub struct CustomItemDefinition {
pub mut:
	id                      string
	display_name            string
	texture                 string
	max_stack_size          int = 64
	attack_damage_value     int
	hand_equipped           bool
	allow_off_hand          bool
	glint                   bool
	can_destroy_in_creative bool = true
	mining_speed            f32  = 1.0
	fuel_duration           f32
	creative_group_index    int
	tags                    []string
	digger_speeds           []DiggerSpeed
	food                    ?FoodComponent
	wearable                ?WearableComponent
	cooldown                ?CooldownComponent
	enchantable             ?EnchantableComponent
	durability_component    ?DurabilityComponent
	runtime_id              int
}

fn value_compound(v nbt.Tag) nbt.Tag {
	mut c := nbt.new_compound()
	c.set('value', v)
	return nbt.Tag(c)
}

fn bool_byte(v bool) nbt.Tag {
	if v {
		return nbt.Tag(i8(1))
	}
	return nbt.Tag(i8(0))
}

fn (d &CustomItemDefinition) icon_compound() nbt.Tag {
	mut textures := nbt.new_compound()
	textures.set('default', nbt.Tag(d.texture))
	mut icon := nbt.new_compound()
	icon.set('textures', nbt.Tag(textures))
	return nbt.Tag(icon)
}

// components builds the component NBT the client consumes: an item_properties
// compound for the base properties and one minecraft:* compound per opted-in
// component.
pub fn (d &CustomItemDefinition) components() nbt.RootTag {
	mut props := nbt.new_compound()
	props.set('allow_off_hand', bool_byte(d.allow_off_hand))
	props.set('can_destroy_in_creative', bool_byte(d.can_destroy_in_creative))
	props.set('creative_category', nbt.Tag(i32(4)))
	props.set('damage', nbt.Tag(i32(d.attack_damage_value)))
	props.set('foil', bool_byte(d.glint))
	props.set('hand_equipped', bool_byte(d.hand_equipped))
	props.set('liquid_clipped', bool_byte(false))
	props.set('max_stack_size', nbt.Tag(i32(d.max_stack_size)))
	props.set('mining_speed', nbt.Tag(f32(d.mining_speed)))
	props.set('should_despawn', bool_byte(true))
	props.set('stacked_by_data', bool_byte(false))
	props.set('use_animation', nbt.Tag(i32(0)))
	props.set('use_duration', nbt.Tag(i32(0)))
	props.set('minecraft:icon', d.icon_compound())

	mut comp := nbt.new_compound()
	comp.set('item_properties', nbt.Tag(props))
	name := if d.display_name == '' { d.id } else { d.display_name }
	comp.set('minecraft:display_name', value_compound(nbt.Tag(name)))
	comp.set('minecraft:icon', d.icon_compound())
	if dur := d.durability_component {
		mut c := nbt.new_compound()
		c.set('max_durability', nbt.Tag(i32(dur.max_durability)))
		comp.set('minecraft:durability', nbt.Tag(c))
	}
	if food := d.food {
		mut c := nbt.new_compound()
		c.set('can_always_eat', bool_byte(food.can_always_eat))
		c.set('nutrition', nbt.Tag(i32(food.nutrition)))
		c.set('saturation_modifier', nbt.Tag(f32(food.saturation)))
		comp.set('minecraft:food', nbt.Tag(c))
	}
	if wear := d.wearable {
		mut c := nbt.new_compound()
		c.set('slot', nbt.Tag(wear.slot))
		c.set('protection', nbt.Tag(i32(wear.protection)))
		comp.set('minecraft:wearable', nbt.Tag(c))
	}
	if cd := d.cooldown {
		mut c := nbt.new_compound()
		c.set('category', nbt.Tag(cd.category))
		c.set('duration', nbt.Tag(f32(cd.duration)))
		comp.set('minecraft:cooldown', nbt.Tag(c))
	}
	if ench := d.enchantable {
		mut c := nbt.new_compound()
		c.set('slot', nbt.Tag(ench.slot))
		c.set('value', nbt.Tag(i32(ench.value)))
		comp.set('minecraft:enchantable', nbt.Tag(c))
	}
	if d.fuel_duration > 0 {
		mut c := nbt.new_compound()
		c.set('duration', nbt.Tag(f32(d.fuel_duration)))
		comp.set('minecraft:fuel', nbt.Tag(c))
	}
	if d.digger_speeds.len > 0 {
		mut speeds := []nbt.Tag{}
		for ds in d.digger_speeds {
			mut entry := nbt.new_compound()
			mut blk := nbt.new_compound()
			blk.set('name', nbt.Tag(ds.block))
			entry.set('block', nbt.Tag(blk))
			entry.set('speed', nbt.Tag(i32(ds.speed)))
			speeds << nbt.Tag(entry)
		}
		mut c := nbt.new_compound()
		c.set('destroy_speeds', nbt.Tag(nbt.List{
			element_type: nbt.tag_compound
			values:       speeds
		}))
		c.set('use_efficiency', bool_byte(true))
		comp.set('minecraft:digger', nbt.Tag(c))
	}
	if d.tags.len > 0 {
		mut tag_values := []nbt.Tag{}
		for t in d.tags {
			tag_values << nbt.Tag(t)
		}
		mut c := nbt.new_compound()
		c.set('tags', nbt.Tag(nbt.List{
			element_type: nbt.tag_string
			values:       tag_values
		}))
		comp.set('minecraft:tags', nbt.Tag(c))
	}

	mut root := nbt.new_compound()
	root.set('components', nbt.Tag(comp))
	root.set('id', nbt.Tag(i32(d.runtime_id)))
	root.set('name', nbt.Tag(d.id))
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(root)
	}
}

// CustomItemClass adapts a definition to the Item interface so the session
// layer treats custom items like any built-in class.
pub struct CustomItemClass {
pub:
	def CustomItemDefinition
}

pub fn (c CustomItemClass) identifier() string {
	return c.def.id
}

pub fn (c CustomItemClass) max_stack_size() int {
	return c.def.max_stack_size
}

pub fn (c CustomItemClass) attack_damage() f32 {
	return f32(c.def.attack_damage_value)
}

pub fn (c CustomItemClass) nutrition() int {
	if food := c.def.food {
		return food.nutrition
	}
	return 0
}

pub fn (c CustomItemClass) saturation() f32 {
	if food := c.def.food {
		return food.saturation
	}
	return 0
}

pub fn (c CustomItemClass) block_runtime_id() int {
	return 0
}

pub fn (c CustomItemClass) durability() int {
	if dur := c.def.durability_component {
		return dur.max_durability
	}
	return 0
}

pub fn (c CustomItemClass) mining_speed() f32 {
	return c.def.mining_speed
}

pub fn (c CustomItemClass) armor_points() int {
	if wear := c.def.wearable {
		return wear.protection
	}
	return 0
}

// CustomRegistry owns every registered custom item definition and hands out
// runtime ids sequentially, starting at custom_item_runtime_id_start.
pub struct CustomRegistry {
mut:
	defs    []CustomItemDefinition
	ids     map[string]int
	next_id int = custom_item_runtime_id_start
}

pub fn new_custom_registry() CustomRegistry {
	return CustomRegistry{}
}

// register allocates a runtime id for def and stores it. Registering the same
// id again returns the previously allocated runtime id unchanged.
pub fn (mut r CustomRegistry) register(def CustomItemDefinition) int {
	if existing := r.ids[def.id] {
		return existing
	}
	mut stored := def
	stored.runtime_id = r.next_id
	r.next_id++
	r.ids[def.id] = stored.runtime_id
	r.defs << stored
	return stored.runtime_id
}

// all returns every registered definition with its runtime id filled in.
pub fn (r &CustomRegistry) all() []CustomItemDefinition {
	return r.defs
}

pub fn (r &CustomRegistry) len() int {
	return r.defs.len
}

pub fn (r &CustomRegistry) runtime_id(id string) ?int {
	return r.ids[id] or { return none }
}

pub fn (r &CustomRegistry) names() []string {
	mut out := []string{cap: r.defs.len}
	for def in r.defs {
		out << def.id
	}
	return out
}
