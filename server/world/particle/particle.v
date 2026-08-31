module particle

// Particle is an effect that may be shown at a position in a world. Like
// sounds, particles are plain values: one may be built once and shown to
// several viewers.
pub interface Particle {
	// event_id returns the level event the client renders the particle for.
	event_id() int
	// data returns the payload of that level event, empty for particles that
	// need none.
	data() int
}
