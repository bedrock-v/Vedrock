module item

// StickItem is the class for 'minecraft:stick'.
pub struct StickItem {
	SimpleItem
}

pub fn new_stick() StickItem {
	return StickItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:stick'
		}
	}
}
