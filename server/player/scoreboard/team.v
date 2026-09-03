module scoreboard

// NameTagVisibility decides who sees a team member's name above their head.
pub enum NameTagVisibility {
	always
	never
	hide_for_other_teams
}

pub fn name_tag_visibility_from_name(name string) ?NameTagVisibility {
	return match name.to_lower() {
		'always' { NameTagVisibility.always }
		'never' { NameTagVisibility.never }
		'hideforotherteams' { NameTagVisibility.hide_for_other_teams }
		else { none }
	}
}

// Team is a named group of players. Bedrock has no team packet of its own, so
// everything a team does is done by the server: it decorates the name it sends
// for its members and decides whether their hits land on each other.
pub struct Team {
pub:
	name         string
	display_name string
	// colour is the formatting code applied to a member's name, without the
	// section sign. Empty leaves the name uncoloured.
	colour           string
	prefix           string
	suffix           string
	friendly_fire    bool              = true
	name_tag_visible NameTagVisibility = .always
}

// decorate returns a member's name as it should be shown.
pub fn (t Team) decorate(name string) string {
	mut out := t.prefix + name + t.suffix
	if t.colour != '' {
		out = '§${t.colour}${out}§r'
	}
	return out
}

// display_title is what the team is called on screen.
pub fn (t Team) display_title() string {
	if t.display_name == '' {
		return t.name
	}
	return t.display_name
}
