module scoreboard

// max_lines is the number of lines the client renders under the title of a
// sidebar scoreboard. Anything past it is dropped by the client.
pub const max_lines = 15

// Scoreboard is the board drawn on the right side of a player's screen. Lines
// are held in display order, top to bottom, unless the board is set to sort
// descending.
pub struct Scoreboard {
	name string
mut:
	lines      []string
	padding    bool = true
	descending bool
}

// new returns an empty Scoreboard with the display name passed. Lines are
// added afterwards through write_line or set. Changing a Scoreboard after
// sending it does not update the board the player sees: it has to be sent
// again.
pub fn new(name string) &Scoreboard {
	return &Scoreboard{
		name: name
	}
}

// name returns the display name of the Scoreboard, drawn above its lines.
pub fn (board &Scoreboard) name() string {
	return board.name
}

// write_line appends a line of text to the bottom of the Scoreboard. It fails
// once the board holds max_lines lines.
pub fn (mut board Scoreboard) write_line(line string) ! {
	if board.lines.len >= max_lines {
		return error('write scoreboard: maximum of ${max_lines} lines of text exceeded')
	}
	board.lines << trim_newlines(line)
}

// write appends a block of text to the Scoreboard, splitting it into one line
// per newline. It fails once the board holds max_lines lines.
pub fn (mut board Scoreboard) write(text string) ! {
	for line in text.split('\n') {
		board.write_line(line)!
	}
}

// set replaces the line at index, padding the board with empty lines until
// that index exists. It fails if index falls outside the board.
pub fn (mut board Scoreboard) set(index int, line string) ! {
	if index < 0 || index >= max_lines {
		return error('set scoreboard line: index ${index} out of range')
	}
	for board.lines.len <= index {
		board.lines << ''
	}
	board.lines[index] = trim_newlines(line)
}

// remove deletes the line at index, moving the lines under it up. It fails if
// index holds no line.
pub fn (mut board Scoreboard) remove(index int) ! {
	if index < 0 || index >= board.lines.len {
		return error('remove scoreboard line: index ${index} out of range')
	}
	board.lines.delete(index)
}

// remove_padding drops the space added to either side of every line, which is
// otherwise used to keep the board as wide as its title.
pub fn (mut board Scoreboard) remove_padding() {
	board.padding = false
}

// descending returns whether the Scoreboard is sorted bottom to top.
pub fn (board &Scoreboard) descending() bool {
	return board.descending
}

// set_descending sorts the Scoreboard bottom to top, reversing the order its
// lines are drawn in.
pub fn (mut board Scoreboard) set_descending() {
	board.descending = true
}

// lines returns the lines of the Scoreboard as they should be drawn, with
// padding applied and the sort order honoured.
pub fn (board &Scoreboard) lines() []string {
	mut lines := board.lines.clone()
	if board.padding {
		for i, line in lines {
			fill := board.name.len - line.len - 2
			lines[i] = if fill <= 0 { ' ${line} ' } else { ' ${line}' + ' '.repeat(fill) }
		}
	}
	if board.descending {
		lines = lines.reverse()
	}
	return lines
}

fn trim_newlines(s string) string {
	return s.replace('\n', '')
}
