module entity

import nbt

// Runtime ids for custom entity types start above the vanilla list so they
// never collide with it.
pub const custom_entity_runtime_id_start = 10000

// CustomEntityDefinition describes an entity type a plugin registers. The
// definition ends up in the AvailableActorIdentifiersPacket idlist so the
// client accepts AddActor packets with the custom identifier.
pub struct CustomEntityDefinition {
pub mut:
	id            string
	summonable    bool = true
	has_spawn_egg bool
	runtime_id    int
}

// short_name derives the registry name from the namespaced id, e.g.
// 'myplugin:fire_golem' -> 'fire_golem'.
pub fn (d &CustomEntityDefinition) short_name() string {
	idx := d.id.index(':') or { return d.id }
	return d.id[idx + 1..]
}

// CustomRegistry owns every registered custom entity definition and hands out
// runtime ids sequentially, starting at custom_entity_runtime_id_start.
pub struct CustomRegistry {
mut:
	defs    []CustomEntityDefinition
	ids     map[string]int
	next_id int = custom_entity_runtime_id_start
}

pub fn new_custom_registry() CustomRegistry {
	return CustomRegistry{}
}

// register allocates a runtime id for def and stores it, returning false when
// the id was already registered.
pub fn (mut r CustomRegistry) register(def CustomEntityDefinition) bool {
	if def.id in r.ids {
		return false
	}
	mut stored := def
	stored.runtime_id = r.next_id
	r.next_id++
	r.ids[stored.id] = stored.runtime_id
	r.defs << stored
	return true
}

pub fn (r &CustomRegistry) all() []CustomEntityDefinition {
	return r.defs
}

pub fn (r &CustomRegistry) len() int {
	return r.defs.len
}

pub fn (r &CustomRegistry) names() []string {
	mut out := []string{cap: r.defs.len}
	for def in r.defs {
		out << def.id
	}
	return out
}

fn flag_byte(v bool) nbt.Tag {
	if v {
		return nbt.Tag(i8(1))
	}
	return nbt.Tag(i8(0))
}

// identifiers_nbt builds the AvailableActorIdentifiers root tag: an idlist of
// one compound per custom entity, in the format the client expects.
pub fn (r &CustomRegistry) identifiers_nbt() nbt.RootTag {
	mut entries := []nbt.Tag{cap: r.defs.len}
	for def in r.defs {
		mut entry := nbt.new_compound()
		entry.set('bid', nbt.Tag(''))
		entry.set('hasspawnegg', flag_byte(def.has_spawn_egg))
		entry.set('id', nbt.Tag(def.id))
		entry.set('rid', nbt.Tag(i32(def.runtime_id)))
		entry.set('summonable', flag_byte(def.summonable))
		entries << nbt.Tag(entry)
	}
	mut root := nbt.new_compound()
	root.set('idlist', nbt.Tag(nbt.List{
		element_type: nbt.tag_compound
		values:       entries
	}))
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(root)
	}
}
