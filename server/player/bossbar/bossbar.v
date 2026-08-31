module bossbar

// BossBar is a bar shown at the top of a player's screen, with text above it
// and a health bar below that text. It is a value type: the with_* methods
// return a modified copy instead of mutating the receiver, so a bar may be
// built once and reused for several players.
pub struct BossBar {
	text   string
	health f32    = 1.0
	colour Colour = .purple
}

// new returns a BossBar showing the text passed. The bar starts out full and
// purple; use with_health_percentage and with_colour to change that.
pub fn new(text string) BossBar {
	return BossBar{
		text: text
	}
}

// text returns the text drawn above the bar.
pub fn (bar BossBar) text() string {
	return bar.text
}

// health_percentage returns how full the bar is drawn, between 0.0 and 1.0.
pub fn (bar BossBar) health_percentage() f32 {
	return bar.health
}

// colour returns the colour of the bar.
pub fn (bar BossBar) colour() Colour {
	return bar.colour
}

// with_health_percentage returns a copy of the BossBar filled up to v, which
// is clamped to the 0.0 to 1.0 range the client accepts.
pub fn (bar BossBar) with_health_percentage(v f32) BossBar {
	mut health := v
	if health < 0.0 {
		health = 0.0
	} else if health > 1.0 {
		health = 1.0
	}
	return BossBar{
		...bar
		health: health
	}
}

// with_colour returns a copy of the BossBar drawn in the Colour passed.
pub fn (bar BossBar) with_colour(c Colour) BossBar {
	return BossBar{
		...bar
		colour: c
	}
}
