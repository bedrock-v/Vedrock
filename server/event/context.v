module event

// Context wraps the subject of an event and lets handlers cancel the outcome or
// mutate the subject in place. Callers dispatch a Context through the Bus, then
// read back is_cancelled() and the possibly modified val to decide what happens.
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

// Priority orders handlers on the Bus. Lowest runs first so highest and monitor
// see the final state. Monitor handlers are expected to observe only.
pub enum Priority {
	lowest
	low
	normal
	high
	highest
	monitor
}
