module session

pub interface WorldJob {
	run(mut h Hub)
}
