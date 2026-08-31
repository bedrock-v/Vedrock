module logger

import sync
import time
import term

pub enum Level {
	debug = 0
	info  = 1
	warn  = 2
	error = 3
}

@[heap]
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
	// A logger is optional wherever it is held as a reference, so a caller that
	// never had one to pass writes nothing instead of taking the process down.
	if isnil(l) {
		return
	}
	if int(level) < int(l.min_level) {
		return
	}
	stamp := timestamp()
	tag := level_tag(level)
	origin := if l.prefix != '' { l.prefix } else { thread_name() }
	if l.colored {
		head := term.gray('[${stamp}]') + ' ' + term.cyan('[${origin}]') +
			' ${colorize(level, '[${tag}]')}'
		body := match level {
			.debug { term.gray(msg) }
			.warn { term.yellow(msg) }
			.error { term.bright_red(msg) }
			else { msg }
		}

		println('${head} ${body}')
	} else {
		println('[${stamp}] [${origin}] [${tag}] ${msg}')
	}
}

// main_thread is whichever thread first built a Logger, which is the one
// running main(). Every other thread is reported by its registered name, or by
// its own id when it never registered one, so concurrent output stays
// attributable either way.
const main_thread = sync.thread_id()

// ThreadNames maps thread ids to the names their threads registered. Reads
// happen on every log line and writes only twice per thread, so the lock is a
// read/write one.
struct ThreadNames {
mut:
	lock_ &sync.RwMutex = sync.new_rwmutex()
	names map[u64]string
}

const thread_names = &ThreadNames{}

// name_thread labels the calling thread for every log line it writes from here
// on. Call it as the first statement of a spawned thread, paired with a
// deferred unname_thread: thread ids are reused once a thread exits, so a name
// left behind would be inherited by an unrelated thread later.
pub fn name_thread(name string) {
	mut reg := unsafe { &ThreadNames(thread_names) }
	reg.lock_.lock()
	unsafe {
		reg.names[sync.thread_id()] = name
	}
	reg.lock_.unlock()
}

// unname_thread drops the calling thread's registered name.
pub fn unname_thread() {
	mut reg := unsafe { &ThreadNames(thread_names) }
	reg.lock_.lock()
	unsafe {
		reg.names.delete(sync.thread_id())
	}
	reg.lock_.unlock()
}

fn thread_name() string {
	id := sync.thread_id()
	if id == main_thread {
		return 'Main Thread'
	}
	mut reg := thread_names
	reg.lock_.rlock()
	name := reg.names[id] or { '' }
	reg.lock_.runlock()
	return if name != '' { name } else { 'Thread-${id}' }
}

// The date is deliberately left out: a server log is read live, so only the
// time of day carries information.
fn timestamp() string {
	now := time.now()
	return '${now.hour:02d}:${now.minute:02d}:${now.second:02d}'
}

fn level_tag(level Level) string {
	return match level {
		.debug { 'DEBUG' }
		.info { 'INFO' }
		.warn { 'WARN' }
		.error { 'ERROR' }
	}
}

fn colorize(level Level, text string) string {
	return match level {
		.debug { term.gray(text) }
		.info { term.bright_green(text) }
		.warn { term.bright_yellow(text) }
		.error { term.bright_red(text) }
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
