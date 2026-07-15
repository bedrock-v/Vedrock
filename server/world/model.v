module world

const model_epsilon = f32(0.0001)

pub enum ModelKind {
	solid
	empty
	slab
	stair
	ladder
	thin
	fence
	wall
	fence_gate
	door
	trapdoor
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
	open        bool
	wall_north  string
	wall_east   string
	wall_south  string
	wall_west   string
	post        bool
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

pub fn fence_model() BlockModel {
	return BlockModel{
		kind: .fence
	}
}

pub fn wall_model(north string, east string, south string, west string, post bool) BlockModel {
	return BlockModel{
		kind:       .wall
		wall_north: north
		wall_east:  east
		wall_south: south
		wall_west:  west
		post:       post
	}
}

pub fn fence_gate_model(facing_face int, open bool) BlockModel {
	return BlockModel{
		kind:        .fence_gate
		facing_face: facing_face
		open:        open
	}
}

pub fn door_model(facing_face int, open bool) BlockModel {
	return BlockModel{
		kind:        .door
		facing_face: facing_face
		open:        open
	}
}

pub fn trapdoor_model(facing_face int, open bool, top bool) BlockModel {
	return BlockModel{
		kind:        .trapdoor
		facing_face: facing_face
		open:        open
		top:         top
	}
}

pub fn (m BlockModel) boxes() []AABB {
	return m.boxes_with_neighbors(map[int]BlockModel{})
}

pub fn (m BlockModel) boxes_with_neighbors(neighbors map[int]BlockModel) []AABB {
	return match m.kind {
		.solid { [box(0, 0, 0, 1, 1, 1)] }
		.empty { []AABB{} }
		.slab { m.slab_boxes() }
		.stair { m.stair_boxes_with_neighbors(neighbors) }
		.ladder { m.ladder_boxes() }
		.thin { m.thin_boxes(neighbors) }
		.fence { m.fence_boxes(neighbors) }
		.wall { m.wall_boxes() }
		.fence_gate { m.fence_gate_boxes() }
		.door { m.door_boxes() }
		.trapdoor { m.trapdoor_boxes() }
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
	return m.stair_boxes_with_neighbors(map[int]BlockModel{})
}

fn (m BlockModel) stair_boxes_with_neighbors(neighbors map[int]BlockModel) []AABB {
	mut boxes := []AABB{}
	if m.upside_down {
		boxes << box(0, 0.5, 0, 1, 1, 1)
	} else {
		boxes << box(0, 0, 0, 1, 0.5, 1)
	}
	y0 := if m.upside_down { f32(0) } else { f32(0.5) }
	y1 := if m.upside_down { f32(0.5) } else { f32(1) }
	corner := m.stair_corner_type(neighbors)
	match corner {
		1 {
			boxes << m.stair_half_box(y0, y1)
			boxes << stair_quarter_box(face_opposite(m.facing_face),
				rotate_right_face(m.facing_face), y0, y1)
		}
		2 {
			boxes << m.stair_half_box(y0, y1)
			boxes << stair_quarter_box(face_opposite(m.facing_face),
				rotate_left_face(m.facing_face), y0, y1)
		}
		3 {
			boxes << stair_quarter_box(m.facing_face, rotate_right_face(m.facing_face), y0, y1)
		}
		4 {
			boxes << stair_quarter_box(m.facing_face, rotate_left_face(m.facing_face), y0, y1)
		}
		else {
			boxes << m.stair_half_box(y0, y1)
		}
	}

	return boxes
}

fn (m BlockModel) stair_half_box(y0 f32, y1 f32) AABB {
	return match m.facing_face {
		2 { box(0, y0, 0, 1, y1, 0.5) }
		3 { box(0, y0, 0.5, 1, y1, 1) }
		4 { box(0, y0, 0, 0.5, y1, 1) }
		5 { box(0.5, y0, 0, 1, y1, 1) }
		else { box(0, y0, 0.5, 1, y1, 1) }
	}
}

fn (m BlockModel) stair_corner_type(neighbors map[int]BlockModel) int {
	rotated := rotate_right_face(m.facing_face)
	if closed_side := neighbors[m.facing_face] {
		if closed_side.kind == .stair && closed_side.upside_down == m.upside_down {
			if closed_side.facing_face == rotated {
				return 4
			}
			if closed_side.facing_face == face_opposite(rotated) {
				if side := neighbors[rotated] {
					if side.kind == .stair && side.facing_face == m.facing_face
						&& side.upside_down == m.upside_down {
						return 0
					}
				}
				return 3
			}
		}
	}
	if open_side := neighbors[face_opposite(m.facing_face)] {
		if open_side.kind == .stair && open_side.upside_down == m.upside_down {
			if open_side.facing_face == rotated {
				if side := neighbors[rotated] {
					if side.kind == .stair && side.facing_face == m.facing_face
						&& side.upside_down == m.upside_down {
						return 0
					}
				}
				return 1
			}
			if open_side.facing_face == face_opposite(rotated) {
				return 2
			}
		}
	}
	return 0
}

fn stair_quarter_box(face_a int, face_b int, y0 f32, y1 f32) AABB {
	mut min_x := f32(0)
	mut max_x := f32(1)
	mut min_z := f32(0)
	mut max_z := f32(1)
	for face in [face_a, face_b] {
		match face {
			2 { max_z = 0.5 }
			3 { min_z = 0.5 }
			4 { max_x = 0.5 }
			5 { min_x = 0.5 }
			else {}
		}
	}
	return box(min_x, y0, min_z, max_x, y1, max_z)
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

fn (m BlockModel) thin_boxes(neighbors map[int]BlockModel) []AABB {
	north := thin_connects(neighbors, 2)
	south := thin_connects(neighbors, 3)
	west := thin_connects(neighbors, 4)
	east := thin_connects(neighbors, 5)
	mut boxes := []AABB{}
	if west || east {
		mut min_x := f32(0.4375)
		mut max_x := f32(0.5625)
		if west {
			min_x = 0
		}
		if east {
			max_x = 1
		}
		boxes << box(min_x, 0, 0.4375, max_x, 1, 0.5625)
	}
	if north || south {
		mut min_z := f32(0.4375)
		mut max_z := f32(0.5625)
		if north {
			min_z = 0
		}
		if south {
			max_z = 1
		}
		boxes << box(0.4375, 0, min_z, 0.5625, 1, max_z)
	}
	if boxes.len == 0 {
		boxes << box(0.4375, 0, 0.4375, 0.5625, 1, 0.5625)
	}
	return boxes
}

fn (m BlockModel) fence_boxes(neighbors map[int]BlockModel) []AABB {
	north := fence_connects(neighbors, 2)
	south := fence_connects(neighbors, 3)
	west := fence_connects(neighbors, 4)
	east := fence_connects(neighbors, 5)
	mut boxes := []AABB{}
	if west || east {
		mut min_x := f32(0.375)
		mut max_x := f32(0.625)
		if west {
			min_x = 0
		}
		if east {
			max_x = 1
		}
		boxes << box(min_x, 0, 0.375, max_x, 1.5, 0.625)
	}
	if north || south {
		mut min_z := f32(0.375)
		mut max_z := f32(0.625)
		if north {
			min_z = 0
		}
		if south {
			max_z = 1
		}
		boxes << box(0.375, 0, min_z, 0.625, 1.5, max_z)
	}
	if boxes.len == 0 {
		boxes << box(0.375, 0, 0.375, 0.625, 1.5, 0.625)
	}
	return boxes
}

fn (m BlockModel) wall_boxes() []AABB {
	mut boxes := []AABB{}
	if m.post {
		boxes << box(0.25, 0, 0.25, 0.75, 1.5, 0.75)
	}
	if m.wall_west != 'none' || m.wall_east != 'none' {
		mut min_x := f32(0.25)
		mut max_x := f32(0.75)
		if m.wall_west != 'none' {
			min_x = 0
		}
		if m.wall_east != 'none' {
			max_x = 1
		}
		boxes << box(min_x, 0, 0.25, max_x, wall_height(m.wall_west, m.wall_east), 0.75)
	}
	if m.wall_north != 'none' || m.wall_south != 'none' {
		mut min_z := f32(0.25)
		mut max_z := f32(0.75)
		if m.wall_north != 'none' {
			min_z = 0
		}
		if m.wall_south != 'none' {
			max_z = 1
		}
		boxes << box(0.25, 0, min_z, 0.75, wall_height(m.wall_north, m.wall_south), max_z)
	}
	if boxes.len == 0 {
		boxes << box(0.25, 0, 0.25, 0.75, 1.5, 0.75)
	}
	return boxes
}

fn wall_height(a string, b string) f32 {
	if a == 'tall' || b == 'tall' {
		return 1.5
	}
	return 1.0
}

fn (m BlockModel) fence_gate_boxes() []AABB {
	if m.open {
		return []AABB{}
	}
	if m.facing_face == 2 || m.facing_face == 3 {
		return [box(0, 0, 0.375, 1, 1.5, 0.625)]
	}
	return [box(0.375, 0, 0, 0.625, 1.5, 1)]
}

fn (m BlockModel) door_boxes() []AABB {
	if m.open {
		return match m.facing_face {
			2 { [box(0, 0, 0, 0.1875, 1, 1)] }
			3 { [box(0.8125, 0, 0, 1, 1, 1)] }
			4 { [box(0, 0, 0.8125, 1, 1, 1)] }
			5 { [box(0, 0, 0, 1, 1, 0.1875)] }
			else { [box(0, 0, 0, 1, 1, 0.1875)] }
		}
	}
	return match m.facing_face {
		2 { [box(0, 0, 0, 1, 1, 0.1875)] }
		3 { [box(0, 0, 0.8125, 1, 1, 1)] }
		4 { [box(0, 0, 0, 0.1875, 1, 1)] }
		5 { [box(0.8125, 0, 0, 1, 1, 1)] }
		else { [box(0, 0, 0, 1, 1, 0.1875)] }
	}
}

fn (m BlockModel) trapdoor_boxes() []AABB {
	if m.open {
		return match m.facing_face {
			2 { [box(0, 0, 0, 1, 1, 0.1875)] }
			3 { [box(0, 0, 0.8125, 1, 1, 1)] }
			4 { [box(0, 0, 0, 0.1875, 1, 1)] }
			5 { [box(0.8125, 0, 0, 1, 1, 1)] }
			else { [box(0, 0, 0, 1, 1, 0.1875)] }
		}
	}
	if m.top {
		return [box(0, 0.8125, 0, 1, 1, 1)]
	}
	return [box(0, 0, 0, 1, 0.1875, 1)]
}

pub fn (m BlockModel) face_solid(face int) bool {
	return match m.kind {
		.solid {
			true
		}
		.empty, .ladder, .fence_gate, .door {
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
		.fence, .wall {
			face == 0 || face == 1
		}
		.trapdoor {
			if m.open {
				false
			} else if m.top {
				face == 1
			} else {
				face == 0
			}
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

pub fn absolute_boxes_with_neighbors(model BlockModel, neighbors map[int]BlockModel, x int, y int, z int) []AABB {
	mut out := []AABB{}
	for b in model.boxes_with_neighbors(neighbors) {
		out << b.translated(x, y, z)
	}
	return out
}

fn neighbor_connect_model(neighbors map[int]BlockModel, face int) ?BlockModel {
	return neighbors[face] or { return none }
}

fn thin_connects(neighbors map[int]BlockModel, face int) bool {
	side := neighbor_connect_model(neighbors, face) or { return false }
	return side.kind == .thin || side.kind == .wall || side.face_solid(face_opposite(face))
}

fn fence_connects(neighbors map[int]BlockModel, face int) bool {
	side := neighbor_connect_model(neighbors, face) or { return false }
	return side.kind == .fence || side.kind == .fence_gate || side.face_solid(face_opposite(face))
}

fn face_opposite(face int) int {
	return match face {
		0 { 1 }
		1 { 0 }
		2 { 3 }
		3 { 2 }
		4 { 5 }
		5 { 4 }
		else { face }
	}
}

fn rotate_right_face(face int) int {
	return match face {
		2 { 5 }
		5 { 3 }
		3 { 4 }
		4 { 2 }
		else { face }
	}
}

fn rotate_left_face(face int) int {
	return match face {
		2 { 4 }
		4 { 3 }
		3 { 5 }
		5 { 2 }
		else { face }
	}
}
