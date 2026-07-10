module permission

pub enum DefaultValue {
	granted // everyone has it
	denied  // nobody has it unless explicitly granted
	op      // only operators have it
	not_op  // everyone except operators has it
}

pub fn (v DefaultValue) str() string {
	return match v {
		.granted { 'granted' }
		.denied { 'denied' }
		.op { 'op' }
		.not_op { 'not_op' }
	}
}

pub struct Permission {
pub:
	name        string
	description string
	default     DefaultValue = .denied
}

// Defaults
pub const command_version = 'vedrock.cmd.version'
pub const command_status = 'vedrock.cmd.status'
pub const command_gamemode_self = 'vedrock.cmd.gamemode.self'
pub const command_gamemode_other = 'vedrock.cmd.gamemode.other'

// Registry is a mutable set of known permissions. The shared `registry`
// below is the one every Permissible checks against; register() may be
// called on it at any time after startup (e.g. by a future plugin)
@[heap]
pub struct Registry {
mut:
	permissions map[string]Permission
}

pub const registry = new_registry()

fn new_registry() &Registry {
	mut r := &Registry{}
	r.register(Permission{
		name:        command_version
		description: 'Allows getting the server version'
		default:     .granted
	})
	r.register(Permission{
		name:        command_status
		description: "Allows viewing the server's status"
		default:     .op
	})
	r.register(Permission{
		name:        command_gamemode_self
		description: "Allows changing one's own game mode"
		default:     .op
	})
	r.register(Permission{
		name:        command_gamemode_other
		description: "Allows changing another player's game mode"
		default:     .op
	})
	return r
}

pub fn (mut r Registry) register(perm Permission) {
	r.permissions[perm.name] = perm
}

pub fn (r &Registry) get(name string) Permission {
	return r.permissions[name] or {
		Permission{
			name:    name
			default: .denied
		}
	}
}

// set_default overrides the default access level of an already-registered
// permission, preserving its name/description. Registers a bare entry (no
// description) if name isn't known yet.
pub fn (mut r Registry) set_default(name string, value DefaultValue) {
	existing := r.permissions[name] or {
		Permission{
			name: name
		}
	}
	r.permissions[name] = Permission{
		name:        existing.name
		description: existing.description
		default:     value
	}
}

// all returns every permission currently known to the registry.
pub fn (r &Registry) all() []Permission {
	mut out := []Permission{cap: r.permissions.len}
	for _, perm in r.permissions {
		out << perm
	}
	return out
}

// shared returns the process-wide registry pointer. Calling mut methods
// through this indirection (rather than on the `registry` const directly)
// is what lets the checker see it's the pointee being mutated, not the
// const binding itself.
fn shared() &Registry {
	return registry
}

// register adds or replaces a permission definition on the shared registry.
// Safe to call at any point after startup.
pub fn register(perm Permission) {
	mut r := shared()
	r.register(perm)
}

// lookup resolves name against the shared registry.
pub fn lookup(name string) Permission {
	return shared().get(name)
}

// set_default overrides a permission's default access level on the shared
// registry. Safe to call at any point after startup.
pub fn set_default(name string, value DefaultValue) {
	mut r := shared()
	r.set_default(name, value)
}

// all returns every permission currently known to the shared registry.
pub fn all() []Permission {
	return shared().all()
}
