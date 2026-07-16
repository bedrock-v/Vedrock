module item

// CoalItem is the class for 'minecraft:coal'.
pub struct CoalItem {
	SimpleItem
}

pub fn new_coal() CoalItem {
	return CoalItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:coal'
		}
	}
}
