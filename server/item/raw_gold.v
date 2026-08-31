module item

// RawGoldItem is the class for 'minecraft:raw_gold'.
pub struct RawGoldItem {
	SimpleItem
}

pub fn new_raw_gold() RawGoldItem {
	return RawGoldItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:raw_gold'
		}
	}
}
