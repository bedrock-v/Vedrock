module plugin

import server.cmd
import server.event
import server.scheduler
import server.arena
import server.world
import server.item
import server.block
import server.entity
import server.enchant
import server.internal.logger

// ServerView is the narrow slice of the running server a plugin is allowed to
// poke. Hub satisfies it structurally, so the plugin package never imports the
// session package and no import cycle forms.
pub interface ServerView {
mut:
	broadcast_message(text string)
	online_count() int
	player_names() []string
	// spawn_entity spawns a registered entity type by name at a position,
	// returning false if the type is unknown.
	spawn_entity(name string, x f32, y f32, z f32) bool
	entity_type_names() []string
	// set_block sets a block by namespaced id in the default world and broadcasts
	// the change, returning false if the block name is unknown.
	set_block(name string, x int, y int, z int) bool
	// get_block returns the block network id at a position in the default world.
	get_block(x int, y int, z int) int
	// place_water sets a water source at the position and starts it spreading.
	place_water(x int, y int, z int)
	// capture_area snapshots the block ids over the box between the two corners,
	// or none if the region is too large. Restore it with restore_area.
	capture_area(x1 int, y1 int, z1 int, x2 int, y2 int, z2 int) ?&arena.Snapshot
	// restore_area writes a snapshot back so viewers see the arena reset.
	restore_area(snapshot &arena.Snapshot)
	// register_generator adds or overrides a named world generator: a plugin
	// can add a brand new one or replace a builtin by registering the same name.
	register_generator(name string, factory fn (dim world.Dimension) world.Generator)
	// generator_type_names lists every registered generator name.
	generator_type_names() []string
	// register_custom_item registers a data-driven item definition and returns
	// its allocated runtime id.
	register_custom_item(def item.CustomItemDefinition) int
	// register_custom_block registers a data-driven block definition and
	// returns its allocated runtime id.
	register_custom_block(def block.CustomBlockDefinition) int
	// register_custom_entity registers a custom entity type together with the
	// Behaviour factory used to spawn it, returning false if the id is taken.
	register_custom_entity(def entity.CustomEntityDefinition, factory entity.BehaviourFactory) bool
	// register_enchantment adds an enchantment, returning false if its id or
	// name is already taken.
	register_enchantment(e enchant.Enchantment) bool
	// next_enchantment_id returns the next free custom enchantment id.
	next_enchantment_id() int
	custom_item_names() []string
	custom_block_names() []string
	custom_entity_names() []string
}

// Api is the single handle handed to a plugin on enable. Everything a plugin can
// do to the server goes through here: register commands, register event
// listeners, reach the ServerView, or log.
@[heap]
pub struct Api {
mut:
	commands  &cmd.Registry        = unsafe { nil }
	events    &event.Bus           = unsafe { nil }
	scheduler &scheduler.Scheduler = unsafe { nil }
pub mut:
	server ServerView
	log    &logger.Logger = unsafe { nil }
}

// register_command adds a command to the shared registry, exactly like a
// built-in command.
pub fn (mut a Api) register_command(c cmd.Command) {
	a.commands.register(c)
}

// register_listener subscribes a Handler to the event Bus at the given
// priority.
pub fn (mut a Api) register_listener(h event.Handler, priority event.Priority) {
	a.events.register(h, priority)
}

// run_delayed schedules task to run once after delay server ticks (20 ticks = 1s).
pub fn (mut a Api) run_delayed(task scheduler.Task, delay i64) &scheduler.TaskHandler {
	return a.scheduler.run_delayed(task, delay)
}

// run_repeating schedules task to run every period ticks.
pub fn (mut a Api) run_repeating(task scheduler.Task, period i64) &scheduler.TaskHandler {
	return a.scheduler.run_repeating(task, period)
}

pub fn (mut a Api) register_generator(name string, factory fn (dim world.Dimension) world.Generator) {
	a.server.register_generator(name, factory)
}

// register_custom_item registers a data-driven item and returns its runtime id.
pub fn (mut a Api) register_custom_item(def item.CustomItemDefinition) int {
	return a.server.register_custom_item(def)
}

// register_custom_block registers a data-driven block and returns its runtime id.
pub fn (mut a Api) register_custom_block(def block.CustomBlockDefinition) int {
	return a.server.register_custom_block(def)
}

// register_custom_entity registers a custom entity type with its Behaviour
// factory, making it spawnable via /summon and spawn_entity.
pub fn (mut a Api) register_custom_entity(def entity.CustomEntityDefinition, factory entity.BehaviourFactory) bool {
	return a.server.register_custom_entity(def, factory)
}

// register_enchantment adds an enchantment to the shared registry.
pub fn (mut a Api) register_enchantment(e enchant.Enchantment) bool {
	return a.server.register_enchantment(e)
}

// next_enchantment_id returns the next free custom enchantment id.
pub fn (mut a Api) next_enchantment_id() int {
	return a.server.next_enchantment_id()
}
