module playerdb

// Provider stores player save data. FileProvider is the default local
// JSON backed implementation; embedders may supply another backend through
// HubOptions without changing session code.
pub interface Provider {
	// load returns NotSaved when this player has never been saved and any
	// other error when a save exists and could not be read. A caller that
	// can't tell those apart will reset players whose save is damaged.
	load(key string) !PlayerData
mut:
	save(key string, data PlayerData) !
}

// FileProvider wraps the existing load_player/save_player behavior.
pub struct FileProvider {
pub:
	dir string
}

pub fn (p FileProvider) load(key string) !PlayerData {
	return load_player(p.dir, key)!
}

pub fn (mut p FileProvider) save(key string, data PlayerData) ! {
	save_player(p.dir, key, data)!
}
