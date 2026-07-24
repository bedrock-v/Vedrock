module session

import sync

// WorldRegistry tracks loaded WorldRuntime instances and coordinates their
// lifecycle. Gameplay state and operations belong on WorldRuntime or WorldTx.
@[heap]
struct WorldRegistry {
mut:
	mutex  &sync.Mutex = sync.new_mutex()
	worlds map[string]&WorldRuntime
}

fn new_world_registry() &WorldRegistry {
	return &WorldRegistry{}
}

// add registers wr under its own world's name.
fn (mut r WorldRegistry) add(wr &WorldRuntime) {
	r.mutex.lock()
	r.worlds[wr.world.name] = wr
	r.mutex.unlock()
}

// get returns the runtime registered under name. The runtime may begin shutting
// down after lookup; retained references remain valid, but reject new work.
fn (mut r WorldRegistry) get(name string) ?&WorldRuntime {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	return r.worlds[name] or { return none }
}

// remove unregisters and returns the runtime so the caller can shut it down.
// Unregistering first prevents new lookups while existing references remain
// valid until shutdown completes.
fn (mut r WorldRegistry) remove(name string) ?&WorldRuntime {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	wr := r.worlds[name] or { return none }
	r.worlds.delete(name)
	return wr
}

fn (mut r WorldRegistry) names() []string {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	mut out := []string{cap: r.worlds.len}
	for name, _ in r.worlds {
		out << name
	}
	return out
}

fn (mut r WorldRegistry) len() int {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	return r.worlds.len
}

// each_runtime returns a snapshot of the currently registered runtimes,
// allowing callers to operate on them without holding the registry lock.
fn (mut r WorldRegistry) each_runtime() []&WorldRuntime {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	mut out := []&WorldRuntime{cap: r.worlds.len}
	for _, wr in r.worlds {
		out << wr
	}
	return out
}
