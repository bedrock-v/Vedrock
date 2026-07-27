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
//
// Dimensions approximate each entity type's Bedrock hitbox closely enough
// for collision and hit testing, but are not treated as exact vanilla data.
// eye_height is currently unused for non-player entities and is included
// for future features that need an eye level position.
//
// Wild mobs use natural_mob_despawn_policy. Persistent, named, tamed or
// boss entities can disable natural despawning with DespawnPolicy{}.
pub fn register_defaults(mut r Registry) {
	r.register('pig', fn () Behaviour {
		return &PassiveBehaviour{
			network_id:     'minecraft:pig'
			dimensions:     Dimensions{
				width:      0.9
				height:     0.9
				eye_height: 0.75
			}
			despawn_policy: natural_mob_despawn_policy
		}
	})
	r.register('cow', fn () Behaviour {
		return &PassiveBehaviour{
			network_id:     'minecraft:cow'
			dimensions:     Dimensions{
				width:      0.9
				height:     1.4
				eye_height: 1.18
			}
			despawn_policy: natural_mob_despawn_policy
		}
	})
	r.register('chicken', fn () Behaviour {
		return &PassiveBehaviour{
			network_id:     'minecraft:chicken'
			dimensions:     Dimensions{
				width:      0.4
				height:     0.7
				eye_height: 0.6
			}
			despawn_policy: natural_mob_despawn_policy
		}
	})
	r.register('zombie', fn () Behaviour {
		return &HostileBehaviour{
			network_id:     'minecraft:zombie'
			dimensions:     Dimensions{
				width:      0.6
				height:     1.95
				eye_height: 1.74
			}
			despawn_policy: natural_mob_despawn_policy
		}
	})
	r.register('snowball', fn () Behaviour {
		return &ProjectileBehaviour{
			network_id:              'minecraft:snowball'
			gravity_accel:           0.03
			drag_factor:             0.01
			survive_block_collision: false
			dimensions:              Dimensions{
				width:       0.25
				height:      0.25
				eye_height:  0.125
				step_height: 0.0
			}
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
			dimensions:              Dimensions{
				width:       0.5
				height:      0.5
				eye_height:  0.25
				step_height: 0.0
			}
		}
	})
}
