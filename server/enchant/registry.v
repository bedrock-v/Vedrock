module enchant

import nbt

// Registry maps enchantment ids and names to their classes. It boots with the
// vanilla set registered; plugins add theirs with ids from
// custom_enchantment_id_start up.
pub struct Registry {
mut:
	by_id       map[int]Enchantment
	by_name     map[string]Enchantment
	next_custom int = custom_enchantment_id_start
}

// new_registry builds a Registry pre-populated with the vanilla enchantments.
pub fn new_registry() Registry {
	mut r := Registry{}
	register_defaults(mut r)
	return r
}

// register adds an enchantment, returning false when its id or name is taken.
pub fn (mut r Registry) register(e Enchantment) bool {
	if e.id() in r.by_id || e.name() in r.by_name {
		return false
	}
	r.by_id[e.id()] = e
	r.by_name[e.name()] = e
	if e.id() >= r.next_custom {
		r.next_custom = e.id() + 1
	}
	return true
}

// next_custom_id returns the next free id in the custom range without
// claiming it.
pub fn (r &Registry) next_custom_id() int {
	return r.next_custom
}

pub fn (r &Registry) get(id int) ?Enchantment {
	return r.by_id[id] or { return none }
}

pub fn (r &Registry) get_by_name(name string) ?Enchantment {
	return r.by_name[name] or { return none }
}

pub fn (r &Registry) len() int {
	return r.by_id.len
}

pub fn (r &Registry) names() []string {
	mut out := []string{cap: r.by_name.len}
	for name, _ in r.by_name {
		out << name
	}
	return out
}

// Applied is one enchantment instance on an item stack.
pub struct Applied {
pub:
	eid   int
	level int
}

// ench_nbt builds the Bedrock 'ench' list tag for an item stack: one compound
// per enchantment with short id and lvl fields.
pub fn ench_nbt(entries []Applied) nbt.Tag {
	mut values := []nbt.Tag{cap: entries.len}
	for e in entries {
		mut c := nbt.new_compound()
		c.set('id', nbt.Tag(i16(e.eid)))
		c.set('lvl', nbt.Tag(i16(e.level)))
		values << nbt.Tag(c)
	}
	return nbt.Tag(nbt.List{
		element_type: nbt.tag_compound
		values:       values
	})
}

// attack_bonus sums the melee damage bonus of every applied enchantment.
pub fn (r &Registry) attack_bonus(applied []Applied) f32 {
	mut total := f32(0)
	for a in applied {
		if e := r.get(a.eid) {
			total += e.attack_bonus(a.level)
		}
	}
	return total
}

// protection_factor sums the damage reduction weight of every applied
// enchantment.
pub fn (r &Registry) protection_factor(applied []Applied) f32 {
	mut total := f32(0)
	for a in applied {
		if e := r.get(a.eid) {
			total += e.protection_factor(a.level)
		}
	}
	return total
}
