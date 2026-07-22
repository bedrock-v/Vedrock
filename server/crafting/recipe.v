module crafting

import protocol
import protocol.types

// RecipeInput describes one ingredient slot in a recipe.
pub struct RecipeInput {
pub:
	name     string // namespaced item id, e.g. "minecraft:oak_planks"
	metadata int    // damage/metadata value, 0 for most items
	count    int    // how many of this item are consumed
}

// Recipe is one crafting recipe. Shaped recipes fill input row-major across
// width × height; shapeless recipes set width=height=0 and list ingredients
// in any order.
pub struct Recipe {
pub:
	id           string // "minecraft:oak_planks"
	recipe_type  int    // protocol.recipe_shapeless or protocol.recipe_shaped
	width        int
	height       int
	input        []RecipeInput
	output_name  string
	output_meta  int
	output_count int
	block        string // "minecraft:crafting_table" or "" for 2x2 player grid
	priority     int
	network_id   u32
}

// Registry holds every known crafting recipe and assigns each a unique
// network id so the client can reference them in craft requests.
pub struct Registry {
mut:
	recipes       []Recipe
	by_network_id map[u32]int // network_id -> index in recipes
	next_id       u32
}

// new_registry returns an empty recipe Registry.
pub fn new_registry() Registry {
	return Registry{
		recipes:       []Recipe{}
		by_network_id: map[u32]int{}
		next_id:       u32(1)
	}
}

// register adds a recipe and assigns it a unique network_id.
pub fn (mut r Registry) register(rec Recipe) {
	mut owned := Recipe{
		id:           rec.id
		recipe_type:  rec.recipe_type
		width:        rec.width
		height:       rec.height
		input:        rec.input
		output_name:  rec.output_name
		output_meta:  rec.output_meta
		output_count: rec.output_count
		block:        rec.block
		priority:     rec.priority
		network_id:   r.next_id
	}
	r.next_id++
	r.by_network_id[owned.network_id] = r.recipes.len
	r.recipes << owned
}

// len returns how many recipes are registered.
pub fn (r &Registry) len() int {
	return r.recipes.len
}

// get returns the recipe with the given network id, or none.
pub fn (r &Registry) get(network_id u32) ?Recipe {
	idx := r.by_network_id[network_id] or { return none }
	if idx >= r.recipes.len {
		return none
	}
	return r.recipes[idx]
}

// all returns every registered recipe.
pub fn (r &Registry) all() []Recipe {
	return r.recipes
}

// default_input_descriptor builds an ItemDescriptorCount with descriptor_type
// default (1). The item is identified by its numeric network id + metadata.
// This is what vanilla Bedrock uses for all built-in items.
fn default_input_descriptor(network_id int, metadata int, count int) types.ItemDescriptorCount {
	return types.ItemDescriptorCount{
		descriptor_type: types.item_descriptor_default
		network_id:      i16(network_id)
		metadata_value:  i16(metadata)
		count:           count
	}
}

// crafting_data_packet builds a CraftingDataPacket from all registered
// recipes, resolving item names to network ids via the supplied map.
pub fn (r &Registry) crafting_data_packet(item_id_by_name map[string]int) protocol.CraftingDataPacket {
	mut packet := protocol.CraftingDataPacket{
		recipes:       []protocol.Recipe{}
		potion_recipes: []protocol.PotionRecipe{}
		potion_container_change_recipes: []protocol.PotionContainerChangeRecipe{}
		material_reducers: []protocol.MaterialReducer{}
		clear_recipes: true
	}
	for rec in r.recipes {
		packet.recipes << recipe_to_protocol(rec, item_id_by_name)
	}
	return packet
}

// recipe_to_protocol converts one internal Recipe to a protocol.Recipe.
fn recipe_to_protocol(rec Recipe, item_id_by_name map[string]int) protocol.Recipe {
	mut p := protocol.Recipe{
		recipe_type: rec.recipe_type
		recipe_id:   rec.id
		block:       rec.block
		priority:    rec.priority
		uuid:        make_recipe_uuid(rec.id)
		recipe_network_id: rec.network_id
		assume_symmetry:   false
		unlock_requirement: protocol.RecipeUnlockRequirement{
			context:     1
			ingredients: []types.ItemDescriptorCount{}
		}
	}
	if rec.recipe_type == protocol.recipe_shaped {
		p.width = rec.width
		p.height = rec.height
	}
	p.input = []types.ItemDescriptorCount{}
	for ing in rec.input {
		id := item_id_by_name[ing.name] or { 0 }
		p.input << default_input_descriptor(id, ing.metadata, ing.count)
	}
	output_id := item_id_by_name[rec.output_name] or { 0 }
	p.output << types.ItemStack{
		id:               output_id
		meta:             rec.output_meta
		count:            rec.output_count
		block_runtime_id: 0
		raw_extra_data:   []u8{}
	}
	return p
}

// make_recipe_uuid builds a deterministic, RFC 4122-compliant UUID from a
// recipe id string. We use a djb2 hash spread across 16 bytes, then set the
// version (4=random) and variant (10xx) bits so the client accepts it.
fn make_recipe_uuid(id string) types.UUID {
	mut b := []u8{len: 16}
	mut h := u32(5381)
	for c in id {
		h = ((h << 5) + h) + u32(c)
	}
	// Spread the hash across all 16 bytes.
	for i in 0 .. 16 {
		b[i] = u8(((h >> (i % 4 * 8)) ^ (h >> ((i + 7) % 16))) & 0xff)
	}
	// XOR with the string bytes for more entropy.
	for i in 0 .. id.len {
		b[i % 16] ^= u8(id[i])
	}
	// Set RFC 4122 version 4 (random) and variant 1 bits.
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return types.uuid_from_bytes(b)
}
