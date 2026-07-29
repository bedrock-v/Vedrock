module world

fn assert_full_box(b AABB) {
	assert b.min_x == 0.0
	assert b.min_y == 0.0
	assert b.min_z == 0.0
	assert b.max_x == 1.0
	assert b.max_y == 1.0
	assert b.max_z == 1.0
}

fn test_solid_model_has_full_collision_and_faces() {
	m := solid_model()
	boxes := m.boxes()
	assert boxes.len == 1
	assert_full_box(boxes[0])
	for face in 0 .. 6 {
		assert m.face_solid(face)
		assert m.face_center_solid(face)
	}
}

fn test_empty_model_has_no_collision_or_faces() {
	m := empty_model()
	assert m.boxes().len == 0
	for face in 0 .. 6 {
		assert !m.face_solid(face)
		assert !m.face_center_solid(face)
	}
}

fn test_slab_model_exposes_only_filled_half_face() {
	bottom := slab_model(false, false)
	assert bottom.boxes().len == 1
	assert bottom.face_solid(0)
	assert !bottom.face_solid(1)
	assert bottom.face_center_solid(0)
	assert !bottom.face_center_solid(1)

	top := slab_model(false, true)
	assert !top.face_solid(0)
	assert top.face_solid(1)
	assert !top.face_center_solid(0)
	assert top.face_center_solid(1)

	double := slab_model(true, false)
	for face in 0 .. 6 {
		assert double.face_solid(face)
		assert double.face_center_solid(face)
	}
}

fn test_stair_model_has_half_and_back_support() {
	normal := stair_model(5, false)
	assert normal.boxes().len == 2
	assert normal.face_solid(0)
	assert !normal.face_solid(1)
	assert normal.face_solid(5)
	assert !normal.face_solid(4)

	upside_down := stair_model(5, true)
	assert !upside_down.face_solid(0)
	assert upside_down.face_solid(1)
	assert upside_down.face_solid(5)
}

fn test_ladder_model_has_thin_collision_but_no_solid_faces() {
	m := ladder_model(2)
	assert m.boxes().len == 1
	for face in 0 .. 6 {
		assert !m.face_solid(face)
		assert !m.face_center_solid(face)
	}
}

fn test_fence_and_thin_models_connect_to_neighbor_models() {
	fence := fence_model()
	fence_boxes := fence.boxes_with_neighbors({
		5: solid_model()
	})
	assert fence_boxes.len == 1
	assert fence_boxes[0].max_x == 1.0
	assert fence_boxes[0].max_y == 1.5

	pane := thin_model()
	pane_boxes := pane.boxes_with_neighbors({
		2: solid_model()
		3: thin_model()
	})
	assert pane_boxes.len == 1
	assert pane_boxes[0].min_z == 0.0
	assert pane_boxes[0].max_z == 1.0
}

fn test_stair_model_uses_neighbor_corner_shape() {
	plain := stair_model(5, false)
	assert plain.boxes().len == 2
	corner := plain.boxes_with_neighbors({
		5: stair_model(3, false)
	})
	assert corner.len == 2
	assert corner[1].min_x == 0.5
	assert corner[1].max_x == 1.0
	assert corner[1].max_z - corner[1].min_z == 0.5
}

fn test_open_gate_has_no_collision() {
	assert fence_gate_model(2, true).boxes().len == 0
	assert fence_gate_model(2, false).boxes().len == 1
}

fn test_absolute_boxes_translate_local_model() {
	boxes := absolute_boxes(solid_model(), 10, 20, -3)
	assert boxes.len == 1
	assert boxes[0].min_x == 10.0
	assert boxes[0].min_y == 20.0
	assert boxes[0].min_z == -3.0
	assert boxes[0].max_x == 11.0
	assert boxes[0].max_y == 21.0
	assert boxes[0].max_z == -2.0
}

fn test_offset_by_shifts_every_axis() {
	b := box(0, 0, 0, 1, 1, 1).offset_by(2, -1, 0.5)
	assert b.min_x == 2.0
	assert b.max_x == 3.0
	assert b.min_y == -1.0
	assert b.max_y == 0.0
	assert b.min_z == 0.5
	assert b.max_z == 1.5
}

fn test_offset_x_clamps_to_the_gap_when_overlapping_on_y_and_z() {
	moving := box(0, 0, 0, 1, 1, 1)
	obstacle := box(2, 0, 0, 3, 1, 1)
	assert moving.offset_x(obstacle, 5.0) == 1.0
	assert moving.offset_x(obstacle, 0.5) == 0.5
	assert moving.offset_x(obstacle, -5.0) == -5.0
}

fn test_offset_x_ignores_obstacle_not_overlapping_on_y_or_z() {
	moving := box(0, 0, 0, 1, 1, 1)
	above := box(2, 5, 0, 3, 6, 1)
	assert moving.offset_x(above, 5.0) == 5.0
}

fn test_offset_y_and_offset_z_mirror_offset_x() {
	moving := box(0, 0, 0, 1, 1, 1)
	floor := box(0, -2, 0, 1, -1, 1)
	assert moving.offset_y(floor, -5.0) == -1.0

	wall := box(0, 0, 2, 1, 1, 3)
	assert moving.offset_z(wall, 5.0) == 1.0
}
