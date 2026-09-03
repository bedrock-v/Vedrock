module session

import math
import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import bedrock_v.protocol.version.v2168.packets as versioned
import server.item
import server.player

// armour_max_points caps how much protection the worn pieces can add up to.
// Beyond it extra defense points do nothing, the same way they do not in game.
const armour_max_points = f32(20.0)

// armour_reduction_divisor turns capped defense points into the fraction of a
// hit they take off: 20 points is 20/25, i.e. 80% off.
const armour_reduction_divisor = f32(25.0)

// armour_durability_divisor scales how much of a hit each worn piece takes as
// durability damage. Every piece hit takes at least one point.
const armour_durability_divisor = f32(4.0)

const sound_armour_break = 'random.break'

// ArmourProtection is what a player's worn pieces add up to.
struct ArmourProtection {
	points    f32
	toughness f32
}

// armour_protection sums the defense and toughness of the pieces the player
// currently wears.
fn (s &NetworkSession) armour_protection() ArmourProtection {
	mut points := 0
	mut toughness := 0
	for index in 0 .. player.armour_slot_count {
		stack := s.player.armour_stack(index) or { continue }
		it := item.get(s.hub.data.item_name(stack.id)) or { continue }
		if it is item.ArmorItem {
			points += it.armor_points()
			toughness += it.armor_toughness()
		}
	}
	return ArmourProtection{
		points:    f32(points)
		toughness: f32(toughness)
	}
}

// armour_reduced returns what is left of amount after the worn pieces have
// taken their share. A big enough hit pierces armour: the more of it there is,
// the less the defense points alone are worth, and toughness is what pushes
// back against that.
fn armour_reduced(amount f32, p ArmourProtection) f32 {
	if p.points <= 0 || amount <= 0 {
		return amount
	}
	pierced := p.points - amount / (2.0 + p.toughness / 4.0)
	effective := math.min(armour_max_points, math.max(p.points / 5.0, pierced))
	return amount * (1.0 - effective / armour_reduction_divisor)
}

// damage_armour applies the durability cost of taking a hit of amount to every
// worn piece, removing the ones that break. Creative armour never wears out.
fn (mut s NetworkSession) damage_armour(amount f32) {
	if s.player.game_mode() == .creative || amount <= 0 {
		return
	}
	cost := int(math.max(f32(1.0), amount / armour_durability_divisor))
	for index in 0 .. player.armour_slot_count {
		s.damage_armour_piece(index, cost)
	}
}

fn (mut s NetworkSession) damage_armour_piece(index int, amount int) {
	slot := player.armour_slot(index)
	stack, net := s.inventory_stack_at(slot)
	if net == 0 {
		return
	}
	it := item.get(s.hub.data.item_name(stack.id)) or { return }
	result := item.damage_item(it, stack.meta, amount)
	if result.broken {
		s.player.delete_stack(net)
		s.player.delete_slot(slot)
		s.player.send_armour_slot_update(index, empty_stack())
		s.hub.broadcast(proto.level_sound_event(sound_armour_break, s.current_position(), -1,
			'minecraft:player', s.runtime_id))
		s.broadcast_armour()
		return
	}
	if result.new_meta == stack.meta {
		return
	}
	mut updated := stack
	updated.meta = result.new_meta
	s.player.put_stack(net, updated)
	s.player.send_armour_slot_update(index, wrap_stack_id(updated, net))
}

// changes_touch_armour reports whether a request moved anything in or out of
// the worn slots, which is what everyone else's view of the player depends on.
fn changes_touch_armour(changes []SlotChange) bool {
	for change in changes {
		if change.container.container == .armor_container {
			return true
		}
	}
	return false
}

// armour_descriptor is the wire form of the piece worn at index.
fn (s &NetworkSession) armour_descriptor(index int) proto.NetworkItemStackDescriptorV2 {
	net := s.player.inv_slot(player.armour_slot(index)) or {
		return proto.item_descriptor_v2(types.ItemStack{})
	}
	stack := s.player.inv_stack(net) or { return proto.item_descriptor_v2(types.ItemStack{}) }
	return proto.item_descriptor_v2_tracked(stack, net)
}

// armour_content_packet is the full set of worn pieces, for the owning client.
fn (s &NetworkSession) armour_content_packet() &proto.InventoryContentPacket {
	mut slots := []proto.NetworkItemStackDescriptorV2{}
	for index in 0 .. player.armour_slot_count {
		slots << s.armour_descriptor(index)
	}
	return &proto.InventoryContentPacket{
		inventory_id:        u32(player.armour_window_id)
		slots:               slots
		container_name_data: proto.FullContainerName{
			container: .armor_container
		}
		storage_item:        proto.item_descriptor_v2(types.ItemStack{})
	}
}

// broadcast_armour shows the player's worn pieces on their model to everyone
// else. The packet has no alias in the protocol's current set yet, so it is
// reached through the version it was last changed in - the same one the
// current MobEquipmentPacket alias points at.
fn (s &NetworkSession) broadcast_armour() {
	mut packet := &versioned.MobArmorEquipmentPacket{
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		head:              s.armour_descriptor(0)
		torso:             s.armour_descriptor(1)
		legs:              s.armour_descriptor(2)
		feet:              s.armour_descriptor(3)
		body:              proto.item_descriptor_v2(types.ItemStack{})
	}
	mut hub := s.hub
	hub.broadcast(packet)
}
