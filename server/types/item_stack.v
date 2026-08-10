module types

pub struct ItemStack {
pub mut:
	id               int
	meta             int
	count            int
	block_runtime_id int
	raw_extra_data   []u8
}

pub fn item_stack_null() ItemStack {
	return ItemStack{
		id: 0
	}
}

pub fn (s &ItemStack) is_null() bool {
	return s.id == 0
}
