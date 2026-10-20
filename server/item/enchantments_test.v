module item

import server.enchant

fn sharpness_id() int {
	e := enchant.get_by_name('sharpness') or { panic('sharpness is not registered') }
	return e.id()
}

fn test_an_item_without_nbt_carries_nothing() {
	assert enchantments_from_nbt([]u8{}).len == 0
	assert enchantment_level([]u8{}, 'sharpness') == 0
}

fn test_enchantments_survive_a_write_and_read() {
	raw := enchanted_nbt([
		enchant.Applied{
			eid:   sharpness_id()
			level: 3
		},
	])
	assert raw.len > 0
	entries := enchantments_from_nbt(raw)
	assert entries.len == 1
	assert entries[0].eid == sharpness_id()
	assert entries[0].level == 3
	assert enchantment_level(raw, 'sharpness') == 3
	assert enchantment_level(raw, 'unbreaking') == 0
}

fn test_several_enchantments_round_trip() {
	unbreaking := enchant.get_by_name('unbreaking') or { panic('unbreaking is not registered') }
	raw := enchanted_nbt([
		enchant.Applied{
			eid:   sharpness_id()
			level: 5
		},
		enchant.Applied{
			eid:   unbreaking.id()
			level: 2
		},
	])
	assert enchantments_from_nbt(raw).len == 2
	assert enchantment_level(raw, 'sharpness') == 5
	assert enchantment_level(raw, 'unbreaking') == 2
}

fn test_an_empty_list_writes_no_nbt() {
	assert enchanted_nbt([]enchant.Applied{}).len == 0
}

fn test_malformed_nbt_is_read_as_nothing() {
	assert enchantments_from_nbt([u8(1), 2, 3]).len == 0
	assert enchantment_level([u8(0xff), 0xff, 9, 9], 'sharpness') == 0
}

fn test_a_book_and_an_enchantment_do_not_read_as_each_other() {
	book := writable_book_nbt(['a page'])
	assert enchantments_from_nbt(book).len == 0
	raw := enchanted_nbt([
		enchant.Applied{
			eid:   sharpness_id()
			level: 1
		},
	])
	assert book_pages_from_nbt(raw).len == 0
}
