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

A `ListenerFn` builds a listener from the `ListenerContext` the server shares
with every listener: the `Status` it describes itself with, the media port's mux
and the player slots. `nethernet` and `lan` return one.

A `LoginHandler` takes one listener's connections through the login sequence and
hands out only the clients that finish it, as a `Client` holding the `Conn` and
the `Identity`. It works on any `Listener`. A transport only has to yield
wires.

```v
import time
import vedrock.server.network

mut ctx := &network.ListenerContext{
	status: network.Status{
		motd: 'Vedrock'
	}
}
listener := network.listen(network.NetherNetConfig{}, mut ctx)!
mut logins := network.LoginHandler.new(listener, mut ctx, network.LoginConfig{})
client := logins.accept(500 * time.millisecond)!
println('${client.identity.display_name} logged in')
// and once the client leaves:
ctx.free_slot()
```

A client takes a player slot when it arrives, before any login work. A full
server tells it so and closes it. Each login holds two threads.
`LoginConfig.max_concurrent` also bounds how many run at once per listener. A
client over it is closed before it takes a slot. The count is shared by every listener on the
context. A client that fails, runs past `LoginConfig.timeout` or is still logging
in when the handler closes gives its slot back. A client handed out keeps it and
whoever accepted the client frees it.

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
