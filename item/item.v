module item

// Item is the behaviour contract every item class implements. Concrete
// classes (one struct per item family) live in their own files and are
// registered in the Registry so the session layer can look them up by their
// string identifier (e.g. 'minecraft:diamond_sword').
pub interface Item {
	// identifier returns the namespaced item id used on the wire.
	identifier() string
	// max_stack_size is how many of this item fit in a single slot.
	max_stack_size() int
}

// SimpleItem is the fallback class for items that carry no special behaviour
// (dyes, sticks, string, ...). Anything not explicitly modelled falls back to
// a SimpleItem with the default stack size.
pub struct SimpleItem {
pub:
	id        string
	stack_max int = 64
}

pub fn (i SimpleItem) identifier() string {
	return i.id
}

pub fn (i SimpleItem) max_stack_size() int {
	return i.stack_max
}
