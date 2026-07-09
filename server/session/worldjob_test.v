module session

import server.internal.gamedata
import server.internal.auth
import time

struct TestOnlyDamageJob {
	victim_runtime_id u64
	amount            f32
}

fn (j TestOnlyDamageJob) run(mut h Hub) {
	mut victim := h.session_by_runtime(j.victim_runtime_id) or { return }
	victim.health -= j.amount
}

fn damage_worker(hub &Hub, victim_runtime_id u64, amount f32, times int) {
	mut mut_hub := unsafe { hub }
	for _ in 0 .. times {
		mut_hub.submit(TestOnlyDamageJob{
			victim_runtime_id: victim_runtime_id
			amount:            amount
		})
	}
}

fn test_concurrent_damage_jobs_serialize_without_lost_updates() {
	mut hub := new_hub(gamedata.GameData{})
	victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Victim'
		}
		runtime_id: 1
		health:     1000.0
	}
	hub.add(victim)

	attackers := 50
	hits_per_attacker := 10
	amount := f32(1.0)

	mut threads := []thread{}
	for _ in 0 .. attackers {
		threads << spawn damage_worker(hub, u64(1), amount, hits_per_attacker)
	}
	threads.wait()

	// submit() only enqueues; run_jobs() drains the channel on its own thread
	// so the victim's health settles asynchronously. Poll instead of assuming it's already applied once every submitter has returned.
	expected := f32(1000.0) - f32(attackers * hits_per_attacker) * amount
	deadline := time.now().add(5 * time.second)
	for time.now() < deadline && victim.health != expected {
		time.sleep(5 * time.millisecond)
	}
	assert victim.health == expected
}
