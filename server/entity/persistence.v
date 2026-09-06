module entity

import os
import json2
import bedrock_v.protocol.types
import server.effect

// SaveData contains the persistent state needed to recreate an entity.
// Temporary Behaviour state such as targets, cooldowns and paths is rebuilt
// after loading and is intentionally not stored.
//
// Projectiles are excluded from persistence by save_snapshot.
pub struct SaveData {
pub mut:
	type_name  string // Registry key (e.g. "zombie") used to reconstruct the Behaviour via Registry.create
	x          f32
	y          f32
	z          f32
	velocity_x f32
	velocity_y f32
	velocity_z f32
	pitch      f32
	yaw        f32
	head_yaw   f32
	health     f32
}

fn entities_path(dir string) string {
	return os.join_path(dir, 'entities.json')
}

// load_entities returns the entities saved in dir. Missing, unreadable or
// invalid save files are treated as an empty entity list.
pub fn load_entities(dir string) []SaveData {
	path := entities_path(dir)
	if !os.exists(path) {
		return []SaveData{}
	}
	text := os.read_file(path) or { return []SaveData{} }
	return json2.decode[[]SaveData](text) or { return []SaveData{} }
}

// save_entities atomically writes the entity list to dir, preserving the
// previous save if writing or renaming the temporary file fails.
pub fn save_entities(dir string, entities []SaveData) ! {
	os.mkdir_all(dir)!
	path := entities_path(dir)
	tmp := '${path}.tmp.${os.getpid()}'
	os.write_file(tmp, json2.encode(entities)) or {
		os.rm(tmp) or {}
		return err
	}
	os.rename(tmp, path) or {
		os.rm(tmp) or {}
		return err
	}
}

fn registry_key_from_identifier(identifier string) string {
	idx := identifier.index(':') or { return identifier }
	return identifier[idx + 1..]
}

// to_save_data captures Entity's instance state for persistence.
fn (e &Entity) to_save_data(type_name string) SaveData {
	return SaveData{
		type_name:  type_name
		x:          e.pos.x
		y:          e.pos.y
		z:          e.pos.z
		velocity_x: e.velocity.x
		velocity_y: e.velocity.y
		velocity_z: e.velocity.z
		pitch:      e.pitch
		yaw:        e.yaw
		head_yaw:   e.head_yaw
		health:     e.health
	}
}

// save_snapshot returns the persistent state of all non-transient entities.
// Projectiles and dropped items are excluded because their short lived state
// is not restored across restarts.
pub fn (mut m Manager) save_snapshot() []SaveData {
	mut out := []SaveData{}
	for e in m.snapshot() {
		if e.behaviour is ProjectileBehaviour || e.behaviour is ItemBehaviour {
			continue
		}
		out << e.to_save_data(registry_key_from_identifier(e.identifier))
	}
	return out
}

// restore_from_save recreates saved entities whose types are still
// registered. Unknown types are skipped without failing the world load.
//
// This must run on the owning world thread because live entity pointers are
// confined to that thread.
pub fn (mut m Manager) restore_from_save(reg &Registry, saved []SaveData) {
	for data in saved {
		behaviour := reg.create(data.type_name) or { continue }
		rid := m.host.allocate_runtime_id()
		mut e := &Entity{
			unique_id:  i64(rid)
			runtime_id: rid
			identifier: behaviour.identifier()
			dimensions: behaviour.dimensions()
			pos:        types.Vector3{data.x, data.y, data.z}
			floor_y:    data.y
			velocity:   types.Vector3{data.velocity_x, data.velocity_y, data.velocity_z}
			pitch:      data.pitch
			yaw:        data.yaw
			head_yaw:   data.head_yaw
			health:     data.health
			behaviour:  behaviour
			effects:    effect.new_manager()
		}
		m.mutex.lock()
		m.actors[rid] = ActorEntry{
			actor: e
		}
		m.mutex.unlock()
		for mut v in m.host.viewers_near(e.pos.x, e.pos.y, e.pos.z, view_radius) {
			v.view_entity_spawn(e)
		}
	}
}
