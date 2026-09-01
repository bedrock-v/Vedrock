module worldrt

import server.world
import server.world.db

// GeneratorFactory resolves the generator a world should be built with. A
// world runtime needs one to start its chunk service and to answer generated
// block queries but resolving a name to a generator is configuration, not
// actor work, so the runtime takes the decision rather than making it.
pub interface GeneratorFactory {
	build_generator(w &db.World) world.Generator
}
