module item

import server.block

// MiningTool is implemented by items that mine a matching block family faster
// than a bare hand. Items that don't implement it break every block at hand
// speed.
pub interface MiningTool {
	// block_tool_type is the block tool family bitflag this item belongs to.
	block_tool_type() int
	// harvest_level is the tier this item harvests up to.
	harvest_level() int
}

pub fn (i ToolItem) block_tool_type() int {
	return match i.tool_type {
		.sword { block.tool_type_sword }
		.pickaxe { block.tool_type_pickaxe }
		.axe { block.tool_type_axe }
		.shovel { block.tool_type_shovel }
		.hoe { block.tool_type_hoe }
	}
}

pub fn (i ToolItem) harvest_level() int {
	return i.tier.harvest_level()
}

fn (t ToolTier) harvest_level() int {
	return match t {
		.wood { block.harvest_level_wood }
		.gold { block.harvest_level_gold }
		.stone { block.harvest_level_stone }
		.copper { block.harvest_level_copper }
		.iron { block.harvest_level_iron }
		.diamond { block.harvest_level_diamond }
		.netherite { block.harvest_level_netherite }
	}
}
