module session

import protocol
import protocol.types
import server.item

// Book edits are session local inventory work: item lookup uses shared
// readonly data, and mutation goes through Player's state lock.
fn (mut s NetworkSession) handle_book_edit(p protocol.BookEditPacket) ! {
	s.apply_book_edit(p)
}

fn (mut s NetworkSession) apply_book_edit(p protocol.BookEditPacket) {
	stack, net := s.inventory_stack_at(p.inventory_slot)
	if net == 0 {
		return
	}
	if s.hub.data.item_name(stack.id) != 'minecraft:writable_book' {
		return
	}
	if p.type == protocol.book_edit_type_sign_book {
		s.sign_book(p.inventory_slot, stack, net, p.title, p.author)
		return
	}

	mut pages := item.book_pages_from_nbt(stack.raw_extra_data)
	match p.type {
		protocol.book_edit_type_replace_page {
			if p.page_number < 0 || p.page_number >= item.max_book_pages {
				return
			}
			for pages.len <= p.page_number {
				pages << ''
			}
			pages[p.page_number] = truncate_page(p.text)
		}
		protocol.book_edit_type_add_page {
			if p.page_number < 0 || p.page_number > pages.len
				|| p.page_number >= item.max_book_pages {
				return
			}
			pages.insert(p.page_number, truncate_page(p.text))
		}
		protocol.book_edit_type_delete_page {
			if p.page_number < 0 || p.page_number >= pages.len {
				return
			}
			pages.delete(p.page_number)
		}
		protocol.book_edit_type_swap_pages {
			if p.page_number < 0 || p.page_number >= pages.len || p.secondary_page_number < 0
				|| p.secondary_page_number >= pages.len {
				return
			}
			pages[p.page_number], pages[p.secondary_page_number] = pages[p.secondary_page_number], pages[p.page_number]
		}
		else {
			return
		}
	}

	mut updated := stack
	updated.raw_extra_data = item.writable_book_nbt(pages)
	s.player.put_stack(net, updated)
	s.send_slot_update(p.inventory_slot, types.ItemStackWrapper{
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
