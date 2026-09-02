module resourcepack

import os
import compress.szip

// content_key_length is the size of the AES key Bedrock uses for pack content
// encryption. The client reads it as ASCII, not as raw key bytes.
pub const content_key_length = 32

// key_file_suffix names the file a local pack's content key is read from:
// "my_pack.mcpack" is keyed by "my_pack.mcpack.key".
pub const key_file_suffix = '.key'

// contents_header is the magic word at offset 4 of an encrypted pack's
// contents.json. An unencrypted pack either has no contents.json at all or a
// plain json one, so the magic is what separates the two.
const contents_header = [u8(0xfc), 0xb9, 0xcf, 0x9b]

const contents_entry = 'contents.json'

// has_content_key reports whether a key file exists beside the pack file.
pub fn has_content_key(pack_path string) bool {
	return os.is_file(pack_path + key_file_suffix)
}

// read_content_key returns the content key stored beside the pack file. A key
// file that exists but does not hold a usable key is an error rather than an
// empty key: serving an encrypted pack without its key leaves the client with
// assets it cannot read, and it cannot tell the server about it.
pub fn read_content_key(pack_path string) !string {
	path := pack_path + key_file_suffix
	key := os.read_file(path)!.trim_space()
	if key.len != content_key_length {
		return error('content key in ${path} is ${key.len} characters, expected ${content_key_length}')
	}
	return key
}

// is_encrypted reports whether the pack file at path carries encrypted content.
pub fn is_encrypted(pack_path string) bool {
	mut z := szip.open(pack_path, .no_compression, .read_only) or { return false }
	defer {
		z.close()
	}
	total := z.total() or { return false }
	for i in 0 .. total {
		z.open_entry_by_index(i) or { return false }
		name := z.name()
		if name != contents_entry && !name.ends_with('/' + contents_entry) {
			z.close_entry()
			continue
		}
		size := int(z.size())
		if size < contents_header.len * 2 {
			z.close_entry()
			return false
		}
		mut buf := []u8{len: size}
		z.read_entry_buf(buf.data, size) or {
			z.close_entry()
			return false
		}
		z.close_entry()
		return buf[4..8] == contents_header
	}
	return false
}
