module scoreboard

// DisplaySlot is where a scoreboard objective is drawn.
pub enum DisplaySlot {
	sidebar
	list
	belowname
}

// wire_name is the name the client knows a slot by.
pub fn (slot DisplaySlot) wire_name() string {
	return match slot {
		.sidebar { 'sidebar' }
		.list { 'list' }
		.belowname { 'belowname' }
	}
}

// display_slot_from_name resolves a slot from what a command was given.
pub fn display_slot_from_name(name string) ?DisplaySlot {
	return match name.to_lower() {
		'sidebar' { DisplaySlot.sidebar }
		'list' { DisplaySlot.list }
		'belowname' { DisplaySlot.belowname }
		else { none }
	}
}

// Objective is something scores are counted under. Criteria are not modelled:
// every objective is a dummy one whose scores are set by the server, which is
// what every criterion other than the vanilla automatic ones amounts to.
pub struct Objective {
pub:
	name         string
	display_name string
	descending   bool
}

// display_title is what the client draws above the scores.
pub fn (o Objective) display_title() string {
	if o.display_name == '' {
		return o.name
	}
	return o.display_name
}
