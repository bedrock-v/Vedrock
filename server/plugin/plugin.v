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

// Plugin is implemented by every plugin. on_enable runs once at startup with an
// Api handle for registering commands and listeners; on_disable runs at
// shutdown so a plugin can flush state. Embed Base for a ready logger and to
// avoid rewriting the boilerplate.
pub interface Plugin {
	meta() Meta
mut:
	on_enable(mut api Api)
	on_disable()
}

// Base is an embeddable helper carrying a scoped logger. A plugin embeds it,
// keeps its own Meta, and gets log for free. It does not implement the Plugin
// interface itself - the concrete plugin still defines meta/on_enable/on_disable.
pub struct Base {
pub mut:
	log &logger.Logger = unsafe { nil }
}
