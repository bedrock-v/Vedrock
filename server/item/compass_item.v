module item

// CompassItem is the class for 'minecraft:compass'.
pub struct CompassItem {}

pub fn (i CompassItem) identifier() string {
	return 'minecraft:compass'
}

pub fn (i CompassItem) max_stack_size() int {
	return 64
}

pub fn (i CompassItem) attack_damage() f32 {
	return 0
}

pub fn (i CompassItem) nutrition() int {
	return 0
}

pub fn (i CompassItem) saturation() f32 {
	return 0
}

pub fn (i CompassItem) block_runtime_id() int {
	return 0
}

pub fn (i CompassItem) durability() int {
	return 0
}

pub fn (i CompassItem) mining_speed() f32 {
	return 1.0
}

pub fn (i CompassItem) armor_points() int {
	return 0
}

pub fn new_compass_item() CompassItem {
	return CompassItem{}
}

// RecoveryCompassItem is the class for 'minecraft:recovery_compass'.
pub struct RecoveryCompassItem {}

pub fn (i RecoveryCompassItem) identifier() string {
	return 'minecraft:recovery_compass'
}

pub fn (i RecoveryCompassItem) max_stack_size() int {
	return 64
}

pub fn (i RecoveryCompassItem) attack_damage() f32 {
	return 0
}

pub fn (i RecoveryCompassItem) nutrition() int {
	return 0
}

pub fn (i RecoveryCompassItem) saturation() f32 {
	return 0
}

pub fn (i RecoveryCompassItem) block_runtime_id() int {
	return 0
}

pub fn (i RecoveryCompassItem) durability() int {
	return 0
}

pub fn (i RecoveryCompassItem) mining_speed() f32 {
	return 1.0
}

pub fn (i RecoveryCompassItem) armor_points() int {
	return 0
}

pub fn new_recovery_compass_item() RecoveryCompassItem {
	return RecoveryCompassItem{}
}

// LodestoneCompassItem is the class for 'minecraft:lodestone_compass'.
pub struct LodestoneCompassItem {}

pub fn (i LodestoneCompassItem) identifier() string {
	return 'minecraft:lodestone_compass'
}

pub fn (i LodestoneCompassItem) max_stack_size() int {
	return 64
}

pub fn (i LodestoneCompassItem) attack_damage() f32 {
	return 0
}

pub fn (i LodestoneCompassItem) nutrition() int {
	return 0
}

pub fn (i LodestoneCompassItem) saturation() f32 {
	return 0
}

pub fn (i LodestoneCompassItem) block_runtime_id() int {
	return 0
}

pub fn (i LodestoneCompassItem) durability() int {
	return 0
}

pub fn (i LodestoneCompassItem) mining_speed() f32 {
	return 1.0
}

pub fn (i LodestoneCompassItem) armor_points() int {
	return 0
}

pub fn new_lodestone_compass_item() LodestoneCompassItem {
	return LodestoneCompassItem{}
}
