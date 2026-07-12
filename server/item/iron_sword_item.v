module item

// IronSwordItem is the class for 'minecraft:iron_sword'.
pub struct IronSwordItem {
	SwordItem
}

pub fn new_iron_sword() IronSwordItem {
	return IronSwordItem{
		SwordItem: SwordItem{
			id:         'minecraft:iron_sword'
			damage:     6
			durability: 250
		}
	}
}
