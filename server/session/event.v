module session

pub struct EventContext[T] {
mut:
	cancelled bool
pub mut:
	val T
}

pub fn new_event_context[T](val T) EventContext[T] {
	return EventContext[T]{
		val: val
	}
}

pub fn (mut ctx EventContext[T]) cancel() {
	ctx.cancelled = true
}

pub fn (ctx &EventContext[T]) is_cancelled() bool {
	return ctx.cancelled
}
