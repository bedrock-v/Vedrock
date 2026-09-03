module session

import server.item
import server.player
import bedrock_v.protocol.current as proto

fn full_set(tier item.ArmorTier) ArmourProtection {
	mut points := 0
	mut toughness := 0
	for slot in [item.ArmorSlot.helmet, .chestplate, .leggings, .boots] {
		piece := item.new_armor_item(tier, slot)
		points += piece.armor_points()
		toughness += piece.armor_toughness()
	}
	return ArmourProtection{
		points:    f32(points)
		toughness: f32(toughness)
	}
}

fn test_no_armour_leaves_damage_alone() {
	assert armour_reduced(10.0, ArmourProtection{}) == 10.0
}

fn test_full_iron_takes_a_fixed_share_of_a_small_hit() {
	// 15 defense points, no toughness. A 4 point hit pierces 2 of them, so 13
	// of 25 come off and 1.92 lands.
	left := armour_reduced(4.0, full_set(.iron))
	assert left > 1.91 && left < 1.93
}

fn test_toughness_holds_up_better_against_a_big_hit() {
	diamond := armour_reduced(40.0, full_set(.diamond))
	netherite := armour_reduced(40.0, full_set(.netherite))
	assert netherite < diamond
	// The two tiers wear the same 20 defense points, so the gap between them is
	// toughness alone and it widens with the size of the hit.
	small_gap := armour_reduced(4.0, full_set(.diamond)) - armour_reduced(4.0, full_set(.netherite))
	assert small_gap > 0
	assert diamond - netherite > small_gap
}

fn test_reduction_never_exceeds_the_cap() {
	over := ArmourProtection{
		points: 40.0
	}
	// 20 points is the most that counts, i.e. 80% off and no more.
	left := armour_reduced(10.0, over)
	assert left > 1.99 && left < 2.01
}

fn test_piercing_never_reduces_below_the_floor() {
	// A huge hit pierces past the defense points, but a fifth of them always
	// counts, so full iron still takes 15/5 = 3 points off the divisor.
	left := armour_reduced(1000.0, full_set(.iron))
	assert left > 879.9 && left < 880.1
}

fn test_armour_container_maps_onto_the_worn_slots() {
	container := proto.FullContainerName{
		container: .armor_container
	}
	assert flat_slot(container, 0)? == player.armour_slot(0)
	assert flat_slot(container, 3)? == player.armour_slot(3)
	if _ := flat_slot(container, i8(player.armour_slot_count)) {
		assert false, 'out of range armour slot accepted'
	}
	if _ := flat_slot(container, -1) {
		assert false, 'negative armour slot accepted'
	}
}

fn test_worn_slots_do_not_overlap_the_carried_ones() {
	assert player.armour_slot(0) == player.inventory_slot_count
	assert player.tracked_slot_count == player.inventory_slot_count + player.armour_slot_count
	assert player.is_armour_slot(player.armour_slot(0))
	assert player.is_armour_slot(player.armour_slot(player.armour_slot_count - 1))
	assert !player.is_armour_slot(player.inventory_slot_count - 1)
	assert !player.is_armour_slot(player.tracked_slot_count)
}

fn test_changes_touch_armour() {
	armour := SlotChange{
		container: proto.FullContainerName{
			container: .armor_container
		}
	}
	carried := SlotChange{
		container: proto.FullContainerName{
			container: .inventory_container
		}
	}
	assert changes_touch_armour([carried, armour])
	assert !changes_touch_armour([carried])
	assert !changes_touch_armour([])
}
