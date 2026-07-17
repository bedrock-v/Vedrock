module world

// Dimension describes one Bedrock dimension's world height bounds, network id
// and default generator. min_y/subchunk_count size every Chunk generated or loaded for it.
pub struct Dimension {
pub:
	id                int
	min_y             int
	subchunk_count    int
	default_generator string
}

pub fn (d Dimension) max_y() int {
	return d.min_y + d.subchunk_count * 16 - 1
}

pub const overworld = Dimension{
	id:                0
	min_y:             dimension_min_y
	subchunk_count:    dimension_subchunk_count
	default_generator: 'normal'
}

pub const nether = Dimension{
	id:                1
	min_y:             0
	subchunk_count:    8
	default_generator: 'nether'
}

pub const the_end = Dimension{
	id:                2
	min_y:             0
	subchunk_count:    16
	default_generator: 'end'
}

pub fn dimension_by_id(id int) ?Dimension {
	return match id {
		0 { overworld }
		1 { nether }
		2 { the_end }
		else { none }
	}
}

pub fn dimension_by_name(name string) ?Dimension {
	return match name.to_lower() {
		'overworld', 'world' { overworld }
		'nether', 'the_nether' { nether }
		'end', 'the_end' { the_end }
		else { none }
	}
}

pub fn (d Dimension) name() string {
	return match d.id {
		1 { 'nether' }
		2 { 'end' }
		else { 'overworld' }
	}
}
