module plugin

import server.internal.logger

// Meta is the static identity of a plugin. Inspired by PocketMine's
// PluginDescription but kept to what a compiled, in-tree plugin needs.
pub struct Meta {
pub:
	name    string
	version string
	authors []string
}

// Plugin is implemented by every plugin. on_enable runs once at
// startup with an Api handle for registering commands and listeners;
// on_disable runs at shutdown so a plugin can flush state.
pub interface Plugin {
	meta() Meta
mut:
	set_log(l &logger.Logger)
	on_enable(mut api Api)
	on_disable()
}

// Base is an embeddable helper carrying a scoped logger. A plugin embeds it,
// keeps its own Meta, and gets log for free. Manager calls set_log before
// on_enable, so log is never the zero value nil by the time a plugin can
// observe it. It does not implement the rest of the Plugin interface itself -
// the concrete plugin still defines meta/on_enable/on_disable.
pub struct Base {
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn (mut b Base) set_log(l &logger.Logger) {
	b.log = l
}
