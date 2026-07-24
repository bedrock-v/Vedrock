module db

fn test_leveldb_factory_satisfies_factory() {
	f := LevelDBFactory{
		worlds_dir: 'worlds'
	}
	_ := Factory(f)
}
