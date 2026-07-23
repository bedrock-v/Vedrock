module effect

pub const night_vision = Type{
	id:       16
	name:     'night_vision'
	lasting:  true
	rgb:      [u8(0x1f), u8(0x1f), u8(0xa1)]!
	category: .beneficial
}
