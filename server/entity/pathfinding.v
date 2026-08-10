module entity

import math
import protocol.types

// Pathfinding is intentionally bounded to keep per tick work predictable.
// path_max_search_radius limits how far a search may reach while
// path_max_nodes_expanded limits how much of that area it may explore.
//
// Searches that exhaust either limit return no path. Callers then fall back
// to direct movement instead of leaving the entity stuck.
pub const path_max_search_radius = f32(32.0)
pub const path_max_nodes_expanded = 400

pub const path_max_safe_drop = 3

struct PathNode {
	x int
	y int
	z int
}

struct Offset {
	dx int
	dz int
}

const move_offsets = [
	Offset{1, 0},
	Offset{-1, 0},
	Offset{0, 1},
	Offset{0, -1},
	Offset{1, 1},
	Offset{1, -1},
	Offset{-1, 1},
	Offset{-1, -1},
]

fn node_key(n PathNode) string {
	return '${n.x},${n.y},${n.z}'
}

// walkable reports whether the entity has enough clear space at the given
// position and a solid block directly beneath it.
fn walkable(mut host Host, x int, y int, z int, clearance int) bool {
	for dy := 0; dy < clearance; dy++ {
		if host.collision_boxes(x, y + dy, z).len > 0 {
			return false
		}
	}
	return host.collision_boxes(x, y - 1, z).len > 0
}

// neighbors returns cells reachable in one move, including safe drops.
// Diagonal movement is allowed only when both adjoining orthogonal cells
// are also walkable, preventing movement through solid corners.
fn neighbors(mut host Host, n PathNode, clearance int) []PathNode {
	mut out := []PathNode{}
	for off in move_offsets {
		nx := n.x + off.dx
		nz := n.z + off.dz

		if walkable(mut host, nx, n.y, nz, clearance) {
			if off.dx != 0 && off.dz != 0 {
				if !walkable(mut host, n.x + off.dx, n.y, n.z, clearance)
					|| !walkable(mut host, n.x, n.y, n.z + off.dz, clearance) {
					continue
				}
			}
			out << PathNode{nx, n.y, nz}
			continue
		}

		for drop := 1; drop <= path_max_safe_drop; drop++ {
			ny := n.y - drop
			mut shaft_clear := true
			for check_y := n.y - 1; check_y > ny; check_y-- {
				if host.collision_boxes(nx, check_y, nz).len > 0 {
					shaft_clear = false
					break
				}
			}
			if !shaft_clear {
				break
			}
			if walkable(mut host, nx, ny, nz, clearance) {
				out << PathNode{nx, ny, nz}
				break
			}
		}
	}
	return out
}

fn step_cost(a PathNode, b PathNode) f32 {
	mut cost := if b.x != a.x && b.z != a.z { f32(1.4142135) } else { f32(1.0) }
	if b.y < a.y {
		// mild preference for level ground over dropping when both reach
		// the goal about equally well.
		cost += f32(a.y - b.y) * 0.5
	}
	return cost
}

fn heuristic(a PathNode, b PathNode) f32 {
	dx := f32(b.x - a.x)
	dz := f32(b.z - a.z)
	return math.sqrtf(dx * dx + dz * dz)
}

fn reconstruct_path(came_from map[string]PathNode, goal PathNode) []types.Vector3 {
	mut nodes := []PathNode{}
	nodes << goal
	mut current := goal
	for {
		prev := came_from[node_key(current)] or { break }
		nodes << prev
		current = prev
	}
	if nodes.len <= 1 {
		return []types.Vector3{}
	}
	mut waypoints := []types.Vector3{cap: nodes.len - 1}
	for i := nodes.len - 2; i >= 0; i-- {
		n := nodes[i]
		waypoints << types.Vector3{f32(n.x) + 0.5, f32(n.y), f32(n.z) + 0.5}
	}
	return waypoints
}

// find_path searches for a bounded route from start to the target column.
// It returns block centered waypoints excluding the starting cell, or none
// when the start is not walkable, no route exists or a search limit is hit.
//
// Entity height determines required headroom. Width is intentionally ignored,
// so wide entities may clip corners.
pub fn find_path(mut host Host, start types.Vector3, target types.Vector3, dims Dimensions) ?[]types.Vector3 {
	mut clearance := int(dims.height)
	if f32(clearance) < dims.height {
		clearance++
	}
	if clearance < 1 {
		clearance = 1
	}

	start_node :=
		PathNode{int(math_floor(start.x)), int(math_floor(start.y)), int(math_floor(start.z))}
	goal :=
		PathNode{int(math_floor(target.x)), int(math_floor(target.y)), int(math_floor(target.z))}

	if !walkable(mut host, start_node.x, start_node.y, start_node.z, clearance) {
		return none
	}

	mut open := []PathNode{}
	mut g_score := map[string]f32{}
	mut f_score := map[string]f32{}
	mut came_from := map[string]PathNode{}
	mut closed := map[string]bool{}

	start_key := node_key(start_node)
	g_score[start_key] = 0
	f_score[start_key] = heuristic(start_node, goal)
	open << start_node

	mut expanded := 0
	for open.len > 0 {
		expanded++
		if expanded > path_max_nodes_expanded {
			return none
		}

		mut best_idx := 0
		mut best_f := f_score[node_key(open[0])] or { f32(1e9) }
		for i := 1; i < open.len; i++ {
			f := f_score[node_key(open[i])] or { f32(1e9) }
			if f < best_f {
				best_f = f
				best_idx = i
			}
		}
		current := open[best_idx]
		open.delete(best_idx)
		current_key := node_key(current)
		if closed[current_key] {
			continue
		}
		closed[current_key] = true

		if current.x == goal.x && current.z == goal.z {
			return reconstruct_path(came_from, current)
		}

		if heuristic(start_node, current) > path_max_search_radius {
			continue
		}

		current_g := g_score[current_key] or { f32(1e9) }
		for neighbor in neighbors(mut host, current, clearance) {
			neighbor_key := node_key(neighbor)
			if closed[neighbor_key] {
				continue
			}
			tentative_g := current_g + step_cost(current, neighbor)
			existing_g := g_score[neighbor_key] or { f32(1e9) }
			if tentative_g < existing_g {
				came_from[neighbor_key] = current
				g_score[neighbor_key] = tentative_g
				f_score[neighbor_key] = tentative_g + heuristic(neighbor, goal)
				open << neighbor
			}
		}
	}
	return none
}
