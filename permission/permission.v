module permission

pub enum DefaultValue {
	granted // everyone has it
	denied  // nobody has it unless explicitly granted
	op      // only operators have it
	not_op  // everyone except operators has it
}

pub struct Permission {
pub:
	name        string
	description string
	default     DefaultValue = .denied
}

// Defaults
pub const command_version = 'vedrock.command.version'
pub const command_status = 'vedrock.command.status'
pub const command_gamemode_self = 'vedrock.command.gamemode.self'
pub const command_gamemode_other = 'vedrock.command.gamemode.other'

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
