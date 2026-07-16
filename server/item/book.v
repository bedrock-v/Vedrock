module item

const nbt_tag_end = u8(0)
const nbt_tag_byte = u8(1)
const nbt_tag_short = u8(2)
const nbt_tag_int = u8(3)
const nbt_tag_long = u8(4)
const nbt_tag_float = u8(5)
const nbt_tag_double = u8(6)
const nbt_tag_byte_array = u8(7)
const nbt_tag_string = u8(8)
const nbt_tag_list = u8(9)
const nbt_tag_compound = u8(10)
const nbt_tag_int_array = u8(11)
const nbt_tag_long_array = u8(12)

const book_pages_key = 'pages'
const book_page_text_key = 'text'
const book_title_key = 'title'
const book_author_key = 'author'
const book_generation_key = 'generation'

// max_book_pages and max_book_page_bytes bound what a client can push into a book's NBT.
pub const max_book_pages = 50
pub const max_book_page_bytes = 256

struct LeNbtWriter {
mut:
	data []u8
}

fn (mut w LeNbtWriter) u8(v u8) {
	w.data << v
}

fn (mut w LeNbtWriter) le_u16(v u16) {
	w.data << u8(v)
	w.data << u8(v >> 8)
}

fn (mut w LeNbtWriter) le_u32(v u32) {
	w.data << u8(v)
	w.data << u8(v >> 8)
	w.data << u8(v >> 16)
	w.data << u8(v >> 24)
}

fn (mut w LeNbtWriter) string(s string) {
	w.le_u16(u16(s.len))
	w.data << s.bytes()
}

fn (mut w LeNbtWriter) key(tag_id u8, name string) {
	w.u8(tag_id)
	w.string(name)
}

fn write_pages_field(mut w LeNbtWriter, pages []string) {
	w.key(nbt_tag_list, book_pages_key)
	w.u8(nbt_tag_compound) // list element type
	w.le_u32(u32(pages.len))
	for page in pages {
		w.key(nbt_tag_string, book_page_text_key)
		w.string(page)
		w.u8(nbt_tag_end) // close this page's compound
	}
}

fn start_item_extra_data(mut w LeNbtWriter) {
	w.le_u16(0xffff)
	w.u8(1)
}

fn end_item_extra_data(mut w LeNbtWriter) {
	w.le_u32(0)
	w.le_u32(0)
}

pub fn writable_book_nbt(pages []string) []u8 {
	if pages.len == 0 {
		return []u8{}
	}
	mut w := LeNbtWriter{}
	start_item_extra_data(mut w)
	w.u8(nbt_tag_compound) // root tag id
	w.le_u16(0) // root name (unnamed)
	write_pages_field(mut w, pages)
	w.u8(nbt_tag_end) // close root
	end_item_extra_data(mut w)
	return w.data
}

pub fn written_book_nbt(title string, author string, generation int, pages []string) []u8 {
	mut w := LeNbtWriter{}
	start_item_extra_data(mut w)
	w.u8(nbt_tag_compound)
	w.le_u16(0)
	write_pages_field(mut w, pages)
	w.key(nbt_tag_string, book_title_key)
	w.string(title)
	w.key(nbt_tag_string, book_author_key)
	w.string(author)
	w.key(nbt_tag_int, book_generation_key)
	w.le_u32(u32(generation))
	w.u8(nbt_tag_end)
	end_item_extra_data(mut w)
	return w.data
}

struct LeNbtReader {
	data []u8
mut:
	pos int
}

fn (mut r LeNbtReader) need(n int) ! {
	if n < 0 || r.pos + n > r.data.len {
		return error('book nbt: unexpected end of buffer at ${r.pos}')
	}
}

fn (mut r LeNbtReader) u8() !u8 {
	r.need(1)!
	b := r.data[r.pos]
	r.pos++
	return b
}

fn (mut r LeNbtReader) le_u16() !u16 {
	r.need(2)!
	v := u16(r.data[r.pos]) | (u16(r.data[r.pos + 1]) << 8)
	r.pos += 2
	return v
}

