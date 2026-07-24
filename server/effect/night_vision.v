module effect

pub const night_vision = Type{
	id:       16
	name:     'night_vision'
	lasting:  true
	rgb:      [u8(0xc2), u8(0xff), u8(0x66)]!
	category: .beneficial
}
