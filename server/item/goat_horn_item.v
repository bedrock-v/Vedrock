module item

// GoatHornItem is the class for 'minecraft:goat_horn'.
pub struct GoatHornItem {
	SimpleItem
}

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

pub fn (i GoatHornItem) use_result(meta int) UseResult {
	idx := if meta >= 0 && meta < goat_horn_sound_names.len { meta } else { 0 }
	return UseResult{
		sound: goat_horn_sound_names[idx]
	}
}

const goat_horn_cooldown_ticks = 140

pub fn (i GoatHornItem) cooldown_ticks() int {
	return goat_horn_cooldown_ticks
}

pub fn new_goat_horn_item() GoatHornItem {
	return GoatHornItem{
		SimpleItem: SimpleItem{
			id:        'minecraft:goat_horn'
			stack_max: 1
		}
	}
}
