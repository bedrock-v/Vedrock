module enchant

// register_custom adds "e" to the enchantment registry (registry.v). Call it
// from your own setup, before server.new(). Returns false if the id or
// name is already taken, vanilla or custom.
pub fn register_custom(e Enchantment) bool {
	mut r := process_registry
	return r.register(e)
}
