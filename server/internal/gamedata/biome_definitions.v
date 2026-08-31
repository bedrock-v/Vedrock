module gamedata

import compress.gzip
import os
import bedrock_v.nbt
import bedrock_v.protocol.serializer

// Mojang ships the biome registry as a big endian NBT document. The wire form
// the client expects is a flat BiomeDefinitionListPacket payload, so the two
// are walked side by side: every write below mirrors one field of the packet's
// encoder, in the same order.
//
// Keys the document leaves out are defaults, which is why every read falls
// back rather than failing.

// expression_op_none is what an absent molang expression type serialises to.
// Zero is a real operator, so a missing type has to go out as -1 or the client
// tries to evaluate an expression that was never there.
const expression_op_none = i32(-1)

fn tag_compound(t nbt.Tag) ?nbt.Compound {
	if t is nbt.Compound {
		return t
	}
	return none
}

fn child(c nbt.Compound, key string) ?nbt.Compound {
	return tag_compound(c.get(key) or { return none })
}

fn children(c nbt.Compound, key string) []nbt.Compound {
	list := c.get(key) or { return [] }
	if list is nbt.List {
		mut out := []nbt.Compound{cap: list.values.len}
		for value in list.values {
			out << tag_compound(value) or { continue }
		}
		return out
	}
	return []
}

fn number(c nbt.Compound, key string) i64 {
	value := c.get(key) or { return 0 }
	return match value {
		i8 { i64(value) }
		i16 { i64(value) }
		i32 { i64(value) }
		i64 { value }
		f32 { i64(value) }
		f64 { i64(value) }
		else { i64(0) }
	}
}

fn decimal(c nbt.Compound, key string) f32 {
	value := c.get(key) or { return 0 }
	return match value {
		f32 { value }
		f64 { f32(value) }
		i8 { f32(value) }
		i16 { f32(value) }
		i32 { f32(value) }
		i64 { f32(value) }
		else { f32(0) }
	}
}

fn text(c nbt.Compound, key string) string {
	value := c.get(key) or { return '' }
	if value is string {
		return value
	}
	return ''
}

fn numbers(c nbt.Compound, key string) []i64 {
	list := c.get(key) or { return [] }
	if list is nbt.List {
		mut out := []i64{cap: list.values.len}
		for value in list.values {
			out << match value {
				i8 { i64(value) }
				i16 { i64(value) }
				i32 { i64(value) }
				i64 { value }
				else { i64(0) }
			}
		}
		return out
	}
	if list is nbt.IntArray {
		return list.values.map(i64(it))
	}
	return []
}

fn decimals(c nbt.Compound, key string) []f32 {
	list := c.get(key) or { return [] }
	if list is nbt.List {
		mut out := []f32{cap: list.values.len}
		for value in list.values {
			out << match value {
				f32 { value }
				f64 { f32(value) }
				else { f32(0) }
			}
		}
		return out
	}
	return []
}

// write_expression_op writes a molang expression type, or the "no expression"
// marker when the document omits it.
fn write_expression_op(mut w serializer.Writer, c nbt.Compound, key string) {
	if c.get(key) == none {
		w.write_varint32(expression_op_none)
		return
	}
	w.write_varint32(i32(number(c, key)))
}

fn write_compound_list(mut w serializer.Writer, entries []nbt.Compound, encode fn (mut serializer.Writer, nbt.Compound)) {
	w.write_varuint32(u32(entries.len))
	for entry in entries {
		encode(mut w, entry)
	}
}

fn write_int_list(mut w serializer.Writer, values []i64) {
	w.write_varuint32(u32(values.len))
	for value in values {
		w.le_i32(i32(value))
	}
}

fn write_coordinate(mut w serializer.Writer, c nbt.Compound) {
	write_expression_op(mut w, c, 'minValueType')
	w.le_u16(u16(number(c, 'minValue')))
	write_expression_op(mut w, c, 'maxValueType')
	w.le_u16(u16(number(c, 'maxValue')))
	w.le_u32(u32(number(c, 'gridOffset')))
	w.le_u32(u32(number(c, 'gridStepSize')))
	w.write_varint32(i32(number(c, 'distribution')))
}

