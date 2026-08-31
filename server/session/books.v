module session

import bedrock_v.protocol.types
import server.item
import bedrock_v.protocol.current as proto

// Book edits are session local inventory work: item lookup uses shared
// readonly data, and mutation goes through Player's state lock.
fn (mut s NetworkSession) handle_book_edit(p proto.BookEditPacket) ! {
	s.apply_book_edit(p)
}

fn (mut s NetworkSession) apply_book_edit(p proto.BookEditPacket) {
	stack, net := s.inventory_stack_at(p.book_slot)
	if net == 0 {
		return
	}
	if s.hub.data.item_name(stack.id) != 'minecraft:writable_book' {
		return
	}

	mut pages := item.book_pages_from_nbt(stack.raw_extra_data)
	action := proto.book_edit_action(p.action)
	match action {
		proto.BookEditFinalize {
			s.sign_book(p.book_slot, stack, net, action.title, action.author)
			return
		}
		proto.BookEditReplacePage {
			if action.page_index < 0 || action.page_index >= item.max_book_pages {
				return
			}
			for pages.len <= action.page_index {
				pages << ''
			}
			pages[action.page_index] = truncate_page(action.text)
		}
		proto.BookEditAddPage {
			if action.page_index < 0 || action.page_index > pages.len
				|| action.page_index >= item.max_book_pages || pages.len >= item.max_book_pages {
				return
			}
			pages.insert(action.page_index, truncate_page(action.text))
		}
		proto.BookEditDeletePage {
			if action.page_index < 0 || action.page_index >= pages.len {
				return
			}
			pages.delete(action.page_index)
		}
		proto.BookEditSwapPages {
			if action.page_index_a < 0 || action.page_index_a >= pages.len
				|| action.page_index_b < 0 || action.page_index_b >= pages.len {
				return
			}
			pages[action.page_index_a], pages[action.page_index_b] = pages[action.page_index_b], pages[action.page_index_a]
		}
	}

	mut updated := stack
	updated.raw_extra_data = item.writable_book_nbt(pages)
	s.player.put_stack(net, updated)
	s.send_slot_update(p.book_slot, types.ItemStackWrapper{
		stack_id:   net
		item_stack: updated
	})
}

fn (mut s NetworkSession) sign_book(slot int, stack types.ItemStack, net int, title string, author string) {
	written_id := s.hub.data.item_id('minecraft:written_book')
	if written_id == 0 {
		return
	}
	pages := item.book_pages_from_nbt(stack.raw_extra_data)
	mut updated := stack
	updated.id = written_id
	updated.raw_extra_data = item.written_book_nbt(truncate_utf8(title, max_book_title_bytes), truncate_utf8(author,
		max_book_title_bytes), 0, pages)
	s.player.put_stack(net, updated)
	s.send_slot_update(slot, types.ItemStackWrapper{
		stack_id:   net
		item_stack: updated
	})
}

// max_book_title_bytes bounds the title and author a client may write when it
// signs a book. Both are unbounded strings on the wire.
const max_book_title_bytes = 64

fn truncate_page(text string) string {
	return truncate_utf8(text, item.max_book_page_bytes)
}

// truncate_utf8 cuts text down to at most limit bytes without splitting a
// UTF-8 sequence, so an oversized page or title never leaves half a character
// behind in the item's NBT.
fn truncate_utf8(text string, limit int) string {
	if text.len <= limit {
		return text
	}
	mut end := limit
	for end > 0 && text[end] & 0xc0 == 0x80 {
		end--
	}
	return text[..end]
}
