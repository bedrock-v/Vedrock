module sound

// ItemBreak is played when a tool or piece of armour runs out of durability.
pub struct ItemBreak {}

pub fn (s ItemBreak) event_name() string {
	return 'break'
}

pub fn (s ItemBreak) data() i32 {
	return no_data
}

// ItemThrow is played when an item is thrown, such as a snowball or an egg.
pub struct ItemThrow {}

pub fn (s ItemThrow) event_name() string {
	return 'item_thrown'
}

pub fn (s ItemThrow) data() i32 {
	return no_data
}

// ItemUseOn is played when an item is used on a block, such as a hoe tilling
// dirt. The runtime id decides which material the client plays the sound of.
pub struct ItemUseOn {
pub:
	block_runtime_id int
}

pub fn (s ItemUseOn) event_name() string {
	return 'item.use.on'
}

pub fn (s ItemUseOn) data() i32 {
	return i32(s.block_runtime_id)
}

// BucketFill is played when a bucket is filled with a liquid.
pub struct BucketFill {
pub:
	lava bool
}

pub fn (s BucketFill) event_name() string {
	return if s.lava { 'bucket.fill_lava' } else { 'bucket.fill_water' }
}

pub fn (s BucketFill) data() i32 {
	return no_data
}

// BucketEmpty is played when a bucket is emptied out.
pub struct BucketEmpty {
pub:
	lava bool
}

pub fn (s BucketEmpty) event_name() string {
	return if s.lava { 'bucket.empty_lava' } else { 'bucket.empty_water' }
}

pub fn (s BucketEmpty) data() i32 {
	return no_data
}

// BowShoot is played when an arrow is loosed from a bow.
pub struct BowShoot {}

pub fn (s BowShoot) event_name() string {
	return 'bow'
}

pub fn (s BowShoot) data() i32 {
	return no_data
}

// ArrowHit is played when an arrow hits something.
pub struct ArrowHit {}

pub fn (s ArrowHit) event_name() string {
	return 'bow.hit'
}

pub fn (s ArrowHit) data() i32 {
	return no_data
}

// Teleport is played when an entity teleports, such as by throwing an ender
// pearl.
pub struct Teleport {}

pub fn (s Teleport) event_name() string {
	return 'teleport'
}

pub fn (s Teleport) data() i32 {
	return no_data
}

// Totem is played when a totem of undying saves a player from dying.
pub struct Totem {}

pub fn (s Totem) event_name() string {
	return 'totem'
}

pub fn (s Totem) data() i32 {
	return no_data
}

// GoatHorn is played when a goat horn is used. The variant selects which of
// the eight horn melodies is played.
pub struct GoatHorn {
pub:
	variant int
}

pub fn (s GoatHorn) event_name() string {
	variant := if s.variant >= 0 && s.variant < 8 { s.variant } else { 0 }
	return 'item.goat_horn.sound.${variant}'
}

pub fn (s GoatHorn) data() i32 {
	return no_data
}