fn write_scatter(mut w serializer.Writer, c nbt.Compound) {
	write_compound_list(mut w, children(c, 'coordinates'), write_coordinate)
	w.write_varint32(i32(number(c, 'evalOrder')))
	write_expression_op(mut w, c, 'chancePercentType')
	w.le_u16(u16(number(c, 'chancePercent')))
	w.le_i32(i32(number(c, 'chanceNumerator')))
	w.le_i32(i32(number(c, 'chanceDenominator')))
	write_expression_op(mut w, c, 'iterationsType')
	w.le_u16(u16(number(c, 'iterations')))
}

fn write_feature(mut w serializer.Writer, c nbt.Compound) {
	write_scatter(mut w, child(c, 'scatter') or { nbt.new_compound() })
	w.le_u16(u16(number(c, 'feature')))
	w.le_u16(u16(number(c, 'identifier')))
	w.le_u16(u16(number(c, 'pass')))
	w.bool(number(c, 'canUseInternalFeature') != 0)
}

fn write_climate(mut w serializer.Writer, c nbt.Compound) {
	w.le_f32(decimal(c, 'temperature'))
	w.le_f32(decimal(c, 'downfall'))
	w.le_f32(decimal(c, 'snowAccumulationMin'))
	w.le_f32(decimal(c, 'snowAccumulationMax'))
}

fn write_mountain_params(mut w serializer.Writer, c nbt.Compound) {
	w.le_i32(i32(number(c, 'steepBlock')))
	w.bool(number(c, 'northSlopes') != 0)
	w.bool(number(c, 'southSlopes') != 0)
	w.bool(number(c, 'westSlopes') != 0)
	w.bool(number(c, 'eastSlopes') != 0)
	w.bool(number(c, 'topSlideEnabled') != 0)
}

fn write_surface_material(mut w serializer.Writer, c nbt.Compound) {
	w.le_i32(i32(number(c, 'topBlock')))
	w.le_i32(i32(number(c, 'midBlock')))
	w.le_i32(i32(number(c, 'seaFloorBlock')))
	w.le_i32(i32(number(c, 'foundationBlock')))
	w.le_i32(i32(number(c, 'seaBlock')))
	w.le_i32(i32(number(c, 'seaFloorDepth')))
}

fn write_element(mut w serializer.Writer, c nbt.Compound) {
	w.le_f32(decimal(c, 'noiseFrequencyScale'))
	w.le_f32(decimal(c, 'noiseLowerBound'))
	w.le_f32(decimal(c, 'noiseUpperBound'))
	write_expression_op(mut w, c, 'heightMinType')
	w.le_u16(u16(number(c, 'heightMin')))
	write_expression_op(mut w, c, 'heightMaxType')
	w.le_u16(u16(number(c, 'heightMax')))
	write_surface_material(mut w, child(c, 'adjustedMaterials') or { nbt.new_compound() })
}

fn write_weighted(mut w serializer.Writer, c nbt.Compound) {
	w.le_u16(u16(number(c, 'biomeIdentifier')))
	w.le_i32(i32(number(c, 'weight')))
}

fn write_conditional(mut w serializer.Writer, c nbt.Compound) {
	write_compound_list(mut w, children(c, 'transformsInto'), write_weighted)
	w.le_u16(u16(number(c, 'conditionJson')))
	w.le_u32(u32(number(c, 'minPassingNeighbors')))
}

fn write_weighted_temperature(mut w serializer.Writer, c nbt.Compound) {
	w.write_varint32(i32(number(c, 'temperature')))
	w.le_i32(i32(number(c, 'weight')))
}

fn write_overworld_gen_rules(mut w serializer.Writer, c nbt.Compound) {
	write_compound_list(mut w, children(c, 'hillsTransformations'), write_weighted)
	write_compound_list(mut w, children(c, 'mutateTransformations'), write_weighted)
	write_compound_list(mut w, children(c, 'riverTransformations'), write_weighted)
	write_compound_list(mut w, children(c, 'shoreTransformations'), write_weighted)
	write_compound_list(mut w, children(c, 'preHillsEdge'), write_conditional)
	write_compound_list(mut w, children(c, 'postShoreEdge'), write_conditional)
	write_compound_list(mut w, children(c, 'climate'), write_weighted_temperature)
}

fn write_multinoise_gen_rules(mut w serializer.Writer, c nbt.Compound) {
	w.le_f32(decimal(c, 'temperature'))
	w.le_f32(decimal(c, 'humidity'))
	w.le_f32(decimal(c, 'altitude'))
	w.le_f32(decimal(c, 'weirdness'))
	w.le_f32(decimal(c, 'weight'))
}

