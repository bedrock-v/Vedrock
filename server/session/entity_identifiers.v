module session

import os
import bedrock_v.nbt
import server.entity
import server.internal.gamedata

// The client resolves every actor type against this registry, its own player
// included, so it has to arrive before any actor data referring to one.
const vanilla_entity_identifiers = gamedata.load_entity_identifiers(os.join_path('data',
	'entity_identifiers.nbt')) or { []nbt.Tag{} }

// entity_identifiers merges the vanilla actor list with the registered custom
// entities, so custom types stay summonable without dropping the vanilla ones
// the client cannot do without.
fn (s &NetworkSession) entity_identifiers() nbt.RootTag {
	mut entries := vanilla_entity_identifiers.clone()
	custom := entity.custom_identifiers_nbt()
	if custom_root := compound_of(custom.tag) {
		if list := custom_root.get('idlist') {
			if list is nbt.List {
				entries << list.values
			}
		}
	}
	mut root := nbt.new_compound()
	root.set('idlist', nbt.Tag(nbt.List{
		element_type: nbt.tag_compound
		values:       entries
	}))
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(root)
	}
}

fn compound_of(t nbt.Tag) ?nbt.Compound {
	if t is nbt.Compound {
		return t
	}
	return none
}
