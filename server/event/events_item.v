module event

import server.player

// ItemUseData is dispatched right before a held item's effect is applied,
// either in the air (e.g. a goat horn's sound) or on a block (e.g. bone meal
// advancing a crop's growth). on_block reports which; x/y/z are only
// meaningful when on_block is true. Cancelling it stops the effect.
pub struct ItemUseData {
pub:
	item_name string
	meta      int
	on_block  bool
	x         int
	y         int
	z         int
pub mut:
	player player.View
}
