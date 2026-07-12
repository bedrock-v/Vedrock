module item

// DiamondSwordItem is the class for 'minecraft:diamond_sword'.
pub struct DiamondSwordItem {
	SwordItem
}

pub fn new_diamond_sword() DiamondSwordItem {
	return DiamondSwordItem{
		SwordItem: SwordItem{
			id:         'minecraft:diamond_sword'
			damage:     7
			durability: 1561
		}
	}
}
