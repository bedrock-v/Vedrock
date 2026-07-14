# Vedrock loadtest

A standalone load/stress-test harness for the Vedrock server. It opens many
concurrent RakNet connections against a running server, drives each one through
the real Bedrock handshake, holds them for a fixed duration, and reports
connection and throughput numbers you can line up against the server's own
tick/load logging.

It is a self-contained `module main` program - it does not touch the server
package, it only reuses two of its building blocks as a client:

- `raknet.dial_timeout` - the RakNet module's client dial API (outbound conn).
- `server.internal.network.Session` - the server's own framing/batch/compression
  transport, used from the client side so the wire format matches exactly.

## Run

From the repo root:

```sh
v run tools/loadtest/main.v <host> <port> <connections> <seconds> [--login]
```

Arguments (all optional, sane defaults shown):

- `host` - server address, default `127.0.0.1`
- `port` - server UDP port, default `19132`
- `connections` - concurrent clients to open, default `50`
- `seconds` - how long to hold the connections, default `10`
- `--login` - also push a Login packet after the handshake (see below)

Examples:

```sh
v run tools/loadtest/main.v                          # 50 conns, 10s, localhost
v run tools/loadtest/main.v 127.0.0.1 19132 200 15   # 200 conns, 15s
v run tools/loadtest/main.v 127.0.0.1 19132 100 5 --login
```

## What each connection does

1. Dials the server over UDP/RakNet (full offline-ping -> open-connection ->
   connected handshake, done by the RakNet dialer).
2. Sends `RequestNetworkSettings` uncompressed.
3. Waits for the server's `NetworkSettings` reply, then enables flate
   compression - matching the server's own state transition.
4. `--login` only: sends a `Login` packet with an offline/empty chain. The
   server does the real login-stage work and then rejects it at auth, which
   closes the connection. Use this to exercise the auth path; without it the
   connection stays parked at the login state.
5. Holds the connection open until the shared deadline, trickling a
   `PlayerAuthInput` movement packet every 500ms so the server keeps doing real
   per-connection read work.

Reaching `NetworkSettings` is the success boundary for a handshake - it proves
the server ran the version check and settings response for that client.

## What it measures

Printed at the end of the run:

- `wall clock` - actual run duration.
- `dial ok / fail` - RakNet connections established vs failed.
- `handshake ok / fail` - clients that reached the NetworkSettings stage.
- `login packets sent` - only with `--login`.
- `connections/sec` - established connections divided by wall clock. This is the
  accept-loop throughput as the load tool saw it.
- `keepalives sent` - total movement/keepalive packets pushed during the hold.
- `bytes sent (approx)` - approximate outbound bytes (packet sizes are estimated,
  not measured post-compression).
- `throughput` - approx KB/s outbound.
- `errors` - dial/transport failures.

## Reading the results

- `dial fail` > 0 means the server's RakNet accept loop is dropping or timing
  out open-connection requests - the accept path is saturated or the server is
  down. Ramp `connections` up until this starts climbing to find the accept
  ceiling.
- `handshake fail` with `dial ok` means connections land but the login/settings
  path stalls - the per-connection thread or the shared hub is the bottleneck,
  not RakNet.
- `connections/sec` falling as you raise `connections` shows where accept
  throughput flattens out.

## Interpreting server-side tick warnings during a run

Watch the server's stdout while the load runs. The server ticks at 20 TPS and,
when a tick runs past its 50ms slot, logs a throttled warning (once per ~5s):

```
Tick <n> over budget by <ms>ms (tps=<x>, load=<y>%)
```

- `load` is the fraction of each tick spent doing work (100% = a full tick's
  budget used). Rising `load` as you add connections is the signal that
  per-connection work is eating into the tick budget.
- `tps` dropping below 20 means ticks are overrunning and the loop is catching
  up - the server can no longer keep real time under this load.
- No warnings + `load` staying low means the server absorbed the connection
  count without tick-stability impact. Push `connections` higher until warnings
  appear to find the stability ceiling.

For memory, watch the server process RSS (e.g. `ps -o rss= -p <pid>` or a
`top`/`htop` on the server pid) across increasing `connections` to see
per-connection memory cost.

## Smoke run (captured on localhost)

Built the server (`v -o /tmp/vedrock_srv .`) and ran against it:

- 25 connections / 5s: 25/25 dial ok, 25/25 handshake ok, 250 keepalives,
  5.001s wall clock, 0 errors, 0 tick overruns.
- 100 connections / 4s: 100/100 dial ok, 100/100 handshake ok, 553 keepalives,
  0 errors, 0 tick overruns - the tick loop stayed stable at 20 TPS.

## Scope and limits

- This harness stops at the login/auth stage. It does not spawn a player, load
  chunks, or send gameplay packets, so it exercises the accept loop, RakNet
  reliability layer, handshake, framing/compression, and (with `--login`) the
  auth path - but not the full in-world tick cost of active players.
- Byte counts are approximate outbound estimates, not measured wire bytes.
- A full client harness would additionally need: a valid (or offline-signed)
  login chain accepted by auth, the resource-pack handshake responses, a
  `RequestChunkRadius`, and `SetLocalPlayerAsInitialized` to reach the spawned
  state and drive real gameplay load. That is out of scope here.
