module logger

import time
import term

pub enum Level {
	debug = 0
	info  = 1
	warn  = 2
	error = 3
}

pub struct Logger {
pub mut:
	min_level Level = .info
	prefix    string
	colored   bool = true
}

pub fn new(min_level Level) &Logger {
	return &Logger{
		min_level: min_level
		colored:   term.can_show_color_on_stdout()
	}
}

pub fn (l &Logger) with_prefix(prefix string) &Logger {
	return &Logger{
		min_level: l.min_level
		prefix:    prefix
		colored:   l.colored
	}
}

fn (l &Logger) log(level Level, msg string) {
	if int(level) < int(l.min_level) {
		return
	}
	stamp := time.now().format_ss()
	tag := level_tag(level)
	mut head := '[${stamp}] [${tag}]'
	if l.prefix != '' {
		head += ' [${l.prefix}]'
	}
	line := '${head} ${msg}'
	if l.colored {
		println(colorize(level, line))
	} else {
		println(line)
	}
}

fn level_tag(level Level) string {
	return match level {
		.debug { 'DEBUG' }
		.info { 'INFO' }
		.warn { 'WARN' }
		.error { 'ERROR' }
	}
}

fn colorize(level Level, line string) string {
	return match level {
		.debug { term.gray(line) }
		.info { term.bright_green(line) }
		.warn { term.yellow(line) }
		.error { term.bright_red(line) }
	}
}

pub fn (l &Logger) debug(msg string) {
	l.log(.debug, msg)
}

pub fn (l &Logger) info(msg string) {
	l.log(.info, msg)
}

pub fn (l &Logger) warn(msg string) {
	l.log(.warn, msg)
}

pub fn (l &Logger) error(msg string) {
	l.log(.error, msg)
}
