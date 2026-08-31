module scoreboard

fn test_lines_are_padded_to_the_title_width() {
	mut board := new('Vedrock')
	board.write_line('hi')!
	assert board.lines() == [' hi   ']
}

fn test_remove_padding_keeps_lines_untouched() {
	mut board := new('Vedrock')
	board.write_line('hi')!
	board.remove_padding()
	assert board.lines() == ['hi']
}

fn test_write_splits_on_newlines() {
	mut board := new('x')
	board.remove_padding()
	board.write('a\nb')!
	assert board.lines() == ['a', 'b']
}

fn test_write_line_fails_past_the_line_limit() {
	mut board := new('x')
	for _ in 0 .. max_lines {
		board.write_line('a')!
	}
	board.write_line('overflow') or { return }
	assert false, 'expected the 16th line to be rejected'
}

fn test_set_fills_the_gap_with_empty_lines() {
	mut board := new('x')
	board.remove_padding()
	board.set(2, 'c')!
	assert board.lines() == ['', '', 'c']
}

fn test_set_rejects_an_index_outside_the_board() {
	mut board := new('x')
	board.set(max_lines, 'a') or { return }
	assert false, 'expected an out of range index to be rejected'
}

fn test_remove_moves_the_lines_below_up() {
	mut board := new('x')
	board.remove_padding()
	board.write('a\nb\nc')!
	board.remove(1)!
	assert board.lines() == ['a', 'c']
}

fn test_descending_reverses_the_drawn_order() {
	mut board := new('x')
	board.remove_padding()
	board.write('a\nb')!
	board.set_descending()
	assert board.descending()
	assert board.lines() == ['b', 'a']
}
