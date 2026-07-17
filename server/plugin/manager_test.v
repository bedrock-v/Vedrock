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

struct FakeView {}

fn (mut v FakeView) broadcast_message(text string) {}

fn (mut v FakeView) online_count() int {
	return 0
}

fn (mut v FakeView) player_names() []string {
	return []
}

fn (mut v FakeView) spawn_entity(name string, x f32, y f32, z f32) bool {
	return false
}

fn (mut v FakeView) entity_type_names() []string {
	return []
}

fn (mut v FakeView) set_block(name string, x int, y int, z int) bool {
	return false
}

fn (mut v FakeView) get_block(x int, y int, z int) int {
	return 0
}

fn (mut v FakeView) place_water(x int, y int, z int) {}

fn (mut v FakeView) capture_area(x1 int, y1 int, z1 int, x2 int, y2 int, z2 int) ?&arena.Snapshot {
	return none
}

fn (mut v FakeView) restore_area(snapshot &arena.Snapshot) {}

fn (mut v FakeView) register_generator(name string, factory fn (dim world.Dimension) world.Generator) {}

fn (mut v FakeView) generator_type_names() []string {
	return []
}

fn (mut v FakeView) register_custom_item(def item.CustomItemDefinition) int {
	return 0
}

fn (mut v FakeView) register_custom_block(def block.CustomBlockDefinition) int {
	return 0
}

fn (mut v FakeView) register_custom_entity(def entity.CustomEntityDefinition, factory fn () entity.Behaviour) bool {
	return false
}

fn (mut v FakeView) register_enchantment(e enchant.Enchantment) bool {
	return false
}

fn (mut v FakeView) next_enchantment_id() int {
	return enchant.custom_enchantment_id_start
}

fn (mut v FakeView) custom_item_names() []string {
	return []
}

fn (mut v FakeView) custom_block_names() []string {
	return []
}

fn (mut v FakeView) custom_entity_names() []string {
	return []
}

struct LoggingPlugin {
	Base
mut:
	enabled bool
}

fn (p &LoggingPlugin) meta() Meta {
	return Meta{
		name:    'Logging'
		version: '1.0.0'
	}
}

fn (mut p LoggingPlugin) on_enable(mut api Api) {
	p.log.info('enabled via embedded Base.log')
	p.enabled = true
}

fn (mut p LoggingPlugin) on_disable() {}

fn test_enable_all_wires_embedded_base_log_before_on_enable() {
	commands := &cmd.Registry{}
	events := &event.Bus{}
	sched := &scheduler.Scheduler{}
	log := logger.new(.info)
	mut m := new_manager(commands, events, sched, &FakeView{}, log)
	mut p := &LoggingPlugin{}
	m.register(p)
	m.enable_all()
	assert p.enabled
}
