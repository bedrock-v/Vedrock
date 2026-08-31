module skin

fn test_new_allocates_the_pixel_buffer() {
	s := new(64, 64)
	assert s.width() == 64
	assert s.height() == 64
	assert s.pix.len == 64 * 64 * 4
}

fn test_fill_paints_every_pixel() {
	mut s := new(2, 2)
	s.fill(Colour{
		r: 1
		g: 2
		b: 3
		a: 4
	})
	assert s.at(1, 1)! == Colour{1, 2, 3, 4}
}

fn test_at_rejects_coordinates_outside_the_skin() {
	s := new(2, 2)
	s.at(2, 0) or { return }
	assert false, 'expected an out of bounds pixel to be rejected'
}

fn test_a_new_cape_holds_no_image() {
	assert !Cape{}.exists()
	assert new_cape(32, 64).exists()
}

fn test_model_config_round_trips_through_its_resource_patch() {
	mut cfg := new_model_config()
	cfg.animated_face = 'geometry.face'
	decoded := decode_model_config(cfg.encode())!
	assert decoded.default_model == default_geometry
	assert decoded.animated_face == 'geometry.face'
}

fn test_model_config_leaves_out_an_unset_animated_face() {
	assert !new_model_config().encode().contains('animated_face')
}

fn test_new_animation_starts_with_a_single_frame() {
	a := new_animation(32, 32, 0, .body_32x32)
	assert a.frame_count == 1
	assert a.typ() == AnimationType.body_32x32
	assert a.pix.len == 32 * 32 * 4
}
