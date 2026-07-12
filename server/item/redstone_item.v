module item

// RedstoneItem is the class for 'minecraft:redstone'.
pub struct RedstoneItem {
	SimpleItem
}

pub fn new_redstone() RedstoneItem {
	return RedstoneItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:redstone'
		}
	}
}
