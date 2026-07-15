# Vedrock Security Review

Independent security audit of the Vedrock Bedrock server, performed read-only against the
`feat/multiWorld` branch. Line references are as-read; note that three other agents are
concurrently hardening login/auth, network/DoS and robustness, so a few gaps flagged below may
already be closing. Where the code is genuinely fine, it is called out as such rather than padded.

## Executive summary

Overall posture: **not safe to expose to the public internet as-is.** The network/DoS layer is in
good shape - batch size caps, decompression-bomb rejection, per-connection rate limits and a
pre-login packet cap are all present and correct (`server/internal/network/*`). The problem is
higher up, in identity and trust:

- **There is no protocol encryption.** The login chain carries a `client_public_key` that the
  server parses and then throws away. The whole session runs in cleartext, so anyone on the path
  can read and inject packets.
- **The login chain-of-trust is not anchored to Mojang.** `verify_chain` decides "Xbox
  authenticated" from a field inside a token that the client itself signs. A crafted chain can set
  `xbox_authenticated = true` without any Mojang signature. Combined with the fact that op status,
  whitelist and player save files are all keyed off the client-supplied `displayName`, this lets an
  attacker impersonate any operator.
- **Offline mode + display-name-keyed persistence = path traversal.** When `xbox-auth` is off (or
  bypassed per above), the display name is fully attacker-controlled and is written straight into a
  filesystem path with no sanitisation.

Server-side authorization for commands is enforced correctly (permission is re-checked on execute,
not just on client visibility), and the world-delete path-traversal guard is solid. The core
gameplay-authorization gaps are combat (no reach/line-of-sight check) and a handful of client-trust
issues. Concurrency is mostly disciplined via the actor model, but there are real unguarded
cross-thread map/field reads.

Bottom line: fix the auth-chain trust anchor, add encryption, and sanitise the player-file key
before this faces untrusted clients.

## Findings (most severe first)

### 1. Critical - Auth - Forgeable Xbox-authentication / operator impersonation
`server/internal/auth/chain.v:69-102`, consumed at `server/session/login.v:36-51`

`verify_chain` walks the JWT chain but never anchors the root of trust to Mojang's public key. The
first token is verified against the `x5u` header of the *same token* (`chain.v:70-79`), i.e. it is
self-signed and self-validating. The `xbox_authenticated` flag is then derived at `chain.v:86` from
`next_key == mojang_public_key`, where `next_key` is the `identityPublicKey` field *inside* the
client-supplied first token. Nothing forces that first token to actually be signed by Mojang.

Exploit: an attacker builds a one-token chain, signs it with their own ECDSA key, puts that key in
the `x5u` header (so `verify_jwt` passes), and sets `payload.identityPublicKey` to the hard-coded
`mojang_public_key` string. `authenticated` becomes `true`, `extraData.displayName/XUID` are
whatever they choose. With `xbox-auth: true` the server still accepts them as Xbox-authenticated.
Because ops (`server/permission/ops.v`), whitelist and player files are all keyed by `displayName`,
they log in as any operator (e.g. name themselves after a known op) and gain full `/op`, `/deop`,
`/world delete`, etc.

Fix: pin the trust root. The first chain token must be verified against the known Mojang root key
(the chain is Mojang-key -> intermediate -> client), not against its own `x5u`. Only set
`xbox_authenticated` when the signature actually chains up to Mojang, and validate token expiry
(`nbf`/`exp`) while you are there. The existing `mojang_public_key` const should be the *verifying*
key of token 0, not a value you compare a client field against.

### 2. Critical - Persistence - Path traversal via unsanitised player key
`server/player/playerdb/player.v:25-41`, key from `server/session/spawn.v:12-20`

`player_path` interpolates the key straight into `os.join_path(dir, '${key}.json')` with no
validation. `player_key()` returns `xuid`, else `uuid`, else `display_name`. In offline mode (or
after finding 1), `display_name` is attacker-controlled. A name like `../../ops` or
`../../whitelist` causes `save_player`/`load_player` to read and write outside `players/`.

Exploit: connect offline with a crafted name, trigger a save (`save_player_data` on quit,
`items.v:118-140`), and clobber an arbitrary `*.json` on disk with player JSON, or read one back on
join. Even without traversal, a name with `/` creates junk directories, and a name colliding with
another player's file corrupts their data.

