module db

import json2
import os
import bedrock_v.nbt
import server.world

fn block_entity_dir(tag string) string {
	dir := os.join_path(os.temp_dir(), 'vedrock_block_entity_${tag}')
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
	return dir
}

fn drop_dir(dir string) {
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
}

fn test_container_contents_survive_a_reload() {
	dir := block_entity_dir('items')
	defer {
		drop_dir(dir)
	}
	mut store := open_world(dir, world.overworld) or { panic(err) }
	mut w := new_world('items-test', store, 'flat', world.overworld)
	w.load()
	w.set_container_items(2, 70, -9, [
		ContainerSlotItem{
			slot:             3
			id:               17
			meta:             2
			count:            64
			block_runtime_id: 55
			raw_extra_data:   [u8(1), 2, 3]
		},
		ContainerSlotItem{
			slot:  11
			id:    5
			count: 1
		},
	])
	w.close() or { panic(err) }

	mut reopened := open_world(dir, world.overworld) or { panic(err) }
	mut back := new_world('items-test', reopened, 'flat', world.overworld)
	back.load()
	items := back.container_items(2, 70, -9)
	assert items.len == 2
	assert items[0].slot == 3
	assert items[0].id == 17
	assert items[0].meta == 2
	assert items[0].count == 64
	assert items[0].block_runtime_id == 55
	assert items[0].raw_extra_data == [u8(1), 2, 3]
	assert items[1].slot == 11
	assert items[1].count == 1
	back.close() or { panic(err) }
}

// Text and contents used to be two records at one position. Merging them means
// a block can carry both, which is what a kind combining them would need.
fn test_one_position_carries_every_kind_at_once() {
	mut w := new_world('mixed-test', none, 'flat', world.overworld)
	w.set_tile_text(4, 8, 15, 'labelled')
	w.set_container_items(4, 8, 15, [ContainerSlotItem{
		slot:  0
		id:    9
		count: 2
	}])

	assert w.tile_text(4, 8, 15) or { '' } == 'labelled'
	assert w.container_items(4, 8, 15).len == 1
	// Writing one kind must not drop the other.
	w.set_tile_text(4, 8, 15, 'relabelled')
	assert w.container_items(4, 8, 15).len == 1
	assert w.tile_text(4, 8, 15) or { '' } == 'relabelled'
}

fn test_a_new_kind_needs_nothing_from_the_storage_layer() {
	dir := block_entity_dir('newkind')
	defer {
		drop_dir(dir)
	}
	mut store := open_world(dir, world.overworld) or { panic(err) }
	mut w := new_world('newkind-test', store, 'flat', world.overworld)
	w.load()
	w.set_tile_text(1, 2, 3, 'sign')
	w.update_block_entity(1, 2, 3, 'BurnTime', nbt.Tag(i32(160)))
	w.close() or { panic(err) }

	mut reopened := open_world(dir, world.overworld) or { panic(err) }
	mut back := new_world('newkind-test', reopened, 'flat', world.overworld)
	back.load()
	assert back.tile_text(1, 2, 3) or { '' } == 'sign'
	data := back.block_entities[override_key(1, 2, 3)] or {
		assert false, 'the block entity did not come back'
		return
	}
	assert compound_int(data, 'BurnTime') == 160
	back.close() or { panic(err) }
}

// A container written before the merge is still read, so an existing world does
// not need a migration pass over its files.
fn test_containers_written_the_old_way_still_load() {
	dir := block_entity_dir('legacy')
	defer {
		drop_dir(dir)
	}
	mut store := open_world(dir, world.overworld) or { panic(err) }
	items := [ContainerSlotItem{
		slot:  7
		id:    42
		count: 5
	}]
	store.overrides.put(container_key(9, 9, 9), json2.encode(items).bytes()) or { panic(err) }
	store.close() or { panic(err) }

	mut reopened := open_world(dir, world.overworld) or { panic(err) }
	mut w := new_world('legacy-test', reopened, 'flat', world.overworld)
	w.load()
	back := w.container_items(9, 9, 9)
	assert back.len == 1
	assert back[0].slot == 7
	assert back[0].id == 42
	assert back[0].count == 5
	w.close() or { panic(err) }
}

fn test_merged_record_wins_over_the_legacy_one_at_same_pos() {
	dir := block_entity_dir('precedence')
	defer {
		drop_dir(dir)
	}
	mut store := open_world(dir, world.overworld) or { panic(err) }
	store.overrides.put(tile_key(1, 1, 1), 'written before the merge'.bytes()) or { panic(err) }
	store.set_block_entity(1, 1, 1, legacy_text_bytes('written after')) or { panic(err) }
	store.close() or { panic(err) }

	mut reopened := open_world(dir, world.overworld) or { panic(err) }
	mut w := new_world('precedence-test', reopened, 'flat', world.overworld)
	w.load()
	assert w.tile_text(1, 1, 1) or { '' } == 'written after'
	w.close() or { panic(err) }
}
