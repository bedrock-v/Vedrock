module sound

// Sound is a sound that may be played at a position in a world. Implementations
// are plain values holding whatever the client needs to render them, so a
// Sound can be built once and played for several viewers.
pub interface Sound {
	// event_name returns the sound event the client resolves to an actual audio
	// file.
	event_name() string
	// data returns the extra payload of the sound event. Most sounds carry
	// nothing and return -1; block sounds carry the runtime id of the block
	// they belong to, so the client picks the right material.
	data() i32
}

// no_data is the payload of a sound event that carries nothing extra.
pub const no_data = i32(-1)

// Custom is a sound named by its event directly, for the sounds the server
// picks by name rather than by kind. It exists for the same reason
// particle.Custom does: a caller that has only a name should still play a
// Sound rather than reach past this package for a packet.
pub struct Custom {
pub:
	name string
}

pub fn (s Custom) event_name() string {
	return s.name
}

pub fn (s Custom) data() i32 {
	return no_data
}
