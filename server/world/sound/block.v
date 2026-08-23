module sound

// BlockPlace is played when a block is placed. The runtime id decides which
// material the client plays the sound of.
pub struct BlockPlace {
pub:
	block_runtime_id int
}

pub fn (s BlockPlace) event_name() string {
	return 'place'
}

pub fn (s BlockPlace) data() i32 {
	return i32(s.block_runtime_id)
}

// BlockBreaking is played while a block is being mined and once it breaks. The
// runtime id decides which material the client plays the sound of.
pub struct BlockBreaking {
pub:
	block_runtime_id int
}

pub fn (s BlockBreaking) event_name() string {
	return 'break'
}

pub fn (s BlockBreaking) data() i32 {
	return i32(s.block_runtime_id)
}

// GlassBreak is played when glass shatters.
pub struct GlassBreak {}

pub fn (s GlassBreak) event_name() string {
	return 'glass'
}

pub fn (s GlassBreak) data() i32 {
	return no_data
}

// Fizz is played when a liquid is extinguished.
pub struct Fizz {}

pub fn (s Fizz) event_name() string {
	return 'fizz'
}

pub fn (s Fizz) data() i32 {
	return no_data
}

// Deny is played when a player is denied from acting on a block.
pub struct Deny {}

pub fn (s Deny) event_name() string {
	return 'deny'
}

pub fn (s Deny) data() i32 {
	return no_data
}

// Click is played when a button, lever or similar control is toggled.
pub struct Click {}

pub fn (s Click) event_name() string {
	return 'click'
}

pub fn (s Click) data() i32 {
	return no_data
}

// Ignite is played when a block is set on fire.
pub struct Ignite {}

pub fn (s Ignite) event_name() string {
	return 'ignite'
}

pub fn (s Ignite) data() i32 {
	return no_data
}

// FireExtinguish is played when a fire is put out.
pub struct FireExtinguish {}

pub fn (s FireExtinguish) event_name() string {
	return 'extinguish.fire'
}

pub fn (s FireExtinguish) data() i32 {
	return no_data
}

// PowerOn is played when a redstone component is powered.
pub struct PowerOn {}

pub fn (s PowerOn) event_name() string {
	return 'power.on'
}

pub fn (s PowerOn) data() i32 {
	return no_data
}

// PowerOff is played when a redstone component loses its power.
pub struct PowerOff {}

pub fn (s PowerOff) event_name() string {
	return 'power.off'
}

pub fn (s PowerOff) data() i32 {
	return no_data
}

// ChestOpen is played when a chest is opened.
pub struct ChestOpen {}

pub fn (s ChestOpen) event_name() string {
	return 'chest.open'
}

pub fn (s ChestOpen) data() i32 {
	return no_data
}

// ChestClose is played when a chest is closed.
pub struct ChestClose {}

pub fn (s ChestClose) event_name() string {
	return 'chest.closed'
}

pub fn (s ChestClose) data() i32 {
	return no_data
}

// BarrelOpen is played when a barrel is opened.
pub struct BarrelOpen {}

pub fn (s BarrelOpen) event_name() string {
	return 'barrel.open'
}

pub fn (s BarrelOpen) data() i32 {
	return no_data
}

// BarrelClose is played when a barrel is closed.
pub struct BarrelClose {}

pub fn (s BarrelClose) event_name() string {
	return 'barrel.close'
}

pub fn (s BarrelClose) data() i32 {
	return no_data
}

// DoorOpen is played when a door is opened.
pub struct DoorOpen {}

pub fn (s DoorOpen) event_name() string {
	return 'door.open'
}

pub fn (s DoorOpen) data() i32 {
	return no_data
}

// DoorClose is played when a door is closed.
pub struct DoorClose {}

pub fn (s DoorClose) event_name() string {
	return 'door.close'
}

pub fn (s DoorClose) data() i32 {
	return no_data
}

// TrapdoorOpen is played when a trapdoor is opened.
pub struct TrapdoorOpen {}

pub fn (s TrapdoorOpen) event_name() string {
	return 'trapdoor.open'
}

pub fn (s TrapdoorOpen) data() i32 {
	return no_data
}

// TrapdoorClose is played when a trapdoor is closed.
pub struct TrapdoorClose {}

pub fn (s TrapdoorClose) event_name() string {
	return 'trapdoor.close'
}

pub fn (s TrapdoorClose) data() i32 {
	return no_data
}

// FenceGateOpen is played when a fence gate is opened.
pub struct FenceGateOpen {}

pub fn (s FenceGateOpen) event_name() string {
	return 'fence_gate.open'
}

pub fn (s FenceGateOpen) data() i32 {
	return no_data
}

// FenceGateClose is played when a fence gate is closed.
pub struct FenceGateClose {}

pub fn (s FenceGateClose) event_name() string {
	return 'fence_gate.close'
}

pub fn (s FenceGateClose) data() i32 {
	return no_data
}

// Note is played by a note block. The pitch is the note the block is tuned to.
pub struct Note {
pub:
	pitch int
}

pub fn (s Note) event_name() string {
	return 'note'
}

pub fn (s Note) data() i32 {
	return i32(s.pitch)
}
