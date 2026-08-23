module bossbar

// Colour is the colour of the bar drawn behind a BossBar's text.
pub enum Colour as u8 {
	pink           = 0
	blue           = 1
	red            = 2
	green          = 3
	yellow         = 4
	purple         = 5
	rebecca_purple = 6
	white          = 7
}

// u8 returns the protocol value of the Colour.
pub fn (c Colour) u8() u8 {
	return u8(c)
}
