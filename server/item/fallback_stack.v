module item

// fallback_stack_size maps a palette item name to its vanilla max stack size
// for the generic fallback tier.
fn fallback_stack_size(name string) int {
	match name {
		'minecraft:ender_pearl', 'minecraft:egg', 'minecraft:snowball', 'minecraft:wind_charge',
		'minecraft:honey_bottle' {
			return 16
		}
		'minecraft:bucket' {
			// Only the empty bucket stacks; filled variants hit the _bucket suffix rule below.
			return 16
		}
		else {}
	}

	return match true {
		name.ends_with('_boat') || name.ends_with('_raft') {
			1
		}
		name == 'minecraft:minecart' || name.ends_with('_minecart') {
			1
		}
		name.ends_with('_bucket') {
			1
		}
		name.ends_with('_potion') || name == 'minecraft:potion' {
			1
		}
		name.contains('music_disc') {
			1
		}
		name == 'minecraft:bundle' || name.ends_with('_bundle') {
			1
		}
		name.ends_with('_harness') {
			1
		}
		name == 'minecraft:banner_pattern' || name.ends_with('_banner_pattern') {
			1
		}
		name.ends_with('_sign') {
			16
		}
		name.ends_with('_banner') {
			16
		}
		name.ends_with('_bed') {
			1
		}
		name == 'minecraft:saddle' || name.ends_with('_horse_armor') {
			1
		}
		name.ends_with('_shulker_box') || name == 'minecraft:undyed_shulker_box' {
			1
		}
		name == 'minecraft:shield' || name == 'minecraft:elytra' || name == 'minecraft:trident' {
			1
		}
		name == 'minecraft:crossbow' || name == 'minecraft:bow' || name == 'minecraft:mace' {
			1
		}
		name == 'minecraft:fishing_rod' || name == 'minecraft:carrot_on_a_stick'
			|| name == 'minecraft:warped_fungus_on_a_stick' {
			1
		}
		name == 'minecraft:flint_and_steel' || name.ends_with('_shears')
			|| name == 'minecraft:shears' {
			1
		}
		name == 'minecraft:enchanted_book' || name == 'minecraft:written_book'
			|| name == 'minecraft:writable_book' {
			1
		}
		name.ends_with('_stew') || name.ends_with('_soup') || name == 'minecraft:cake' {
			1
		}
		name == 'minecraft:totem_of_undying' || name == 'minecraft:spyglass' {
			1
		}
		else {
			64
		}
	}
}
