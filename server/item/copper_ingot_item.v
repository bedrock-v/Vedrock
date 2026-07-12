module item

// CopperIngotItem is the class for 'minecraft:copper_ingot'.
pub struct CopperIngotItem {
	SimpleItem
}

pub fn new_copper_ingot() CopperIngotItem {
	return CopperIngotItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:copper_ingot'
		}
	}
}
