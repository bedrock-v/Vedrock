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
