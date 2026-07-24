module item

// DamageResult is the outcome of applying durability damage to a stack.
// broken means the item should be removed (or replaced with its broken
// item, once anything defines one. For now, every durable item just disappears.
pub struct DamageResult {
pub:
	broken   bool
	new_meta int
}

// damage_item computes the result of applying amount points of durability
// damage to an item currently at current_meta.
pub fn damage_item(it Item, current_meta int, amount int) DamageResult {
	max := it.durability()
	if max <= 0 || amount <= 0 {
		return DamageResult{
			new_meta: current_meta
		}
	}
	new_meta := current_meta + amount
	if new_meta >= max {
		return DamageResult{
			broken: true
		}
	}
	return DamageResult{
		new_meta: new_meta
	}
}
