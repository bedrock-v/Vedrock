module block

// container_default_slots is how many slots every container in this file
// holds. A double chest is two of them side by side rather than a container
// with its own size.
pub const container_default_slots = 27

// ContainerKind describes a block that stores items: how it is opened, where
// its contents live and whether two of them join into one bigger container.
pub struct ContainerKind {
pub:
	identifier string
	slots      int = container_default_slots
	// player_scoped moves the contents onto the player instead of the block,
	// which is what makes an ender chest an ender chest.
	player_scoped bool
}

const shulker_box_suffix = '_shulker_box'

// container_kind returns what kind of container a block identifier names, or
// none when the block stores nothing.
pub fn container_kind(identifier string) ?ContainerKind {
	if identifier.ends_with(shulker_box_suffix) {
		return ContainerKind{
			identifier: identifier
		}
	}
	return match identifier {
		'minecraft:chest', 'minecraft:trapped_chest', 'minecraft:barrel' {
			ContainerKind{
				identifier: identifier
			}
		}
		'minecraft:ender_chest' {
			ContainerKind{
				identifier:    identifier
				player_scoped: true
			}
		}
		else {
			none
		}
	}
}

// container_kind_of returns the kind for a block runtime id.
pub fn container_kind_of(block_id int) ?ContainerKind {
	b := get(block_id) or { return none }
	return container_kind(b.identifier())
}
