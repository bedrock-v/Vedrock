## Description

`net` is the packet layer of one client's connection: the batch framing over a
transport and the login sequence that runs before anything else.

A `Conn` is a `Wire` plus framing. The wire carries whole messages and knows
nothing of what they hold; `Conn` turns a message into the packets it carries
and hands them over one at a time because one message carries a batch and the
session handles each packet on its world before asking for the next.

`Wire` and `Listener` are interfaces, so this package has no transport in it.
`transport/nethernet` implements both over NetherNet and the tests implement
them over a list of messages and over a client that answers as it goes.

A server holds several listeners and cannot tell them apart. It never names a
transport either: a `ListenerFn` builds one from a `Status` and a `Config`
carries those functions and gaining a transport changes nothing above this
line.

```v
import vedrock.server.net
import vedrock.server.transport.nethernet

mut listener := nethernet.listen(nethernet.Config{}, net.Status{ motd: 'Vedrock' })!
mut wire := listener.accept(500 * time.millisecond)!
mut conn := net.new_conn(mut wire)

identity := net.handshake(mut conn, net.LoginConfig{})!
println('${identity.display_name} logged in from ${conn.remote()}')
```

`handshake` runs the server side of the login sequence: network settings,
compression, the login itself and resource pack negotiation. It returns the
identity the client claims. A client that gets through it is waiting for
`StartGame`, which needs game data the caller owns and is sent from there.

One thing the sequence deliberately does not do is **verify the login chain**.
The chain's signatures are not checked. `Identity.xbox_authenticated` is false
for every login and the name is self-declared. Until verification exists, a
caller must not treat the name or the account ids as proof of who the player is.

Encryption is not in that company. A transport that encrypts every byte on its own
says so through `Wire.encrypted`, and NetherNet does, running over DTLS. When a
transport does not, the login sequence runs the game's own handshake: ECDH on
P-384 against the client's key, a key derived from a random salt and AES-256-CTR
with a per-message SHA-256 checksum in place of the auth tag the game does not
send. The token telling the client the salt goes out in the clear and everything
after it is enciphered, in both directions, in order.

Everything a client sends before it has logged in is bounded: the message size,
the packet count per batch, the size of one packet, how far a batch may expand
while it is being decompressed, how many messages in a row may carry nothing
this server can decode and how many messages the login sequence itself will
read. A peer decides what it sends and without those it would also decide how
much work a read costs.
