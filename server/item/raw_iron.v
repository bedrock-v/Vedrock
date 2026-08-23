module item

// RawIronItem is the class for 'minecraft:raw_iron'.
pub struct RawIronItem {
	SimpleItem
}

pub fn new_raw_iron() RawIronItem {
	return RawIronItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:raw_iron'
		}
	}
}
