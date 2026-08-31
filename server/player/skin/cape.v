module skin

// Cape is the cape worn behind a Skin. A cape is either empty or holds one
// image, stored the same way a Skin stores its pixels.
pub struct Cape {
	width  int
	height int
pub mut:
	// id is the identifier the client caches the cape under. It is empty for a
	// cape that holds no image.
	id string
	// pix holds the RGBA pixel data of the cape, four bytes per pixel.
	pix []u8
}

// new_cape returns a Cape of the size passed, with its pixels allocated so it
// can be written to right away.
pub fn new_cape(width int, height int) Cape {
	return Cape{
		width:  width
		height: height
		pix:    []u8{len: width * height * 4}
	}
}

// width returns the width of the Cape in pixels.
pub fn (c &Cape) width() int {
	return c.width
}

// height returns the height of the Cape in pixels.
pub fn (c &Cape) height() int {
	return c.height
}

// exists reports whether the Cape holds an image at all.
pub fn (c &Cape) exists() bool {
	return c.width > 0 && c.height > 0 && c.pix.len > 0
}

// at returns the RGBA colour at the coordinates passed. It fails if the
// coordinates fall outside the Cape.
pub fn (c &Cape) at(x int, y int) !Colour {
	if x < 0 || y < 0 || x >= c.width || y >= c.height {
		return error('cape pixel (${x}, ${y}) is out of bounds')
	}
	offset := x * 4 + c.width * y * 4
	return Colour{
		r: c.pix[offset]
		g: c.pix[offset + 1]
		b: c.pix[offset + 2]
		a: c.pix[offset + 3]
	}
}
