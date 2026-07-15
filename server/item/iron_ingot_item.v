module item

// IronIngotItem is the class for 'minecraft:iron_ingot'.
pub struct IronIngotItem {
	SimpleItem
}

pub fn new_iron_ingot() IronIngotItem {
	return IronIngotItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:iron_ingot'
		}
	}
}