fn write_replacement(mut w serializer.Writer, c nbt.Compound) {
	w.le_i16(i16(number(c, 'biome')))
	w.le_i16(i16(number(c, 'dimension')))
	targets := numbers(c, 'targetBiomes')
	w.write_varuint32(u32(targets.len))
	for target in targets {
		w.le_i16(i16(target))
	}
	w.le_f32(decimal(c, 'amount'))
	w.le_f32(decimal(c, 'noiseFrequencyScale'))
	w.le_i32(i32(number(c, 'replacementIndex')))
}

fn write_mesa_surface(mut w serializer.Writer, c nbt.Compound) {
	w.le_i32(i32(number(c, 'clayMaterial')))
	w.le_i32(i32(number(c, 'hardClayMaterial')))
	w.bool(number(c, 'brycePillars') != 0)
	w.bool(number(c, 'hasForest') != 0)
}

fn write_optional_block(mut w serializer.Writer, c nbt.Compound, key string) {
	if c.get(key) == none {
		w.bool(false)
		return
	}
	w.bool(true)
	w.le_i32(i32(number(c, key)))
}

fn write_capped_surface(mut w serializer.Writer, c nbt.Compound) {
	write_int_list(mut w, numbers(c, 'floorBlocks'))
	write_int_list(mut w, numbers(c, 'ceilingBlocks'))
	write_optional_block(mut w, c, 'seaBlock')
	write_optional_block(mut w, c, 'foundationBlock')
	write_optional_block(mut w, c, 'beachBlock')
}

fn write_noise_block(mut w serializer.Writer, c nbt.Compound) {
	w.write_string(text(c, 'noise'))
	w.le_f32(decimal(c, 'threshold'))
	if range := child(c, 'range') {
		w.le_f32(decimal(range, 'min'))
		w.le_f32(decimal(range, 'max'))
	} else {
		w.le_f32(0)
		w.le_f32(0)
	}
	w.le_i32(i32(number(c, 'block')))
}

fn write_noise_gradient_surface(mut w serializer.Writer, c nbt.Compound) {
	write_int_list(mut w, numbers(c, 'nonReplaceableBlocks'))
	write_compound_list(mut w, children(c, 'gradientBlocks'), write_noise_block)
	noise := child(c, 'noise') or { nbt.new_compound() }
	w.write_string(text(noise, 'name'))
	w.le_i32(i32(number(noise, 'firstOctave')))
	amplitudes := decimals(noise, 'amplitudes')
	w.write_varuint32(u32(amplitudes.len))
	for amplitude in amplitudes {
		w.le_f32(amplitude)
	}
}

fn write_surface_builder(mut w serializer.Writer, c nbt.Compound) {
	if materials := child(c, 'surfaceMaterials') {
		w.bool(true)
		write_surface_material(mut w, materials)
	} else {
		w.bool(false)
	}
	w.bool(number(c, 'hasDefaultOverworldSurface') != 0)
	w.bool(number(c, 'hasSwampSurface') != 0)
	w.bool(number(c, 'hasFrozenOceanSurface') != 0)
	w.bool(number(c, 'hasTheEndSurface') != 0)
	if mesa := child(c, 'mesaSurface') {
		w.bool(true)
		write_mesa_surface(mut w, mesa)
	} else {
		w.bool(false)
	}
	if capped := child(c, 'cappedSurface') {
		w.bool(true)
		write_capped_surface(mut w, capped)
	} else {
		w.bool(false)
	}
	if gradient := child(c, 'noiseGradientSurface') {
		w.bool(true)
		write_noise_gradient_surface(mut w, gradient)
	} else {
		w.bool(false)
	}
}

