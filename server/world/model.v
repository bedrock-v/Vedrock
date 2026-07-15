module world

const model_epsilon = f32(0.0001)

pub enum ModelKind {
	solid
	empty
	slab
	stair
	ladder
	thin
}

pub struct AABB {
pub:
	min_x f32
	min_y f32
	min_z f32
	max_x f32
	max_y f32
	max_z f32
}

pub struct BlockModel {
pub:
	kind        ModelKind
	facing_face int
	top         bool
	double      bool
	upside_down bool
}

pub fn box(min_x f32, min_y f32, min_z f32, max_x f32, max_y f32, max_z f32) AABB {
	return AABB{
		min_x: min_x
		min_y: min_y
		min_z: min_z
		max_x: max_x
		max_y: max_y
		max_z: max_z
	}
}

pub fn solid_model() BlockModel {
	return BlockModel{
		kind: .solid
	}
}

pub fn empty_model() BlockModel {
	return BlockModel{
		kind: .empty
	}
}

pub fn slab_model(double bool, top bool) BlockModel {
	return BlockModel{
		kind:   .slab
		double: double
		top:    top
	}
}

pub fn stair_model(facing_face int, upside_down bool) BlockModel {
	return BlockModel{
		kind:        .stair
		facing_face: facing_face
		upside_down: upside_down
	}
}

pub fn ladder_model(facing_face int) BlockModel {
	return BlockModel{
		kind:        .ladder
		facing_face: facing_face
	}
}

pub fn thin_model() BlockModel {
	return BlockModel{
		kind: .thin
	}
}

pub fn (m BlockModel) boxes() []AABB {
	return match m.kind {
		.solid { [box(0, 0, 0, 1, 1, 1)] }
		.empty { []AABB{} }
		.slab { m.slab_boxes() }
		.stair { m.stair_boxes() }
		.ladder { m.ladder_boxes() }
		.thin { [box(0.4375, 0, 0.4375, 0.5625, 1, 0.5625)] }
	}
}

fn (m BlockModel) slab_boxes() []AABB {
	if m.double {
		return [box(0, 0, 0, 1, 1, 1)]
	}
	if m.top {
		return [box(0, 0.5, 0, 1, 1, 1)]
	}
	return [box(0, 0, 0, 1, 0.5, 1)]
}

fn (m BlockModel) stair_boxes() []AABB {
	mut boxes := []AABB{}
	if m.upside_down {
		boxes << box(0, 0.5, 0, 1, 1, 1)
	} else {
		boxes << box(0, 0, 0, 1, 0.5, 1)
	}
	y0 := if m.upside_down { f32(0) } else { f32(0.5) }
	y1 := if m.upside_down { f32(0.5) } else { f32(1) }
	boxes << match m.facing_face {
		2 { box(0, y0, 0, 1, y1, 0.5) }
		3 { box(0, y0, 0.5, 1, y1, 1) }
		4 { box(0, y0, 0, 0.5, y1, 1) }
		5 { box(0.5, y0, 0, 1, y1, 1) }
		else { box(0, y0, 0.5, 1, y1, 1) }
	}

	return boxes
}

fn (m BlockModel) ladder_boxes() []AABB {
	return [
		match m.facing_face {
			2 { box(0, 0, 0, 1, 1, 0.1875) }
			3 { box(0, 0, 0.8125, 1, 1, 1) }
			4 { box(0, 0, 0, 0.1875, 1, 1) }
			5 { box(0.8125, 0, 0, 1, 1, 1) }
			else { box(0, 0, 0, 1, 1, 0.1875) }
		},
	]
}

pub fn (m BlockModel) face_solid(face int) bool {
	return match m.kind {
		.solid {
			true
		}
		.empty, .ladder {
			false
		}
		.slab {
			if m.double {
				true
			} else if m.top {
				face == 1
			} else {
				face == 0
			}
		}
		.stair {
			(face == 1 && m.upside_down) || (face == 0 && !m.upside_down) || face == m.facing_face
		}
		.thin {
			face == 0
		}
	}
}

pub fn (m BlockModel) face_center_solid(face int) bool {
	if m.kind == .empty || m.kind == .ladder {
		return false
	}
	for b in m.boxes() {
		if b.face_center_solid(face) {
			return true
		}
	}
	return false
}

pub fn (b AABB) face_center_solid(face int) bool {
	return match face {
		0 {
			b.min_y <= model_epsilon && between_half(b.min_x, b.max_x)
				&& between_half(b.min_z, b.max_z)
		}
		1 {
			b.max_y >= 1.0 - model_epsilon && between_half(b.min_x, b.max_x)
				&& between_half(b.min_z, b.max_z)
		}
		2 {
			b.min_z <= model_epsilon && between_half(b.min_x, b.max_x)
				&& between_half(b.min_y, b.max_y)
		}
		3 {
			b.max_z >= 1.0 - model_epsilon && between_half(b.min_x, b.max_x)
				&& between_half(b.min_y, b.max_y)
		}
		4 {
			b.min_x <= model_epsilon && between_half(b.min_z, b.max_z)
				&& between_half(b.min_y, b.max_y)
		}
		5 {
			b.max_x >= 1.0 - model_epsilon && between_half(b.min_z, b.max_z)
				&& between_half(b.min_y, b.max_y)
		}
		else {
			false
		}
	}
}

fn between_half(min f32, max f32) bool {
	return min <= 0.5 + model_epsilon && max >= 0.5 - model_epsilon
}

pub fn (b AABB) translated(x int, y int, z int) AABB {
	return AABB{
		min_x: b.min_x + f32(x)
		min_y: b.min_y + f32(y)
		min_z: b.min_z + f32(z)
		max_x: b.max_x + f32(x)
		max_y: b.max_y + f32(y)
		max_z: b.max_z + f32(z)
	}
}

pub fn (b AABB) overlaps(other AABB) bool {
	return b.min_x < other.max_x && b.max_x > other.min_x && b.min_y < other.max_y
		&& b.max_y > other.min_y && b.min_z < other.max_z && b.max_z > other.min_z
}

pub fn absolute_boxes(model BlockModel, x int, y int, z int) []AABB {
	mut out := []AABB{}
	for b in model.boxes() {
		out << b.translated(x, y, z)
	}
	return out
}
