module item

// RawCopperItem is the class for 'minecraft:raw_copper'.
pub struct RawCopperItem {
	SimpleItem
}

pub fn new_raw_copper() RawCopperItem {
	return RawCopperItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:raw_copper'
		}
	}
}
