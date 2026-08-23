module gamedata

import compress.gzip
import compress.deflate

// GunzipSink collects decompressed chunks into a buffer that was sized up front.
struct GunzipSink {
mut:
	out []u8
}

fn gunzip_chunk(chunk []u8, userdata voidptr) int {
	mut sink := unsafe { &GunzipSink(userdata) }
	sink.out << chunk
	return chunk.len
}

// gunzip decompresses a gzip stream into a buffer preallocated from the
// stream's own ISIZE footer.
//
// gzip.decompress grows its output by repeated appends, so a payload that ends
// up at 4MB churns through several times that in intermediate arrays - enough,
// on the block palette, to push the collector's heap to over 20MB during boot
// and leave it fragmented afterwards. Sizing the buffer once costs the payload
// and nothing else.
pub fn gunzip(data []u8) ![]u8 {
	if data.len < 4 {
		return error('gzip stream too short')
	}
	// ISIZE is the last four bytes, little-endian: the payload size mod 2^32.
	size := u32(data[data.len - 4]) | (u32(data[data.len - 3]) << 8) | (u32(data[data.len - 2]) << 16) | (u32(data[data.len - 1]) << 24)
	mut sink := GunzipSink{
		out: []u8{cap: int(size)}
	}
	written := gzip.decompress_with_callback(data, deflate.ChunkCallback(gunzip_chunk),
		&sink)!
	if written != sink.out.len {
		return error('gzip stream reported ${written} bytes but delivered ${sink.out.len}')
	}
	return sink.out
}
