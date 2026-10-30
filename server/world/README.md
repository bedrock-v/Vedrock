## Description

`world` owns the mutable state of one world and hands it out through
transactions.

Each world runs a single thread. That thread is the only one that touches the
world's state and it reaches it through a `Tx` constructed on the thread itself.
Nothing else gets a live world: callers queue work with `submit`, `call` or
`call_ref` and wait for the actor to run it.

An entity's identity is a `Handle`, which holds the entity's state whether or not
a world holds the entity. A `Ref[T]` is the typed reference callers keep and it
follows the entity: work scheduled through it runs on whichever world holds the
entity when the work runs, not the one that held it when the reference was made.
A `Tx` is spent once its task is over and a `Handle` or a `Ref` is what outlives
one.

An `Entity` is anything with an `id() u64`. There is no entity package in the
rewrite yet. The `Zombie` below stands in for whatever ends up implementing it.

```v
import vedrock.server.world

struct Zombie {
	id_ u64
mut:
	health int
}

fn (z &Zombie) id() u64 {
	return z.id_
}

mut overworld := world.start('overworld')
h := world.new_handle(1, &Zombie{
	id_:    1
	health: 20
})

// Entities are added inside a transaction like every other change.
world.call[bool](mut overworld, 'spawn', fn [h] (mut tx world.Tx) !bool {
	tx.add(h)
	return true
})!

// Keep the reference, not the entity.
zombie := world.ref[Zombie](h)
health := world.call_ref[Zombie, int](zombie, 'hurt', fn (mut tx world.Tx, mut z &Zombie) !int {
	z.health -= 5
	return z.health
})!
println(health)

overworld.close()
```

A world also holds its chunks. A chunk the world has never had is filled by the
`Generator` it was started with and kept. Generation runs on worker threads, one
unless `chunk_workers` says otherwise, so a slow generator delays only the
chunks it is filling, never the world. A worker encodes what it generated and
everyone the chunk is sent to shares those bytes. The generator also says where
new players spawn.

What a player sees is a `Loader`: the chunks within a radius of where it is.
Moving it queues what came into view, nearest first, and stops viewing what
left it. `load` hands out what is ready and chunks are asked for nearest first
but go out in the order they are generated. A chunk the world has goes out at once.
One it doesn't is asked for and comes out of a later `load`, once a worker has
filled it. Several loaders asking for one chunk share one generation. A chunk
nobody views is dropped by a sweep every `chunk_unload_interval`, two minutes
unless configured.

```v
mut overworld := world.start('overworld', generator: world.NopGenerator{})
mut l := world.new_loader(8)
// Called every tick: what was generated since the last tick comes out here.
ready := world.call[[]world.LoadedChunk](mut overworld, 'view', fn [mut l] (mut tx world.Tx) ![]world.LoadedChunk {
	l.move(mut tx, 0.5, 0.5)
	return l.load(mut tx, 4)
})!
```

Work that has to happen once the current callback returns goes through
`Tx.defer`, which runs it on the same world in the order it was queued. Work on
*another* world goes through that world's own transaction: a transaction never
reaches into a world other than its own and queueing work for a world from
inside that world's own actor is refused.
