## Description

`network` is how a client reaches this server: the NetherNet listener, the
packet layer of one client's connection and the login sequence that runs before
anything else.

A `Conn` is a `Wire` plus framing. The wire carries whole messages and knows
nothing of what they hold; `Conn` turns a message into the packets it carries
and hands them over one at a time because one message carries a batch and the
session handles each packet on its world before asking for the next.

NetherNet is the only transport. `NetherNetListener` binds the HTTP signalling
endpoint a client uses when it joins by address and hands out each connection
as a `Wire`. `Wire` and `Listener` are interfaces so the tests can stand in for
the network: over a list of messages and over a client that answers as it goes.

A `ListenerFn` builds a listener from the `Status` the server describes itself
with. `nethernet` returns one for a `NetherNetConfig`.

```v
import vedrock.server.network

mut listener := network.listen(network.NetherNetConfig{}, network.Status{ motd: 'Vedrock' })!
mut wire := listener.accept(500 * time.millisecond)!
mut conn := network.new_conn(mut wire)

identity := network.handshake(mut conn, network.LoginConfig{})!
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

The game's own encryption is not in the sequence at all. NetherNet runs over
DTLS, which already encrypts every byte, so the client skips it and so does the
server: Login is answered with PlayStatus with no handshake in between.

Everything a client sends before it has logged in is bounded: the message size,
the packet count per batch, the size of one packet, how far a batch may expand
while it is being decompressed, how many messages in a row may carry nothing
this server can decode and how many messages the login sequence itself will
read. A peer decides what it sends and without those it would also decide how
much work a read costs.