fn (mut r LeNbtReader) le_u32() !u32 {
	r.need(4)!
	v := u32(r.data[r.pos]) | (u32(r.data[r.pos + 1]) << 8) | (u32(r.data[r.pos + 2]) << 16) | (u32(r.data[
		r.pos + 3]) << 24)
	r.pos += 4
	return v
}

fn (mut r LeNbtReader) skip(n int) ! {
	r.need(n)!
	r.pos += n
}

fn (mut r LeNbtReader) string() !string {
	length := int(r.le_u16()!)
	r.need(length)!
	s := r.data[r.pos..r.pos + length].bytestr()
	r.pos += length
	return s
}

fn (mut r LeNbtReader) skip_payload(tag_id u8) ! {
	match tag_id {
		nbt_tag_byte {
			r.u8()!
		}
		nbt_tag_short {
			r.le_u16()!
		}
		nbt_tag_int, nbt_tag_float {
			r.le_u32()!
		}
		nbt_tag_long, nbt_tag_double {
			r.le_u32()!
			r.le_u32()!
		}
		nbt_tag_byte_array {
			n := int(r.le_u32()!)
			r.skip(n)!
		}
		nbt_tag_string {
			r.string()!
		}
		nbt_tag_list {
			element_id := r.u8()!
			count := int(r.le_u32()!)
			for _ in 0 .. count {
				r.skip_payload(element_id)!
			}
		}
		nbt_tag_compound {
			for {
				child_id := r.u8()!
				if child_id == nbt_tag_end {
					break
				}
				r.string()!
				r.skip_payload(child_id)!
			}
		}
		nbt_tag_int_array {
			n := int(r.le_u32()!)
			for _ in 0 .. n {
				r.le_u32()!
			}
		}
		nbt_tag_long_array {
			n := int(r.le_u32()!)
			for _ in 0 .. n {
				r.le_u32()!
				r.le_u32()!
			}
		}
		else {
			return error('book nbt: unknown tag id ${tag_id}')
		}
	}
}

fn (mut r LeNbtReader) read_pages_list() ![]string {
	element_id := r.u8()!
	count := int(r.le_u32()!)
	mut pages := []string{cap: count}
	for _ in 0 .. count {
		if element_id != nbt_tag_compound {
			return error('book nbt: unexpected pages element type ${element_id}')
		}
		mut text := ''
		for {
			field_id := r.u8()!
			if field_id == nbt_tag_end {
				break
			}
			field_key := r.string()!
			if field_id == nbt_tag_string && field_key == book_page_text_key {
				text = r.string()!
			} else {
				r.skip_payload(field_id)!
			}
		}
		pages << text
	}
	return pages
}

fn parse_book_pages(mut r LeNbtReader) ![]string {
	root_id := r.u8()!
	if root_id != nbt_tag_compound {
		return error('book nbt: root is not a compound')
	}
	r.string()! // root name, unused
	for {
		child_id := r.u8()!
		if child_id == nbt_tag_end {
			break
		}
		key := r.string()!
		if child_id == nbt_tag_list && key == book_pages_key {
			return r.read_pages_list()!
		}
		r.skip_payload(child_id)!
	}
	return []string{}
}

fn parse_item_extra_data(mut r LeNbtReader) ![]string {
	flag := r.le_u16()!
	if flag != 0xffff {
		// 0 = no NBT for this item; any other value would be malformed but
		// either way there are no pages to find.
		return []string{}
	}
	version := r.u8()!
	if version != 1 {
		return error('book nbt: unexpected item extra data version ${version}')
	}
	return parse_book_pages(mut r)!
}

pub fn book_pages_from_nbt(raw []u8) []string {
	if raw.len == 0 {
		return []string{}
	}
	mut r := LeNbtReader{
		data: raw
	}
	return parse_item_extra_data(mut r) or { []string{} }
}
