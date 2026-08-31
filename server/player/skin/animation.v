module skin

// AnimationType is the part of the body an Animation is drawn over.
pub enum AnimationType {
	// head is an animation played over the head of the skin.
	head
	// body_32x32 is an animation played over the body of a 32x32 skin, the
	// usual size for body animations.
	body_32x32
	// body_128x128 is an animation played over the body of a 128x128 skin.
	body_128x128
}

// Animation is a sequence of frames played over part of a Skin. The
// ModelConfig of the skin decides when it is shown.
pub struct Animation {
	width  int
	height int
	typ    AnimationType
pub mut:
	// pix holds the RGBA pixel data of every frame, four bytes per pixel.
	pix []u8
	// frame_count is how many frames pix holds.
	frame_count int = 1
	// expression is the player expression the animation belongs to.
	expression int
}

// new_animation returns an Animation of the size and type passed, with its
// pixels allocated and a single frame.
pub fn new_animation(width int, height int, expression int, typ AnimationType) Animation {
	return Animation{
		width:      width
		height:     height
		typ:        typ
		pix:        []u8{len: width * height * 4}
		expression: expression
	}
}

// width returns the width of a frame in pixels.
pub fn (a &Animation) width() int {
	return a.width
}

// height returns the height of a frame in pixels.
pub fn (a &Animation) height() int {
	return a.height
}

// typ returns the part of the body the Animation is drawn over.
pub fn (a &Animation) typ() AnimationType {
	return a.typ
}
