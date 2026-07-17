module item

// compost_result is the shared UseOnBlockResult for any Compostable item
// used on a composter. Crops/seeds add one layer of compost per use. Real
// vanilla composting is probabilistic and empties into bone meal once full; both are
// simplified away here.
fn compost_result(block_name string) ?UseOnBlockResult {
	if block_name != 'minecraft:composter' {
		return none
	}
	return UseOnBlockResult{
		state_key:   'composter_fill_level'
		state_delta: 1
	}
}
