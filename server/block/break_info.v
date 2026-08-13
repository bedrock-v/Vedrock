module block

// Tool family bitflags. A block may accept several families at once, so they
// combine as a mask (leaves are cut by both shears and a sword).
pub const tool_type_none = 0
pub const tool_type_sword = 1
pub const tool_type_shovel = 2
pub const tool_type_pickaxe = 4
pub const tool_type_axe = 8
pub const tool_type_shears = 16
pub const tool_type_hoe = 32

// Harvest levels per tool tier. A block whose harvest level is 0 is harvested
// by anything, bare hands included.
pub const harvest_level_none = 0
pub const harvest_level_wood = 1
pub const harvest_level_gold = 2
pub const harvest_level_stone = 3
pub const harvest_level_copper = 3
pub const harvest_level_iron = 4
pub const harvest_level_diamond = 5
pub const harvest_level_netherite = 6

// Base break time is the hardness scaled by one of these, depending on
// whether the held tool is the right family and tier for the block.
const compatible_tool_multiplier = f32(1.5)
const incompatible_tool_multiplier = f32(5.0)

// BreakInfo is everything the break time formula needs about one block.
pub struct BreakInfo {
pub:
	hardness      f32 = 1.0
	tool_type     int
	harvest_level int
}

// breakable reports whether the block can be destroyed at all.
pub fn (i BreakInfo) breakable() bool {
	return i.hardness >= 0
}

// breaks_instantly reports whether the block is destroyed within one tick
// regardless of the held item.
pub fn (i BreakInfo) breaks_instantly() bool {
	return i.hardness == 0
}

// tool_compatible reports whether a tool of the given family and harvest
// level harvests this block, which decides both the break time multiplier
// and whether the block drops anything.
pub fn (i BreakInfo) tool_compatible(tool_type int, harvest_level int) bool {
	if i.hardness < 0 {
		return false
	}
	return i.tool_type == tool_type_none || i.harvest_level == harvest_level_none
		|| ((i.tool_type & tool_type) != 0 && harvest_level >= i.harvest_level)
}

// break_seconds is how long the block takes to break with a tool of the given
// family, harvest level and mining efficiency. Efficiency only counts when
// the tool family matches, so a diamond pickaxe is no faster than a hand on
// dirt.
pub fn (i BreakInfo) break_seconds(tool_type int, harvest_level int, efficiency f32) f32 {
	multiplier := if i.tool_compatible(tool_type, harvest_level) {
		compatible_tool_multiplier
	} else {
		incompatible_tool_multiplier
	}
	mut speed := f32(1.0)
	if (i.tool_type & tool_type) != 0 && efficiency > 0 {
		speed = efficiency
	}
	return i.hardness * multiplier / speed
}

// ToolRequirement is implemented by block classes that pin their own tool
// family and tier. Blocks that don't implement it fall back to the shared
// name based defaults.
pub interface ToolRequirement {
	tool_type() int
	harvest_level() int
}

// break_info_for resolves a block's break info, preferring an explicit
// ToolRequirement over the name based fallback.
fn break_info_for(b Block) BreakInfo {
	hardness := b.hardness()
	if b is ToolRequirement {
		return BreakInfo{
			hardness:      hardness
			tool_type:     b.tool_type()
			harvest_level: b.harvest_level()
		}
	}
	tool_type, harvest_level := fallback_tool(b.identifier())
	return BreakInfo{
		hardness:      hardness
		tool_type:     tool_type
		harvest_level: harvest_level
	}
}