Fix: never use a free-form display name as a filesystem key. Prefer the XUID/UUID only, reject empty,
and sanitise to a strict charset (or hash the key). Reuse the pattern already applied in
`server/world/db/manage.v:11-29` (`safe_world_dir`) which correctly rejects `/`, `\`, `..`, `.`,
absolute paths and post-normalisation escapes.

### 3. High - Transport - No protocol encryption negotiated
`server/session/login.v:36-56`, `server/internal/network/session.v`

Bedrock supports ECDH-negotiated AES encryption after login using the client public key. Vedrock
parses `client_public_key` (`chain.v`) but never initiates a `ServerToClientHandshakePacket` /
enables a cipher. Compression is toggled (`login.v:32`) but the stream is otherwise plaintext for the
entire session.

Impact: any on-path attacker (shared LAN, malicious router, ISP) can read chat, credentials-adjacent
identity data, and inject or modify packets - including forging commands from an authenticated
session. This also removes the only cryptographic binding between the login identity and subsequent
packets, compounding finding 1.

Fix: implement Bedrock's login encryption handshake (ECDH over the client public key, AES-GCM/CTR per
protocol) and require it before entering `.play`.

### 4. High - Identity - Op/whitelist/identity keyed on spoofable display name
`server/session/login.v:42-49`, `server/permission/ops.v:32-34`, `server/permission/whitelist.v`

Even independent of the chain-forgery bug, authorization is tied to `identity.display_name`:
`whitelist.is_allowed(display_name)` (`login.v:42`), `ops.is_op(display_name)` (`login.v:48`), and
grants via `player_grants.apply(... display_name, xuid, uuid)` (`login.v:49`). Display names are not
unique or authenticated (they are chosen client-side in offline mode and only weakly bound even with
Xbox). Two accounts can share a name; an offline player picks any name.

Impact: whitelist and op lists are trivially bypassed/impersonated whenever Xbox auth is off or
bypassed. Op is granted purely on a name match.

Fix: key ops, whitelist and grants on XUID (authenticated identity), not display name. Treat display
name as a cosmetic label only.

### 5. High - Combat - No reach or line-of-sight check on attack
`server/session/combat.v:46-72`, dispatched from `server/session/blocks.v:48-55`

`handle_attack` takes the client-supplied `target_entity_runtime_id` and applies damage with no
distance check between attacker and victim, and no validation that the target is actually a valid,
visible entity in range. Block *placement* is correctly reach-limited
(`blocks.v:147-152 within_place_reach`), but combat is not.

Exploit: a modified client sends `InventoryTransaction` use-item-on-entity attacks against any
runtime id from anywhere on the map (reach hack / kill-aura / cross-world kill), bounded only by the
client's own send rate. Weapon damage is taken from the client-supplied held item
(`combat.v:50`, see finding 9), so damage per hit is also attacker-influenced.

Fix: reject attacks where the victim is outside a server-side reach bound (mirror `within_place_reach`
using both players' server positions) and where attacker/victim are in different worlds. Rate-limit
attacks server-side.

### 6. Medium - Concurrency - Unguarded cross-thread reads of shared maps/fields
`server/session/hub.v` (ops/whitelist), `server/session/blocks.v:217-244`, `server/session/whitelist_admin.v:41-63`

The actor model is followed for writes, but several reads happen on the connection thread while the
actor thread mutates the same state:

- `ops.is_op(...)` and `whitelist.is_allowed(...)` are read at login on the connection thread
  (`login.v:42,48`) while `SetOpJob`/`WhitelistAddJob` mutate the same maps on the actor thread
  (`moderation.v:14-26`, `whitelist_admin.v:7-33`). V maps are not safe for concurrent
  read/write - this is a data race that can corrupt the map or crash.
- `whitelist_enabled()`/`whitelist_names()` (`whitelist_admin.v:41-63`) read `h.whitelist` directly
  off the caller thread.
- `obstructed_by_entity` (`blocks.v:225-244`) reads every other session's `target.position` without
  taking that session's `pos_mutex`, while those sessions write it under `pos_mutex`
  (`session.v:199-203`). Same for `add_player`/broadcast paths reading `position`/`display_name`.

Impact: intermittent crashes or corrupted permission state under concurrent login + `/op` or
`/whitelist` traffic; torn position reads. Hard to exploit deterministically but a real stability and
correctness bug that a connection flood makes more likely.

Fix: route ops/whitelist reads through the Hub mutex (or the actor), or make these structures
internally mutex-guarded. For position, read cross-session positions via a locked accessor
(`current_position()` exists but is not used in `obstructed_by_entity`).

### 7. Medium - DoS - Unbounded WorldJob submission can stall the actor / block threads
`server/session/hub.v:31,397-408`; e.g. `combat.v:65`, `blocks.v`, `moderation.v`

`jobs` is a channel with `cap: 256` and `submit()` blocks when full (`hub.v:397-399`). Every
client action that mutates cross-session state submits a job (attack, respawn, teleport, give,
clear, world ops). A client that spams attacks/respawns (no server-side rate limit on those - see
finding 5) can flood the queue. Because `submit` blocks, connection threads back up behind a full
queue, and `tick_loop` also submits a `TickJob` every tick (`server.v:249`) - if the actor is
saturated, ticks stall for everyone.

Impact: one or a few malicious clients degrade or freeze the whole server (global DoS) even though
the per-connection byte/packet limits are respected, because a single small packet can enqueue
expensive cross-session work.

Fix: rate-limit the gameplay actions that enqueue jobs (per-session token bucket), and/or make
`submit` non-blocking with a drop/tail policy for non-critical jobs so a full queue cannot stall the
tick loop.

### 8. Medium - Input - `handle_mob_equipment` trusts client-declared held item
`server/session/inventory.v:61-70`

`handle_mob_equipment` sets `s.held_item`/`s.held_slot` directly from the packet and broadcasts it,
without checking the client actually holds that item in the claimed slot. `weapon_damage` in combat
reads the held item id (`combat.v:50`) to compute damage.

Impact: a client can claim to hold a netherite sword it does not own to maximise attack damage, or
spoof equipment appearance to other players. Bounded (damage tiers are small) but it is unvalidated
client trust in the combat path.

Fix: derive the held item from the server-side inventory model at `held_slot`, not from the packet;
validate the slot index.

### 9. Low - Input - Command name case-sensitivity mismatch in disable/unregister
`server/cmd/command.v:49-73`, `server/server.v:124-127`

`register` stores commands under `cmd.name()` verbatim, but `unregister` lower-cases the key
(`command.v:59`) and `resolve` lower-cases lookups (`command.v:76`). If any command name contains an
uppercase letter, `disabled_commands` in `permissions.yml` (applied via `unregister` at
`server.v:124`) silently fails to remove it, so an admin who disables a command may still have it
live. Current built-ins are all lowercase, so it is latent.

Fix: normalise to lower-case in `register` too, so registry keys and lookups agree.

### 10. Low - DoS - Pre-login work bounded by count, not by total bytes over time
`server/internal/network/session.v:85-90`

The pre-login cap counts packets (`max_prelogin_packets = 64`) and the rate limiter caps bytes/sec,
which is good. But a single login packet may carry a large `auth_info_json` that is JSON-decoded and
has ECDSA signatures verified (`chain.v`), and the 64-packet budget still allows a fair amount of
crypto work per connection before disconnect. Combined with unlimited concurrent `accept`s
(`server.v:263-269` spawns a thread per connection with no cap on concurrent handshakes), a
connection flood can drive CPU via signature verification and per-connection thread/goroutine
allocation.

Impact: pre-auth CPU/thread exhaustion under a connection flood.

Fix: cap the size of `auth_info_json` and the chain length before verifying, and bound the number of
concurrent un-authenticated handshakes (a semaphore around `spawn s.handle`).

## Things that are actually fine

- **World deletion path traversal**: `safe_world_dir` (`server/world/db/manage.v:11-29`) is a
  correct, defence-in-depth guard - rejects `/`, `\`, `..`, `.`, absolute paths, and re-checks that
  the normalised path still sits directly under `worlds_dir`. `delete_world` also refuses the default
  world and worlds with players, and closes the LevelDB handle first (`hub.v:257-276`). Good.
- **Command authorization is server-side**: `dispatch` re-checks `visible()` (permission) before
  `execute` (`command.v:101-104,120`); it does not rely on client-side command visibility. Privileged
  commands (`/op`, `/world`, `/gamemode`, `/whitelist`, `/kill`, `/tp`) all declare a permission node
  gated behind op default. A normal player cannot invoke them.
- **Network frame bounds**: `decode_batch` caps compressed batch, decompressed batch (bomb guard),
  per-packet size and packet count (`server/internal/network/batch.v:15-18,44-91`); `check_rate`
  enforces per-connection packet/byte ceilings (`session.v:59-74`). This layer is well done.
- **Block placement** is reach- and bounds-checked and cooldown-throttled (`blocks.v:85-104`).
- **Plugin surface** (`server/plugin/*`) is in-tree and compiled, not loaded from disk, so there is no
  untrusted-plugin loading vector. `ServerView` is a deliberately narrow interface. Fine as long as
  only trusted plugins are wired in `register_plugins`.

## Quick wins

- Sanitise/replace the player-file key (finding 2) - reuse `safe_world_dir`'s validation or hash the
  key. Small, self-contained change with high payoff.
- Lower-case command keys in `register` (finding 9).
- Route `ops.is_op`/`whitelist.is_allowed` reads through the Hub mutex (finding 6) - a few lines.
- Cap `auth_info_json` size and chain length before crypto (finding 10).
- Add a server-side reach check in `handle_attack` mirroring `within_place_reach` (finding 5).

## Must-fix before public production

1. **Anchor the login chain to Mojang's key and validate expiry** (finding 1). Until this is fixed,
   `xbox_authenticated` is meaningless and any operator can be impersonated.
2. **Key ops/whitelist/grants and player files on authenticated XUID, not display name**
   (findings 2, 4).
3. **Negotiate protocol encryption** (finding 3). Cleartext sessions on a hostile network defeat all
   of the above.
4. **Rate-limit gameplay actions that enqueue WorldJobs and bound concurrent handshakes**
   (findings 5, 7, 10) so a single client cannot stall the tick loop or exhaust CPU.
