module session

import bedrock_v.protocol.current as proto
import server.player.bossbar
import server.player

// bossbar_actor_id is the unique id the boss bar is attached to. The bar is
// bound to the player's own entity so it never depends on a boss entity being
// spawned, and reusing one id means re-sending a bar replaces the previous one.
fn (s &NetworkSession) bossbar_actor_id() proto.ActorUniqueID {
	return proto.ActorUniqueID{
		value: i64(s.runtime_id)
	}
}

// send_bossbar shows bar at the top of the player's screen, replacing whichever
// bar was shown before.
fn (mut s NetworkSession) send_bossbar(bar bossbar.BossBar) {
	s.remove_bossbar()
	s.deliver(&proto.BossEventPacket{
		target_actor_id: s.bossbar_actor_id()
		event_type:      .add
		name:            bar.text()
		health_percent:  bar.health_percentage()
		color:           bar.colour().u8()
	})
}

// remove_bossbar hides the boss bar currently shown to the player. It is a
// no-op on the client if no bar is up.
fn (mut s NetworkSession) remove_bossbar() {
	s.deliver(&proto.BossEventPacket{
		target_actor_id: s.bossbar_actor_id()
		event_type:      .remove
	})
}

fn (mut c ConsoleSender) send_bossbar(_ bossbar.BossBar) {
	// The console has no client to render a boss bar on.
}

fn (mut c ConsoleSender) remove_bossbar() {}
