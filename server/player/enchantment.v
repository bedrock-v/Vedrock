module player

// EnchantResult is the outcome of trying to enchant what a player holds.
pub enum EnchantResult {
	applied
	// no_item is an empty hand, and cannot_combine an enchantment the held
	// item will not take, or a level it does not go up to.
	no_item
	cannot_combine
	not_found
}
