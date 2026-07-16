module item

// GoatHornItem is the class for 'minecraft:goat_horn'.
pub struct GoatHornItem {}

const goat_horn_sound_names = [
	'item.goat_horn.sound.0',
	'item.goat_horn.sound.1',
	'item.goat_horn.sound.2',
	'item.goat_horn.sound.3',
	'item.goat_horn.sound.4',
	'item.goat_horn.sound.5',
	'item.goat_horn.sound.6',
	'item.goat_horn.sound.7',
]

pub fn (i GoatHornItem) identifier() string {
	return 'minecraft:goat_horn'
}

pub fn (i GoatHornItem) max_stack_size() int {
	return 1
}

pub fn (i GoatHornItem) attack_damage() f32 {
	return 0
}

pub fn (i GoatHornItem) nutrition() int {
	return 0
}

pub fn (i GoatHornItem) saturation() f32 {
	return 0
}

pub fn (i GoatHornItem) block_runtime_id() int {
	return 0
}

pub fn (i GoatHornItem) durability() int {
	return 0
}

pub fn (i GoatHornItem) mining_speed() f32 {
	return 1.0
}

pub fn (i GoatHornItem) armor_points() int {
	return 0
}

pub fn (i GoatHornItem) use_result(meta int) UseResult {
	idx := if meta >= 0 && meta < goat_horn_sound_names.len { meta } else { 0 }
	return UseResult{
		sound: goat_horn_sound_names[idx]
	}
}

pub fn new_goat_horn_item() GoatHornItem {
	return GoatHornItem{}
}
