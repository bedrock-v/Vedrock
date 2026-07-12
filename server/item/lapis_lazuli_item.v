module item

// LapisLazuliItem is the class for 'minecraft:lapis_lazuli'.
pub struct LapisLazuliItem {
	SimpleItem
}

pub fn new_lapis_lazuli() LapisLazuliItem {
	return LapisLazuliItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:lapis_lazuli'
		}
	}
}
