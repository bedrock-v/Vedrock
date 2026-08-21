module gamedata

fn shapes() VoxelShapes {
	return load_voxel_shapes('../data/voxel_shapes.json') or {
		load_voxel_shapes('data/voxel_shapes.json') or { panic('cannot find data dir: ${err}') }
	}
}

fn test_load_voxel_shapes_names_point_at_their_shape() {
	loaded := shapes()
	assert loaded.shapes.len > 200
	assert loaded.names.len > 200
	for entry in loaded.names {
		assert int(entry.id) < loaded.shapes.len
	}
}

fn test_an_empty_shape_still_carries_one_plane_per_axis() {
	loaded := shapes()
	mut empty_id := -1
	for entry in loaded.names {
		if entry.name == 'minecraft:empty' {
			empty_id = int(entry.id)
			break
		}
	}
	assert empty_id >= 0
	empty := loaded.shapes[empty_id]
	assert empty.storage.len == 0
	assert empty.x_coordinates == [f32(0)]
	assert empty.y_coordinates == [f32(0)]
	assert empty.z_coordinates == [f32(0)]
}

fn test_a_full_cube_is_one_filled_cell() {
	loaded := shapes()
	mut cube_id := -1
	for entry in loaded.names {
		if entry.name == 'minecraft:unit_cube' {
			cube_id = int(entry.id)
			break
		}
	}
	assert cube_id >= 0
	cube := loaded.shapes[cube_id]
	assert cube.x_size == 1
	assert cube.y_size == 1
	assert cube.z_size == 1
	assert cube.storage == [u8(1)]
	assert cube.x_coordinates == [f32(0), 1.0]
	assert cube.y_coordinates == [f32(0), 1.0]
	assert cube.z_coordinates == [f32(0), 1.0]
}
