module block

import nbt

// Runtime ids for custom blocks start above the vanilla palette so they never
// collide with it.
pub const custom_block_runtime_id_start = 10000

// MaterialInstance is the render description for one face (or '*' for all).
pub struct MaterialInstance {
pub:
	face          string = '*'
	texture       string
	render_method string = 'opaque'
}

// BoxComponent is a collision or selection box: origin is the corner offset
// from the block origin (-8..8), size the extent in pixels (0..16).
pub struct BoxComponent {
pub:
	origin_x f32 = -8.0
	origin_y f32
	origin_z f32 = -8.0
	size_x   f32 = 16.0
	size_y   f32 = 16.0
	size_z   f32 = 16.0
}

// CustomBlockDefinition describes a data-driven block a plugin registers. It
// is serialized to block property NBT and shipped in the StartGamePacket
// blocks list so the client can build render state for it.
pub struct CustomBlockDefinition {
pub mut:
	id                   string
	display_name         string
	texture              string
	geometry             string
	materials            []MaterialInstance
	friction             f32 = 0.4
	break_hardness       f32 = 1.0
	explosion_resistance int = 5
	light_emission       int
	light_dampening      int = 15
	map_color            string
	creative_category    string = 'construction'
	creative_group       string
	collision            ?BoxComponent
	selection            ?BoxComponent
	runtime_id           int
}

// NetworkEntry is the wire form of a custom block: the name plus the block
// property NBT the session layer wraps into a protocol.BlockEntry.
pub struct NetworkEntry {
pub:
	name       string
	properties nbt.RootTag
}

fn float_list(values []f32) nbt.Tag {
	mut tags := []nbt.Tag{cap: values.len}
	for v in values {
		tags << nbt.Tag(v)
	}
	return nbt.Tag(nbt.List{
		element_type: nbt.tag_float
		values:       tags
	})
}

fn byte_flag(v bool) nbt.Tag {
	if v {
		return nbt.Tag(i8(1))
	}
	return nbt.Tag(i8(0))
}

fn (d &CustomBlockDefinition) material_instances() nbt.Tag {
	mut materials := nbt.new_compound()
	mut instances := d.materials.clone()
	if instances.len == 0 {
		instances << MaterialInstance{
			texture: d.texture
		}
	}
	for inst in instances {
		mut m := nbt.new_compound()
		m.set('texture', nbt.Tag(inst.texture))
		m.set('render_method', nbt.Tag(inst.render_method))
		m.set('ambient_occlusion', byte_flag(true))
		m.set('face_dimming', byte_flag(true))
		materials.set(inst.face, nbt.Tag(m))
	}
	mut c := nbt.new_compound()
	c.set('mappings', nbt.Tag(nbt.new_compound()))
	c.set('materials', nbt.Tag(materials))
	return nbt.Tag(c)
}

fn box_compound(box BoxComponent) nbt.Tag {
	mut c := nbt.new_compound()
	c.set('enabled', byte_flag(true))
	c.set('origin', float_list([box.origin_x, box.origin_y, box.origin_z]))
	c.set('size', float_list([box.size_x, box.size_y, box.size_z]))
	return nbt.Tag(c)
}

fn value_compound(v nbt.Tag) nbt.Tag {
	mut c := nbt.new_compound()
	c.set('value', v)
	return nbt.Tag(c)
}

// network_entry builds the block property NBT: a components compound,
// menu_category, molang version and the allocated runtime id under
// vanilla_block_data.
pub fn (d &CustomBlockDefinition) network_entry() NetworkEntry {
	mut comp := nbt.new_compound()
	name := if d.display_name == '' { d.id } else { d.display_name }
	comp.set('minecraft:display_name', value_compound(nbt.Tag(name)))
	comp.set('minecraft:friction', value_compound(nbt.Tag(f32(d.friction))))
	comp.set('minecraft:destructible_by_mining', value_compound(nbt.Tag(f32(d.break_hardness))))
	mut explosion := nbt.new_compound()
	explosion.set('explosion_resistance', nbt.Tag(i32(d.explosion_resistance)))
	comp.set('minecraft:destructible_by_explosion', nbt.Tag(explosion))
	mut dampening := nbt.new_compound()
	dampening.set('lightLevel', nbt.Tag(i8(d.light_dampening)))
	comp.set('minecraft:light_dampening', nbt.Tag(dampening))
	mut emission := nbt.new_compound()
	emission.set('emission', nbt.Tag(i8(d.light_emission)))
	comp.set('minecraft:light_emission', nbt.Tag(emission))
	if d.map_color != '' {
		comp.set('minecraft:map_color', value_compound(nbt.Tag(d.map_color)))
	}
	comp.set('minecraft:material_instances', d.material_instances())
	if d.geometry != '' {
		mut geo := nbt.new_compound()
		geo.set('identifier', nbt.Tag(d.geometry))
		geo.set('bone_visibility', nbt.Tag(nbt.new_compound()))
		comp.set('minecraft:geometry', nbt.Tag(geo))
	} else {
		comp.set('minecraft:unit_cube', nbt.Tag(nbt.new_compound()))
	}
	if col := d.collision {
		comp.set('minecraft:collision_box', box_compound(col))
	}
	if sel := d.selection {
		comp.set('minecraft:selection_box', box_compound(sel))
	}

	mut menu := nbt.new_compound()
	menu.set('category', nbt.Tag(d.creative_category))
	menu.set('group', nbt.Tag(d.creative_group))
	menu.set('is_hidden_in_commands', byte_flag(false))

	mut vanilla := nbt.new_compound()
	vanilla.set('block_id', nbt.Tag(i32(d.runtime_id)))

	mut root := nbt.new_compound()
	root.set('components', nbt.Tag(comp))
	root.set('menu_category', nbt.Tag(menu))
	root.set('molangVersion', nbt.Tag(i32(1)))
	root.set('vanilla_block_data', nbt.Tag(vanilla))
	root.set('properties', nbt.Tag(nbt.List{
		element_type: nbt.tag_compound
		values:       []nbt.Tag{}
	}))
	root.set('permutations', nbt.Tag(nbt.List{
		element_type: nbt.tag_compound
		values:       []nbt.Tag{}
	}))
	return NetworkEntry{
		name:       d.id
		properties: nbt.RootTag{
			name: ''
			tag:  nbt.Tag(root)
		}
	}
}

// CustomRegistry owns every registered custom block definition and hands out
// runtime ids sequentially, starting at custom_block_runtime_id_start.
pub struct CustomRegistry {
mut:
	defs    []CustomBlockDefinition
	ids     map[string]int
	next_id int = custom_block_runtime_id_start
}

pub fn new_custom_registry() CustomRegistry {
	return CustomRegistry{}
}

// register allocates a runtime id for def and stores it. Registering the same
// id again returns the previously allocated runtime id unchanged.
pub fn (mut r CustomRegistry) register(def CustomBlockDefinition) int {
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

pub fn (r &CustomRegistry) all() []CustomBlockDefinition {
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
