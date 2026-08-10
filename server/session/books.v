module session

import protocol.version.v924.packets as packets_924
import protocol.version.v924.enums as enums_924
import protocol.types
import server.item

// Book edits are session local inventory work: item lookup uses shared
// readonly data, and mutation goes through Player's state lock.
fn (mut s NetworkSession) handle_book_edit(p packets_924.BookEditPacket) ! {
	s.apply_book_edit(p)
}

fn (mut s NetworkSession) apply_book_edit(p packets_924.BookEditPacket) {
	stack, net := s.inventory_stack_at(p.book_slot)
	if net == 0 {
		return
	}
	if s.hub.data.item_name(stack.id) != 'minecraft:writable_book' {
		return
	}

	mut pages := item.book_pages_from_nbt(stack.raw_extra_data)
	match p.action {
		enums_924.BookEditFinalize {
			s.sign_book(p.book_slot, stack, net, p.action.title, p.action.author)
			return
		}
		enums_924.BookEditReplacePage {
			if p.action.page_index < 0 || p.action.page_index >= item.max_book_pages {
				return
			}
			for pages.len <= p.action.page_index {
				pages << ''
			}
			pages[p.action.page_index] = truncate_page(p.action.text)
		}
		enums_924.BookEditAddPage {
			if p.action.page_index < 0 || p.action.page_index > pages.len
				|| p.action.page_index >= item.max_book_pages {
				return
			}
			pages.insert(int(p.action.page_index), truncate_page(p.action.text))
		}
		enums_924.BookEditDeletePage {
			if p.action.page_index < 0 || p.action.page_index >= pages.len {
				return
			}
			pages.delete(p.action.page_index)
		}
		enums_924.BookEditSwapPages {
			if p.action.page_index_a < 0 || p.action.page_index_a >= pages.len
				|| p.action.page_index_b < 0 || p.action.page_index_b >= pages.len {
				return
			}
			pages[p.action.page_index_a], pages[p.action.page_index_b] = pages[p.action.page_index_b], pages[p.action.page_index_a]
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
	updated.raw_extra_data = item.written_book_nbt(truncate_page(title), truncate_page(author), 0,
		pages)
	s.player.put_stack(net, updated)
	s.send_slot_update(slot, types.ItemStackWrapper{
		stack_id:   net
		item_stack: updated
	})
}

fn truncate_page(text string) string {
	if text.len <= item.max_book_page_bytes {
		return text
	}
	return text[..item.max_book_page_bytes]
}
