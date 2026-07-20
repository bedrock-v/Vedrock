module entity

// BehaviourFactory builds a fresh Behaviour for a registered entity type. Each
// spawn gets its own instance so per-entity behaviour state stays isolated.
pub type BehaviourFactory = fn () Behaviour

// Registry maps short type names (e.g. 'pig') to Behaviour factories. It is the
// lookup /summon and plugins use to spawn entities by name.
pub struct Registry {
mut:
	factories map[string]BehaviourFactory
}

pub fn new_registry() Registry {
	return Registry{}
}

// register adds a named entity type. Re-registering a name overwrites it.
pub fn (mut r Registry) register(name string, factory BehaviourFactory) {
	r.factories[name.to_lower()] = factory
}

// create builds a new Behaviour for name, or none if the type is unknown.
pub fn (r &Registry) create(name string) ?Behaviour {
	factory := r.factories[name.to_lower()] or { return none }
	return factory()
}

// names lists every registered type name.
pub fn (r &Registry) names() []string {
	mut out := []string{cap: r.factories.len}
	for name, _ in r.factories {
		out << name
	}
	return out
}

// register_defaults registers the entity types Vedrock ships with.
pub fn register_defaults(mut r Registry) {
	r.register('pig', fn () Behaviour {
		return &PassiveBehaviour{
			network_id: 'minecraft:pig'
		}
	})
	r.register('cow', fn () Behaviour {
		return &PassiveBehaviour{
			network_id: 'minecraft:cow'
		}
	})
	r.register('chicken', fn () Behaviour {
		return &PassiveBehaviour{
			network_id: 'minecraft:chicken'
		}
	})
	r.register('zombie', fn () Behaviour {
		return &HostileBehaviour{
			network_id: 'minecraft:zombie'
		}
	})
	r.register('snowball', fn () Behaviour {
		return &ProjectileBehaviour{
			network_id:              'minecraft:snowball'
			gravity_accel:           0.03
			drag_factor:             0.01
			survive_block_collision: false
		}
	})
	r.register('arrow', fn () Behaviour {
		return &ProjectileBehaviour{
			network_id:              'minecraft:arrow'
			max_age:                 1200
			damage:                  2.0
			gravity_accel:           0.05
			drag_factor:             0.01
			survive_block_collision: true
		}
	})
}
