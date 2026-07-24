module event

// Context is a homage to dragonfly's event.Context[T]. It wraps the subject of
// an event and lets handlers cancel the outcome or mutate the subject in place.
// Callers dispatch a Context through the Bus, then read back is_cancelled() and
// the possibly-modified val to decide what actually happens.
pub struct Context[T] {
pub mut:
	cancelled bool
	val       T
}

// new_context wraps val in a fresh, uncancelled Context.
pub fn new_context[T](val T) Context[T] {
	return Context[T]{
		val: val
	}
}

// cancel marks the event as cancelled. Whether that stops anything is up to the
// code that dispatched the Context.
pub fn (mut c Context[T]) cancel() {
	c.cancelled = true
}

// is_cancelled reports whether any handler cancelled the event.
pub fn (c &Context[T]) is_cancelled() bool {
	return c.cancelled
}

// Priority orders handlers on the Bus. Lowest runs first so that highest and
// monitor see the final, already-modified state - monitor handlers are expected
// to only observe, never mutate. Mirrors PocketMine's EventPriority.
pub enum Priority {
	lowest
	low
	normal
	high
	highest
	monitor
}
