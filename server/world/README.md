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

Work that has to happen once the current callback returns goes through
`Tx.defer`, which runs it on the same world in the order it was queued. Work on
*another* world goes through that world's own transaction: a transaction never
reaches into a world other than its own and queueing work for a world from
inside that world's own actor is refused.
