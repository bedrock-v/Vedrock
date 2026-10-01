## Description

`nethernet` is one of the transports a client reaches this server over: a
NetherNet listener and the connections it accepts. It implements `net.Listener`
and `net.Wire` and is reached only through those.

It carries whole messages and nothing above them. What a message holds is
`net`'s business, and the dependency runs one way: this package names `net`'s
two interfaces, and `net` names no transport at all, the packet layer and its
tests build with no transport compiled in.

```v
import vedrock.server
import vedrock.server.transport.nethernet

mut srv := server.new(
	listeners: [nethernet.listener(nethernet.Config{ port: 19132 })]
	motd:      'Vedrock'
)!
srv.run()
```
