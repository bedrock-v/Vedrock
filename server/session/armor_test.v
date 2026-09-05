module session

import time
import bedrock_v.protocol
import bedrock_v.protocol.serializer
import bedrock_v.protocol.types
import bedrock_v.protocol.version.v2168.packets as versioned
import server.internal.gamedata
import server.internal.logger
import server.item
import server.player
import bedrock_v.protocol.current as proto

fn full_set(tier item.ArmorTier) ArmorProtection {
	mut points := 0
	mut toughness := 0
	for slot in [item.ArmorSlot.helmet, .chestplate, .leggings, .boots] {
		piece := item.new_armor_item(tier, slot)
		points += piece.armor_points()
		toughness += piece.armor_toughness()
	}
	return ArmorProtection{
		points:    f32(points)
		toughness: f32(toughness)
	}
}

fn test_no_armor_leaves_damage_alone() {
	assert armor_reduced(10.0, ArmorProtection{}) == 10.0
}

fn test_full_iron_takes_a_fixed_share_of_a_small_hit() {
	// 15 defense points, no toughness. A 4 point hit pierces 2 of them, so 13
	// of 25 come off and 1.92 lands.
	left := armor_reduced(4.0, full_set(.iron))
	assert left > 1.91 && left < 1.93
}

fn test_toughness_holds_up_better_against_a_big_hit() {
	diamond := armor_reduced(40.0, full_set(.diamond))
	netherite := armor_reduced(40.0, full_set(.netherite))
	assert netherite < diamond
	// The two tiers wear the same 20 defense points, so the gap between them is
	// toughness alone and it widens with the size of the hit.
	small_gap := armor_reduced(4.0, full_set(.diamond)) - armor_reduced(4.0, full_set(.netherite))
	assert small_gap > 0
	assert diamond - netherite > small_gap
}

fn test_reduction_never_exceeds_the_cap() {
	over := ArmorProtection{
		points: 40.0
	}
	// 20 points is the most that counts, i.e. 80% off and no more.
	left := armor_reduced(10.0, over)
	assert left > 1.99 && left < 2.01
}

fn test_piercing_never_reduces_below_the_floor() {
	// A huge hit pierces past the defense points, but a fifth of them always
	// counts, so full iron still takes 15/5 = 3 points off the divisor.
	left := armor_reduced(1000.0, full_set(.iron))
	assert left > 879.9 && left < 880.1
}

fn test_armor_container_maps_onto_the_worn_slots() {
	container := proto.FullContainerName{
		container: .armor_container
	}
	assert flat_slot(container, 0)? == player.armor_slot(0)
	assert flat_slot(container, 3)? == player.armor_slot(3)
	if _ := flat_slot(container, i8(player.armor_slot_count)) {
		assert false, 'out of range armor slot accepted'
	}
	if _ := flat_slot(container, -1) {
		assert false, 'negative armor slot accepted'
	}
}

fn test_worn_slots_do_not_overlap_the_carried_ones() {
	assert player.armor_slot(0) == player.inventory_slot_count
	assert player.tracked_slot_count == player.inventory_slot_count + player.armor_slot_count
	assert player.is_armor_slot(player.armor_slot(0))
	assert player.is_armor_slot(player.armor_slot(player.armor_slot_count - 1))
	assert !player.is_armor_slot(player.inventory_slot_count - 1)
	assert !player.is_armor_slot(player.tracked_slot_count)
}

fn test_changes_touch_armor() {
	armor := SlotChange{
		container: proto.FullContainerName{
			container: .armor_container
		}
	}
	carried := SlotChange{
		container: proto.FullContainerName{
			container: .inventory_container
		}
	}
	assert changes_touch_armor([carried, armor])
	assert !changes_touch_armor([carried])
	assert !changes_touch_armor([])
}

fn test_worn_pieces_live_in_the_inventory_that_clearing_empties() {
	mut pl := player.new_player()
	net := pl.track_stack(types.ItemStack{ id: 300, count: 1 })
	pl.set_slot(player.armor_slot(0), net)
	if _ := pl.armor_stack(0) {
	} else {
		assert false, 'a worn piece was not readable back'
	}

	// Clearing the inventory is one map wipe, so it reaches the worn slots
	// as well - which is why /clear has to rebroadcast the armor.
	pl.delete_slot(player.armor_slot(0))
	if _ := pl.armor_stack(0) {
		assert false, 'a worn piece survived its slot being cleared'
	}
}

// Armour is worn by one player and rendered by all the others, and the wearer
// is a different number to each of them. Building the packet once and handing
// it to everyone names the wearer in the server's own numbering, which is a
// number the recipient either does not know or has given to somebody else.
fn test_armor_names_the_wearer_in_each_recipients_own_numbering() {
	mut hub := new_hub(gamedata.GameData{})
	mut wearer_transport := &FakeTransport{}
	mut wearer := armor_broadcast_session(mut hub, mut wearer_transport)
	mut viewer_transport := &FakeTransport{}
	mut viewer := armor_broadcast_session(mut hub, mut viewer_transport)

	// The viewer meets somebody else before it ever sees the wearer, so its
	// numbering for the wearer cannot coincide with the wearer's global id.
	viewer.wire_id_for(4321)
	expected := viewer.wire_id_for(wearer.runtime_id)
	assert expected != wearer.runtime_id

	wearer.broadcast_armor()

	assert wait_for_sent_len(viewer_transport, 1, 2000)
	mut decoded := versioned.MobArmorEquipmentPacket{}
	decode_into(viewer_transport.sent[0], mut decoded)!
	assert decoded.target_runtime_id.value == expected

	// The wearer sees itself in the packet too, and to itself it is always
	// the same constant.
	assert wait_for_sent_len(wearer_transport, 1, 2000)
	mut own := versioned.MobArmorEquipmentPacket{}
	decode_into(wearer_transport.sent[0], mut own)!
	assert own.target_runtime_id.value == self_entity_runtime_id
}

fn armor_broadcast_session(mut hub Hub, mut transport FakeTransport) &NetworkSession {
	mut s := &NetworkSession{
		player:     player.new_player()
		runtime_id: hub.allocate_runtime_id()
		conn:       &Conn{
			transport: transport
			bootstrap: true
		}
		hub:        hub
		log:        logger.new(.info)
	}
	hub.add(s)
	s.activate_outbound()
	return s
}

// The two helpers below are per file by this module's test convention: v test
// compiles one _test.v at a time, so each one carries what it uses.
fn decode_into[T](p protocol.Packet, mut out T) ! {
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(p))
	protocol.read_packet_header(mut r)!
	out.decode_payload(mut r)!
}

fn wait_for_sent_len(transport &FakeTransport, want int, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for transport.sent.len < want {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return transport.sent.len >= want
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return transport.sent.len >= want
		}
	}
	return true
}
