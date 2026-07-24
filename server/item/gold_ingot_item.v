module item

// GoldIngotItem is the class for 'minecraft:gold_ingot'.
pub struct GoldIngotItem {
	SimpleItem
}

pub fn new_gold_ingot() GoldIngotItem {
	return GoldIngotItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:gold_ingot'
		}
	}
}
