module session


// self_entity_runtime_id is the id a client knows itself by. Bedrock clients
// accept any value here and pinning it removes a whole class of "which id am
// I" confusion: a session's own packets always say 1 and the check for "is this
// about me" is a comparison against a constant.
pub const self_entity_runtime_id = u64(1)

// Runtime ids are per viewer.
//
// The server allocates one globally unique id per actor (entity.ActorId.value)
// and uses it as the actor's identity everywhere inside the server. What goes
// on the wire is not that id: each session hands out its own numbering for the
// actors it has been shown, so the same player is a different number to every
// client watching them.
//
// That is what makes visibility expressible at all. An actor a session was
// never shown has no id there, so it can't be named in either direction. It
// also means a packet naming an actor can no longer be built once and
// broadcast; every viewer stamps its own.
//
// The maps are cleared on a world change because the actors a session can see
// change wholesale and the old numbering means nothing in the new world.

// wire_id_for returns the id this session knows the actor by, allocating one on
// first sight. The session's own player is always self_entity_runtime_id.
fn (mut s NetworkSession) wire_id_for(actor u64) u64 {
	if actor == s.runtime_id {
		return self_entity_runtime_id
	}
	s.wire_id_mutex.lock()
	defer {
		s.wire_id_mutex.unlock()
	}
	if existing := s.wire_ids[actor] {
		return existing
	}
	s.next_wire_id++
	id := s.next_wire_id
	s.wire_ids[actor] = id
	s.wire_actors[id] = actor
	return id
}

// actor_for_wire_id is the reverse: which actor this session meant by an id it
// handed out. A client naming anything else is naming something it was never
// shown.
fn (mut s NetworkSession) actor_for_wire_id(id u64) ?u64 {
	if id == self_entity_runtime_id {
		return s.runtime_id
	}
	s.wire_id_mutex.lock()
	defer {
		s.wire_id_mutex.unlock()
	}
	return s.wire_ids_actor(id)
}

fn (s &NetworkSession) wire_ids_actor(id u64) ?u64 {
	return s.wire_actors[id] or { return none }
}

// forget_wire_ids drops the whole numbering. A world change invalidates it: the
// actors on the other side are different ones and reusing a number for a
// different actor is how a client ends up rendering the wrong thing.
fn (mut s NetworkSession) forget_wire_ids() {
	s.wire_id_mutex.lock()
	s.wire_ids = map[u64]u64{}
	s.wire_actors = map[u64]u64{}
	s.next_wire_id = self_entity_runtime_id
	s.wire_id_mutex.unlock()
}
