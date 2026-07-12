module item

// EmeraldItem is the class for 'minecraft:emerald'.
pub struct EmeraldItem {
	SimpleItem
}

pub fn new_emerald() EmeraldItem {
	return EmeraldItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:emerald'
		}
	}
}
