module cmd

import server.player

// Sender is the live connection that issued a cmd. Context carries
// read-only stats for building output; anything a Command needs to send
// back or mutate goes through Sender instead. Embeds player.View for the
// part that's genuinely about a specific player (identity, messaging,
// movement, inventory, UI, etc.) and adds only what's actually about running
// commands: whitelist/difficulty/broadcast/world management apply to the
// server, not to whichever player happens to be the sender.
pub interface Sender {
	player.View
	whitelist_enabled() bool
	whitelist_names() []string
mut:
	find_player(name string) ?Sender
	set_operator(value bool)
	// place_water sets a water source at the block position and starts its spread.
	place_water(x int, y int, z int)
	whitelist_add(name string)
	whitelist_remove(name string)
	whitelist_set_enabled(value bool)
	set_difficulty(value int)
	// Scoreboard state is the server's, not any one player's, so it lives
	// here rather than on player.View.
	scoreboard_objectives() []ObjectiveInfo
	scoreboard_add_objective(name string, display_name string) bool
	scoreboard_remove_objective(name string) bool
	// scoreboard_set_display shows an objective in a slot; an empty objective
	// name clears the slot. It reports false for an unknown slot or objective.
	scoreboard_set_display(slot string, objective string) bool
	scoreboard_set_score(objective string, entry string, value int) bool
	scoreboard_add_score(objective string, entry string, delta int) ?int
	scoreboard_reset_score(entry string)
	scoreboard_teams() []TeamInfo
	scoreboard_add_team(name string, display_name string) bool
	scoreboard_remove_team(name string) bool
	scoreboard_team_join(team string, entry string) bool
	scoreboard_team_leave(entry string) bool
	// scoreboard_team_option sets one of a team's settings by name, reporting
	// false for an unknown team, option or value.
	scoreboard_team_option(team string, option string, value string) bool
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

// ObjectiveInfo is a read-only view of one scoreboard objective, so the cmd
// layer never depends on the scoreboard types directly.
pub struct ObjectiveInfo {
pub:
	name         string
	display_name string
}

// TeamInfo is the same for a team, with how many entries are in it.
pub struct TeamInfo {
pub:
	name         string
	display_name string
	members      int
}
