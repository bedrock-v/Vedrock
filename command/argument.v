module command

import strconv

// Bedrock protocol "type_info" flags/values used to describe a command
// parameter to the client for autocomplete. The protocol package
// stores type_info as an opaque u32 (protocol/src/available_commands_packet.v).
pub const arg_flag_valid = u32(0x100000)
pub const arg_flag_enum = u32(0x200000)

pub const arg_type_int = u32(1)
pub const arg_type_target = u32(8)
pub const arg_type_string = u32(56)
pub const arg_type_rawtext = u32(70)

// Argument is one typed, positional slot in a command's syntax. Registry uses it to 
// validate raw tokens before Command.execute runs and to build real CommandParameter data 
// for the client's AvailableCommandsPacket, replacing per command manual arg-count checks.
pub interface Argument {
	name() string
	optional() bool
	// consumes_rest reports whether this argument swallows every remaining
	// raw token (e.g. a trailing chat message). Only the last argument in a command's list may do this.
	consumes_rest() bool
	// matches reports whether raw (a single token or the joined tail when consumes_rest() is true) is an acceptable value.
	matches(raw string) bool
	// network_type_info is the Bedrock protocol type_info payload for
	// non-enum arguments; unused for enum arguments (see enum_values()).
	network_type_info() u32
	// enum_values returns the accepted values for an enum style argument or an empty list for non enum arguments.
	enum_values() []string
}

pub struct IntArgument {
	arg_name     string
	arg_optional bool
}

pub fn (a IntArgument) name() string {
	return a.arg_name
}

pub fn (a IntArgument) optional() bool {
	return a.arg_optional
}

pub fn (a IntArgument) consumes_rest() bool {
	return false
}

pub fn (a IntArgument) matches(raw string) bool {
	strconv.atoi(raw) or { return false }
	return true
}

pub fn (a IntArgument) network_type_info() u32 {
	return arg_type_int
}

pub fn (a IntArgument) enum_values() []string {
	return []
}

// StringArgument matches a single non empty token (e.g. a player name).
pub struct StringArgument {
	arg_name     string
	arg_optional bool
}

pub fn (a StringArgument) name() string {
	return a.arg_name
}

pub fn (a StringArgument) optional() bool {
	return a.arg_optional
}

pub fn (a StringArgument) consumes_rest() bool {
	return false
}

pub fn (a StringArgument) matches(raw string) bool {
	return raw.len > 0
}

pub fn (a StringArgument) network_type_info() u32 {
	return arg_type_string
}

pub fn (a StringArgument) enum_values() []string {
	return []
}

// TargetArgument matches a single token naming another connected player.
pub struct TargetArgument {
	arg_name     string
	arg_optional bool
}

pub fn (a TargetArgument) name() string {
	return a.arg_name
}

pub fn (a TargetArgument) optional() bool {
	return a.arg_optional
}

pub fn (a TargetArgument) consumes_rest() bool {
	return false
}

pub fn (a TargetArgument) matches(raw string) bool {
	return raw.len > 0
}

pub fn (a TargetArgument) network_type_info() u32 {
	return arg_type_target
}

pub fn (a TargetArgument) enum_values() []string {
	return []
}

// TextArgument consumes the rest of the line as one string (e.g. a chat/kick message). 
// Must be the last argument in a command's list.
pub struct TextArgument {
	arg_name     string
	arg_optional bool
}

pub fn (a TextArgument) name() string {
	return a.arg_name
}

pub fn (a TextArgument) optional() bool {
	return a.arg_optional
}

pub fn (a TextArgument) consumes_rest() bool {
	return true
}

pub fn (a TextArgument) matches(raw string) bool {
	return a.arg_optional || raw.len > 0
}

pub fn (a TextArgument) network_type_info() u32 {
	return arg_type_rawtext
}

pub fn (a TextArgument) enum_values() []string {
	return []
}

// StringEnumArgument matches a fixed and case-insensitive set of values (e.g. gamemode names). 
pub struct StringEnumArgument {
	arg_name     string
	arg_optional bool
	values       []string
}

pub fn (a StringEnumArgument) name() string {
	return a.arg_name
}

pub fn (a StringEnumArgument) optional() bool {
	return a.arg_optional
}

pub fn (a StringEnumArgument) consumes_rest() bool {
	return false
}

pub fn (a StringEnumArgument) matches(raw string) bool {
	needle := raw.to_lower()
	for v in a.values {
		if v.to_lower() == needle {
			return true
		}
	}
	return false
}

pub fn (a StringEnumArgument) network_type_info() u32 {
	return 0
}

pub fn (a StringEnumArgument) enum_values() []string {
	return a.values
}

pub fn validate_arguments(spec []Argument, raw []string) bool {
	mut i := 0
	for a in spec {
		if i >= raw.len {
			if a.optional() {
				continue
			}
			return false
		}
		token := if a.consumes_rest() { raw[i..].join(' ') } else { raw[i] }
		if !a.matches(token) {
			return false
		}
		i = if a.consumes_rest() { raw.len } else { i + 1 }
	}
	return true
}

pub fn usage_line(cmd Command) string {
	mut parts := []string{}
	for a in cmd.arguments() {
		if a.optional() {
			parts << '[${a.name()}]'
		} else {
			parts << '<${a.name()}>'
		}
	}
	if parts.len == 0 {
		return 'Usage: /${cmd.name()}'
	}
	return 'Usage: /${cmd.name()} ${parts.join(' ')}'
}
