module session

import server.internal.logger
import server.world as blockworld

// load_configured_worlds loads the default world and, when enabled, every
// other stored world, then sets the configured default as Hub's active
// world.
//
// Keeping this boot time orchestration inside the session package prevents
// raw world storage types from leaking into Server's public surface.
pub fn (mut h Hub) load_configured_worlds(worlds_dir string, default_world string, load_all bool, generator string, log &logger.Logger) {
	h.set_world_config(worlds_dir, generator)
	mut factory := h.world_factory or {
		log.warn('No world factory configured - no worlds can be loaded')
		return
	}

	mut names := [default_world]
	if load_all {
		for name in factory.discover() {
			if name !in names {
				names << name
			}
		}
	}
	for name in names {
		if w := factory.open(name, generator, blockworld.overworld) {
			h.add_world(w)
			log.info('Loaded world "${name}" (${w.block_count()} overrides)')
		} else {
			log.warn('Failed to load world "${name}": ${err}')
		}
	}
	if _ := h.world(default_world) {
		h.set_default_world(default_world)
	}
	if h.world_count() == 0 {
		log.warn('No worlds loaded - players will spawn in an empty void')
	}
}
