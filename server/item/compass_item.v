module item

// CompassItem is the class for 'minecraft:compass'.
pub struct CompassItem {
	SimpleItem
}

pub fn new_compass_item() CompassItem {
	return CompassItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:compass'
		}
	}
}

// RecoveryCompassItem is the class for 'minecraft:recovery_compass'.
pub struct RecoveryCompassItem {
	SimpleItem
}

pub fn new_recovery_compass_item() RecoveryCompassItem {
	return RecoveryCompassItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:recovery_compass'
		}
	}
}

// LodestoneCompassItem is the class for 'minecraft:lodestone_compass'.
pub struct LodestoneCompassItem {
	SimpleItem
}

pub fn new_lodestone_compass_item() LodestoneCompassItem {
	return LodestoneCompassItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:lodestone_compass'
		}
	}
}
