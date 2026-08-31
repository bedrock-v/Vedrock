module gamedata

import os
import x.json2

// VoxelShape is one block shape in the form the client reads it: a grid of
// filled cells plus the cutting planes on each axis that bound them.
pub struct VoxelShape {
pub:
	x_size        u8
	y_size        u8
	z_size        u8
	storage       []u8
	x_coordinates []f32
	y_coordinates []f32
	z_coordinates []f32
}

// VoxelShapeName ties an identifier to a shape's position in the list. The
// client keeps its own copy of the vanilla shapes but only finds one by the
// name the server gives it, so the names have to travel with the shapes.
pub struct VoxelShapeName {
pub:
	name string
	id   u16
}

pub struct VoxelShapes {
pub:
	shapes []VoxelShape
	names  []VoxelShapeName
}

// VoxelBox is one axis aligned box of a shape, in block units.
struct VoxelBox {
	min [3]f32
	max [3]f32
}

// load_voxel_shapes reads the vanilla shape list. Shapes without an identifier
// are still loaded, because the named ones are found by their position.
pub fn load_voxel_shapes(path string) !VoxelShapes {
	document := json2.decode[json2.Any](os.read_file(path)!)!
	entries := document.as_array()
	if entries.len == 0 {
		return error('voxel shapes: the list is empty')
	}

	mut shapes := []VoxelShape{cap: entries.len}
	mut names := []VoxelShapeName{}
	for entry in entries {
		fields := entry.as_map()
		identifier := any_str(fields, 'identifier')
		if identifier != '' {
			names << VoxelShapeName{
				name: identifier
				id:   u16(shapes.len)
			}
		}
		shapes << build_voxel_shape((fields['boxes'] or { json2.Any('') }).as_array())!
	}
	return VoxelShapes{
		shapes: shapes
		names:  names
	}
}

fn build_voxel_shape(boxes []json2.Any) !VoxelShape {
	if boxes.len == 0 {
		// An empty shape still carries one cutting plane per axis, the same as
		// the game sends.
		return VoxelShape{
			x_coordinates: [f32(0)]
			y_coordinates: [f32(0)]
			z_coordinates: [f32(0)]
		}
	}

	mut parsed := []VoxelBox{cap: boxes.len}
	mut xs := []f32{cap: boxes.len * 2}
	mut ys := []f32{cap: boxes.len * 2}
	mut zs := []f32{cap: boxes.len * 2}
	for box in boxes {
		b := parse_voxel_box(box)!
		parsed << b
		xs << b.min[0]
		xs << b.max[0]
		ys << b.min[1]
		ys << b.max[1]
		zs << b.min[2]
		zs << b.max[2]
	}
	x_coordinates := sorted_unique(xs)
	y_coordinates := sorted_unique(ys)
	z_coordinates := sorted_unique(zs)

	res_x := x_coordinates.len - 1
	res_y := y_coordinates.len - 1
	res_z := z_coordinates.len - 1

	// A cell is filled when its midpoint falls inside any of the boxes, which
	// is what turns overlapping boxes into one grid.
	mut storage := []u8{len: (res_x * res_y * res_z + 7) / 8}
	for z in 0 .. res_z {
		for y in 0 .. res_y {
			for x in 0 .. res_x {
				mid_x := (x_coordinates[x] + x_coordinates[x + 1]) / 2.0
				mid_y := (y_coordinates[y] + y_coordinates[y + 1]) / 2.0
				mid_z := (z_coordinates[z] + z_coordinates[z + 1]) / 2.0
				for b in parsed {
					if mid_x >= b.min[0] && mid_x <= b.max[0] && mid_y >= b.min[1]
						&& mid_y <= b.max[1] && mid_z >= b.min[2] && mid_z <= b.max[2] {
						index := z + (y * res_z) + (x * res_z * res_y)
						storage[index / 8] |= u8(1) << (index % 8)
						break
					}
				}
			}
		}
	}

	return VoxelShape{
		x_size:        u8(res_x)
		y_size:        u8(res_y)
		z_size:        u8(res_z)
		storage:       storage
		x_coordinates: x_coordinates
		y_coordinates: y_coordinates
		z_coordinates: z_coordinates
	}
}

fn parse_voxel_box(value json2.Any) !VoxelBox {
	corners := value.as_array()
	if corners.len != 2 {
		return error('voxel shapes: a box needs two corners')
	}
	return VoxelBox{
		min: parse_voxel_corner(corners[0])!
		max: parse_voxel_corner(corners[1])!
	}
}

// parse_voxel_corner reads one corner, converting the pixel coordinates the
// file carries into the block units the client expects.
fn parse_voxel_corner(value json2.Any) ![3]f32 {
	values := value.as_array()
	if values.len != 3 {
		return error('voxel shapes: a corner needs three coordinates')
	}
	return [f32(values[0].int()) / 16.0, f32(values[1].int()) / 16.0, f32(values[2].int()) / 16.0]!
}

fn sorted_unique(values []f32) []f32 {
	mut sorted := values.clone()
	sorted.sort()
	mut out := []f32{cap: sorted.len}
	for value in sorted {
		if out.len == 0 || out.last() != value {
			out << value
		}
	}
	return out
}
