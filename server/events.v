module server

import server.event

// register_event adds handler to the server's global event bus.
pub fn (mut s Server) register_event(handler event.Handler, priority event.Priority) {
	s.hub.register_event(handler, priority)
}

// unregister_event removes handler from the global event bus.
pub fn (mut s Server) unregister_event(handler event.Handler) {
	s.hub.unregister_event(handler)
}
