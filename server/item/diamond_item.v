module item

// DiamondItem is the class for 'minecraft:diamond'.
pub struct DiamondItem {
	SimpleItem
}

pub fn new_diamond() DiamondItem {
	return DiamondItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:diamond'
		}
	}
}
