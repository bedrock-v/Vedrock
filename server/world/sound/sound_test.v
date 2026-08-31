module sound

fn test_block_sounds_carry_the_runtime_id() {
	place := BlockPlace{
		block_runtime_id: 42
	}
	assert place.event_name() == 'place'
	assert place.data() == 42

	breaking := BlockBreaking{
		block_runtime_id: 42
	}
	assert breaking.event_name() == 'break'
	assert breaking.data() == 42
}

fn test_sounds_without_a_payload_report_no_data() {
	assert Pop{}.data() == no_data
	assert Click{}.data() == no_data
	assert Totem{}.data() == no_data
}

fn test_attack_distinguishes_a_hit_that_dealt_damage() {
	assert Attack{
		damage: true
	}.event_name() == 'attack.strong'
	assert Attack{
		damage: false
	}.event_name() == 'attack.nodamage'
}

fn test_goat_horn_falls_back_to_the_first_melody() {
	assert GoatHorn{
		variant: 3
	}.event_name() == 'item.goat_horn.sound.3'
	assert GoatHorn{
		variant: 99
	}.event_name() == 'item.goat_horn.sound.0'
}

fn test_a_sound_satisfies_the_interface() {
	sounds := [Sound(BlockPlace{}), Pop{}, Attack{}]
	assert sounds.len == 3
}