fn write_chunk_gen_data(mut w serializer.Writer, c nbt.Compound) {
	if climate := child(c, 'climate') {
		w.bool(true)
		write_climate(mut w, climate)
	} else {
		w.bool(false)
	}
	if features := child(c, 'consolidatedFeatures') {
		w.bool(true)
		write_compound_list(mut w, children(features, 'features'), write_feature)
	} else {
		w.bool(false)
	}
	if mountain := child(c, 'mountainParams') {
		w.bool(true)
		write_mountain_params(mut w, mountain)
	} else {
		w.bool(false)
	}
	if adjustment := child(c, 'surfaceMaterialAdjustment') {
		w.bool(true)
		write_compound_list(mut w, children(adjustment, 'biomeElements'), write_element)
	} else {
		w.bool(false)
	}
	if overworld := child(c, 'overworldGenRules') {
		w.bool(true)
		write_overworld_gen_rules(mut w, overworld)
	} else {
		w.bool(false)
	}
	if multinoise := child(c, 'multinoiseGenRules') {
		w.bool(true)
		write_multinoise_gen_rules(mut w, multinoise)
	} else {
		w.bool(false)
	}
	if legacy := child(c, 'legacyWorldGenRules') {
		w.bool(true)
		write_compound_list(mut w, children(legacy, 'legacyPreHills'), write_conditional)
	} else {
		w.bool(false)
	}
	if replacements := child(c, 'replacementBiomes') {
		w.bool(true)
		write_compound_list(mut w, children(replacements, 'replacements'), write_replacement)
	} else {
		w.bool(false)
	}
	if c.get('villageType') == none {
		w.bool(false)
	} else {
		w.bool(true)
		w.u8(u8(number(c, 'villageType')))
	}
	if surface := child(c, 'surfaceBuilderData') {
		w.bool(true)
		write_surface_builder(mut w, surface)
	} else {
		w.bool(false)
	}
	if sub_surface := child(c, 'subSurfaceBuilderData') {
		w.bool(true)
		write_surface_builder(mut w, sub_surface)
	} else {
		w.bool(false)
	}
}

fn write_biome(mut w serializer.Writer, entry nbt.Compound) {
	w.le_u16(u16(number(entry, 'index')))
	data := child(entry, 'data') or { nbt.new_compound() }
	w.le_u16(u16(number(data, 'id')))
	w.le_f32(decimal(data, 'temperature'))
	w.le_f32(decimal(data, 'downfall'))
	w.le_f32(decimal(data, 'foliageSnow'))
	w.le_f32(decimal(data, 'depth'))
	w.le_f32(decimal(data, 'scale'))
	w.le_i32(i32(number(data, 'mapWaterColorARGB')))
	w.bool(number(data, 'rain') != 0)
	if tags := child(data, 'tags') {
		w.bool(true)
		values := numbers(tags, 'tags')
		w.write_varuint32(u32(values.len))
		for value in values {
			w.le_u16(u16(value))
		}
	} else {
		w.bool(false)
	}
	if chunk_gen := child(data, 'chunkGenData') {
		w.bool(true)
		write_chunk_gen_data(mut w, chunk_gen)
	} else {
		w.bool(false)
	}
}

fn ungzip(document []u8) ![]u8 {
	if document.len > 1 && document[0] == 0x1f && document[1] == 0x8b {
		return gzip.decompress(document)!
	}
	return document
}

// encode_biome_definitions turns Mojang's biome_definitions.nbt into the
// BiomeDefinitionListPacket payload the client expects.
pub fn encode_biome_definitions(document []u8) ![]u8 {
	root := parse_be_nbt(ungzip(document)!)!
	top := tag_compound(root.tag) or { return error('biome definitions: root is not a compound') }
	biomes := children(top, 'biomeData')
	if biomes.len == 0 {
		return error('biome definitions: biomeData is empty')
	}
	mut w := serializer.new_writer()
	w.write_varuint32(u32(biomes.len))
	for biome in biomes {
		write_biome(mut w, biome)
	}
	mut names := []string{}
	if list := top.get('biomeStringList') {
		if list is nbt.List {
			for value in list.values {
				if value is string {
					names << value
				}
			}
		}
	}
	w.write_varuint32(u32(names.len))
	for name in names {
		w.write_string(name)
	}
	return w.bytes()
}

// load_biome_definitions reads Mojang's biome registry from path and returns
// the packet payload for it.
pub fn load_biome_definitions(path string) ![]u8 {
	return encode_biome_definitions(os.read_bytes(path)!)!
}

// load_entity_identifiers reads Mojang's actor registry, the list the client
// resolves every actor type against, its own player included.
pub fn load_entity_identifiers(path string) ![]nbt.Tag {
	root := parse_be_nbt(ungzip(os.read_bytes(path)!)!)!
	top := tag_compound(root.tag) or { return error('entity identifiers: root is not a compound') }
	list := top.get('idlist') or { return error('entity identifiers: no idlist') }
	if list is nbt.List {
		return list.values
	}
	return error('entity identifiers: idlist is not a list')
}
