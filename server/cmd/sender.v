module cmd

import bedrock_v.protocol.types
import server.event
import server.form
import server.player
import server.player.bossbar
import server.player.scoreboard
import server.player.title

// Sender is the live connection that issued a cmd. Context carries read-only
// stats for building output; anything a Command needs to send back or mutate
// goes through Sender instead.
//
// It embeds event.CommandSource for the part that is only about identifying
// the sender and answering them which the console satisfies as readily as a
// player does. Everything else is declared here because it is a statement
// about running commands rather than about being a player: the player facing
// verbs are the tx-less entry points a command reaches from the session
// thread and the server facing ones (whitelist, difficulty, broadcast, world
// management) apply to the server, not to whoever happens to be the sender.
pub interface Sender {
	event.CommandSource
	has_permission(name string) bool
	whitelist_enabled() bool
	whitelist_names() []string
mut:
	// The player a command acts on. A ConsoleSender implements these as
	// noops: find_player never resolves to one, so nothing reaches them.
	set_gamemode(mode player.Gamemode)
	kill()
	disconnect(message string)
	position() types.Vector3
	teleport(x f32, y f32, z f32)
	clear_inventory()
	give_item(id string, count int) bool
	// give_experience awards points, and give_experience_levels whole levels.
	give_experience(points int)
	give_experience_levels(levels int)
	experience_level() int
	send_form(f form.Form) !
	send_scoreboard(board &scoreboard.Scoreboard)
	remove_scoreboard()
	send_title(t title.Title)
	send_bossbar(bar bossbar.BossBar)
	remove_bossbar()
	find_player(name string) ?Sender
	set_operator(value bool)
	// place_water and place_lava set a source of that fluid at the block
	// position and start its spread.
	place_water(x int, y int, z int)
	place_lava(x int, y int, z int)
	whitelist_add(name string)
	whitelist_remove(name string)
	whitelist_set_enabled(value bool)
	set_difficulty(value int)
	broadcast_message(text string)
	// show_title sends a title/subtitle/actionbar to this sender only.
	show_title(kind int, text string)
	// broadcast_title sends to every connected player (for /title @a).
	broadcast_title(kind int, text string)
	// world management. Mutating ops return an error the command relays to the
	// sender; list/info are read-only snapshots.
	world_names() []string
	world_info(name string) ?WorldSummary
	world_metrics(name string) ?WorldMetricsSummary
	// world_create's dimension and generator are names rather than the
	// world.Dimension/world.Generator types themselves, so the cmd layer never
	// depends on the world package directly.
	world_create(name string, dimension string, generator string) !
	world_load(name string) !
	world_delete(name string) !
	world_teleport(name string) !
}

// WorldSummary is a read-only snapshot of a loaded world, built for command
// output so the cmd layer never depends on the db types directly.
pub struct WorldSummary {
pub:
	name       string
	generator  string
	dimension  string
	overrides  int
	is_default bool
	players    int
}

// WorldMetricsSummary is a readonly snapshot of a world's runtime health.
// Plain values keep command and reporting code independent of session internals.
pub struct WorldMetricsSummary {
pub:
	name                           string
	current_tick                   i64
	requested_tick                 i64
	simulation_debt_ticks          i64
	queued_tasks                   int
	oldest_queued_task_age_ms      i64
	last_tick_duration_ms          i64
	longest_task_duration_ms       i64
	longest_task_name              string
	catchup_events                 i64
	tick_overruns                  i64
	scheduled_backlog              int
	liquid_backlog                 int
	entity_count                   int
	player_count                   i64
	outbound_overflow_count        i64
	outbound_peak_depth            i64
	persist_pending_count          int
	persist_oldest_pending_ms      i64
	persist_enqueued_total         i64
	persist_committed_total        i64
	persist_pressure_level         int
	persist_high_water_threshold   int
	persist_hard_ceiling_threshold int
	persist_last_write_ms          i64
	persist_longest_write_ms       i64
	persist_consecutive_errors     i64
	chunk_cached_count             int
	chunk_cached_bytes             i64
	chunk_cache_budget_bytes       i64
	chunk_inflight_count           int
	chunk_oldest_inflight_ms       i64
	chunk_active_workers           i64
	chunk_worker_limit             int
	chunk_queue_depth              i64
	chunk_requests_total           i64
	chunk_dedup_hits_total         i64
	actor_running                  bool
}
