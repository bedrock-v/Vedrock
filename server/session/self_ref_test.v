module session

import time

// Verify that self_ref remains valid after the caller returns.
// The worker holds the only session reference while another thread
// forces GC cycles, covering the cross-thread lifetime requirement.
fn make_and_dispatch_self_ref(result chan u64) {
	mut s := &NetworkSession{
		runtime_id: 777
	}
	self := s.self_ref()
	worker := fn [self, result] () {
		time.sleep(300 * time.millisecond)
		result <- self.runtime_id()
	}
	spawn worker()
}

fn allocate_self_ref_test_gc_pressure(stop chan bool) {
	for {
		select {
			_ := <-stop {
				return
			}
			else {
				mut garbage := []&NetworkSession{}
				for i in 0 .. 20000 {
					garbage << &NetworkSession{
						runtime_id: u64(i)
					}
				}
				gc_collect()
				_ := garbage.len
			}
		}
	}
}

fn test_self_ref_pointer_survives_cross_thread_gc_pressure() {
	result := chan u64{cap: 1}
	make_and_dispatch_self_ref(result)

	stop := chan bool{cap: 1}
	spawn allocate_self_ref_test_gc_pressure(stop)

	got := <-result
	stop <- true
	time.sleep(50 * time.millisecond)

	assert got == 777
}
