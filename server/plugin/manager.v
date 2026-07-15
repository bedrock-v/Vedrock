module plugin

import server.cmd
import server.event
import server.scheduler
import server.internal.logger

// Manager owns the plugin lifecycle: register plugins at boot, enable them all
// once the server is wired, disable them all on shutdown. Loosely mirrors
// PocketMine's PluginManager, minus the disk loading a compiled server can't do.
@[heap]
pub struct Manager {
mut:
	plugins []Plugin
	api     &Api           = unsafe { nil }
	log     &logger.Logger = unsafe { nil }
}

// new_manager builds a Manager sharing the server's command registry, event bus
// and a ServerView. Plugins registered later enable against this same Api.
pub fn new_manager(commands &cmd.Registry, events &event.Bus, sched &scheduler.Scheduler, server ServerView, log &logger.Logger) &Manager {
	return &Manager{
		api: &Api{
			commands:  commands
			events:    events
			scheduler: sched
			server:    server
			log:       log
		}
		log: log
	}
}

// register queues a plugin. It is not enabled until enable_all runs.
pub fn (mut m Manager) register(p Plugin) {
	m.plugins << p
}

// count reports how many plugins are registered.
pub fn (m &Manager) count() int {
	return m.plugins.len
}

// enable_all enables every registered plugin in registration order, giving each
// a logger scoped to its name.
pub fn (mut m Manager) enable_all() {
	for mut p in m.plugins {
		info := p.meta()
		m.api.log = m.log.with_prefix(info.name)
		p.set_log(m.api.log)
		m.log.info('Enabling ${info.name} v${info.version}')
		p.on_enable(mut m.api)
	}
	m.log.info('${m.plugins.len} plugin(s) enabled, ${m.api.events.len()} listener(s) registered')
}

// disable_all disables every plugin in reverse order so later plugins tear down
// before the ones they may depend on.
pub fn (mut m Manager) disable_all() {
	for i := m.plugins.len - 1; i >= 0; i-- {
		mut p := m.plugins[i]
		p.on_disable()
		m.log.info('Disabled ${p.meta().name}')
	}
}
