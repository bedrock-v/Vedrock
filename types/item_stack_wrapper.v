module types

pub struct ItemStackWrapper {
pub mut:
	stack_id         int
	stack_id_variant int
	item_stack       ItemStack
}

pub fn item_stack_wrapper_legacy(item_stack ItemStack) ItemStackWrapper {
	return ItemStackWrapper{
		stack_id:   if item_stack.id == 0 { 0 } else { 1 }
		item_stack: item_stack
	}
}
