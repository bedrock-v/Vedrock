module skin

// Colour is a single RGBA pixel of a Skin or Cape.
pub struct Colour {
pub:
	r u8
	g u8
	b u8
	a u8
}

// Skin is the appearance a player has been given: the texture itself, the
// geometry it is mapped onto, the animations that geometry may play, and the
// cape worn behind it.
pub struct Skin {
	width  int
	height int
pub mut:
	// id is the identifier the client caches the skin under, and full_id is
	// that identifier combined with the cape's.
	id      string
	full_id string
	// play_fab_id is the PlayFab account the skin belongs to, empty for a skin
	// the server made up.
	play_fab_id string
	// persona reports whether the skin comes from the persona system rather
	// than from a plain texture.
	persona bool
	// pix holds the RGBA pixel data of the skin, four bytes per pixel.
	pix []u8
	// model holds the raw JSON geometry of the skin. An empty model means the
	// client falls back to the standard humanoid geometry.
	model []u8
	// model_config points at the geometry inside model that each state of the
	// skin uses.
	model_config ModelConfig
	// cape is the cape worn behind the skin, empty unless one was set.
	cape Cape
	// animations holds the animations the model_config may point at.
	animations []Animation
}

// new returns a Skin of the size passed, with its pixels allocated so it can
// be written to right away. Bedrock accepts 64x32, 64x64 and 128x128 skins.
pub fn new(width int, height int) Skin {
	return Skin{
		width:        width
		height:       height
		pix:          []u8{len: width * height * 4}
		model_config: new_model_config()
	}
}

// width returns the width of the Skin in pixels.
pub fn (s &Skin) width() int {
	return s.width
}

// height returns the height of the Skin in pixels.
pub fn (s &Skin) height() int {
	return s.height
}

// at returns the RGBA colour at the coordinates passed. It fails if the
// coordinates fall outside the Skin.
pub fn (s &Skin) at(x int, y int) !Colour {
	if x < 0 || y < 0 || x >= s.width || y >= s.height {
		return error('skin pixel (${x}, ${y}) is out of bounds')
	}
	offset := x * 4 + s.width * y * 4
	return Colour{
		r: s.pix[offset]
		g: s.pix[offset + 1]
		b: s.pix[offset + 2]
		a: s.pix[offset + 3]
	}
}

// fill paints every pixel of the Skin the colour passed.
pub fn (mut s Skin) fill(c Colour) {
	for i := 0; i + 3 < s.pix.len; i += 4 {
		s.pix[i] = c.r
		s.pix[i + 1] = c.g
		s.pix[i + 2] = c.b
		s.pix[i + 3] = c.a
	}
}
