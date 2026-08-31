module gamedata

import os
import bedrock_v.nbt

// BlockDefinition is one of the blocks the game drives from data rather than
// implementing natively: the identifier the client resolves and the property
// NBT it builds render, collision and menu state from.
pub struct BlockDefinition {
pub:
	name       string
	properties nbt.RootTag
}

// load_block_definitions reads the data driven block registry. A client that
// never receives one of these falls back to the raw identifier, draws no icon
// and refuses to place the block.
pub fn load_block_definitions(path string) ![]BlockDefinition {
	root := parse_be_nbt(ungzip(os.read_bytes(path)!)!)!
	top := tag_compound(root.tag) or { return error('block definitions: root is not a compound') }
	entries := children(top, 'blocks')
	if entries.len == 0 {
		return error('block definitions: blocks is empty')
	}
	mut out := []BlockDefinition{cap: entries.len}
	for entry in entries {
		name := text(entry, 'name')
		if name == '' {
			return error('block definitions: an entry has no name')
		}
		properties := child(entry, 'properties') or {
			return error('block definitions: ${name} has no properties')
		}
		out << BlockDefinition{
			name:       name
			properties: nbt.RootTag{
				name: ''
				tag:  nbt.Tag(properties)
			}
		}
	}
	return out
}
