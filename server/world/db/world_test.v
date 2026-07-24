module db

fn test_world_store_satisfies_provider() {
	mut store := &WorldStore{
		db:        unsafe { nil }
		overrides: unsafe { nil }
	}
	_ := Provider(store)
}
