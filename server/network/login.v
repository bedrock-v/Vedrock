module network

import time
import x.json2
import crypto.ecdsa
import crypto.md5
import encoding.base64
import encoding.hex
import rand
import bedrock_v.nethernet as nn
import bedrock_v.protocol
import bedrock_v.protocol.packets
import bedrock_v.protocol.enums
import bedrock_v.protocol.types
import bedrock_v.protocol.serializer

// default_compression_threshold is the batch size from which messages are
// compressed. The client is told this number and uses it too.
pub const default_compression_threshold = 256

// Identity is who the client is. xbox_authenticated is true only when it comes
// from a login token a LoginVerifier verified on a connection that proved it
// holds the key the token names. A verified token on a connection that proved no
// key still names the player but it could have been replayed from another
// server the player joined. Without a verifier the client could have put
// anything here.
pub struct Identity {
pub:
	display_name       string
	xuid               string
	uuid               string
	xbox_authenticated bool
}

// LoginConfig is what the login sequence needs to know from the server.
pub struct LoginConfig {
pub:
	compression_threshold int = default_compression_threshold
	// packs_required refuses a client that will not accept the server's
	// resource packs.
	packs_required bool
	// max_login_messages bounds what a client that has not logged in can make
	// the server do. The sequence itself is a handful of messages.
	max_login_messages int = 64
	// timeout is how long a client has from arriving to finishing the whole
	// sequence, resource packs included. It is one deadline and nothing the
	// client sends extends it. Zero means no deadline.
	timeout time.Duration = 30 * time.second
	// allow_unverified lets clients in on a login nothing verified for offline
	// servers and tests.
	allow_unverified bool
	max_concurrent int = 64
}

// VersionMismatch is a client refused for speaking another protocol version. It
// has been told so with a PlayStatus already and anything sent after that can
// replace the client's "outdated" screen with a generic one.
pub struct VersionMismatch {
	Error
pub:
	client i32
}

pub fn (e VersionMismatch) msg() string {
	return 'client speaks protocol ${e.client}, server speaks ${protocol.protocol_id}'
}

// handshake runs the server side of the login sequence and returns once the
// client is through it. The login is verified by verifier which can be left out
// only when cfg allows unverified logins.
pub fn handshake(mut c Conn, cfg LoginConfig, verifier ?LoginVerifier) !Identity {
	if verifier == none && !cfg.allow_unverified {
		return error('logins have to be verified and there is no verifier')
	}
	mut h := Handshake{
		conn:     c
		budget:   cfg.max_login_messages
		verifier: verifier
	}
	h.network_settings(cfg)!
	identity := h.login()!
	h.resource_packs(cfg)!
	return identity
}

// Handshake is the login sequence in progress. It holds the connection and what
// is left of the client's packet budget.
struct Handshake {
mut:
	conn     &Conn
	budget   int
	spent    int
	verifier ?LoginVerifier
}

// read takes the next packet and refuses a client that keeps sending without
// finishing the sequence.
fn (mut h Handshake) read() !protocol.Packet {
	if h.spent >= h.budget {
		return error('client sent ${h.spent} messages without finishing the login sequence')
	}
	before := h.conn.reads()
	p := h.conn.read()!
	after := h.conn.reads()
	h.spent += if after > before { after - before } else { 1 }
	return p
}

// network_settings answers the client's first packet and turns compression on.
fn (mut h Handshake) network_settings(cfg LoginConfig) ! {
	for {
		p := h.read()!
		if p is packets.RequestNetworkSettingsPacket {
			if p.client_network_version != i32(protocol.protocol_id) {
				status := if p.client_network_version < i32(protocol.protocol_id) {
					enums.PlayStatus.login_failed_client_old
				} else {
					enums.PlayStatus.login_failed_server_old
				}
				h.conn.write(&packets.PlayStatusPacket{
					status: status
				})!
				return VersionMismatch{
					client: p.client_network_version
				}
			}
			h.conn.write(&packets.NetworkSettingsPacket{
				compression_threshold: u16(cfg.compression_threshold)
				compression_algorithm: .z_lib
			})!
			h.conn.enable_compression(cfg.compression_threshold)
			return
		}
	}
}

// login reads who the client claims to be and accepts it.
fn (mut h Handshake) login() !Identity {
	for {
		p := h.read()!
		if p is packets.LoginPacket {
			identity := read_identity(p.connection_request, h.verifier, h.conn.public_key())!
			check_identity(identity)!
			h.conn.write(&packets.PlayStatusPacket{
				status: .login_success
			})!
			return identity
		}
	}
}

// resource_packs negotiates the packs the client has to have. This server
// serves none yet. The exchange is the empty list and the stack the client
// acknowledges.
fn (mut h Handshake) resource_packs(cfg LoginConfig) ! {
	h.conn.write(&packets.ResourcePacksInfoPacket{
		resource_pack_required: cfg.packs_required
	})!
	for {
		p := h.read()!
		if p is packets.ResourcePackClientResponsePacket {
			match p.response {
				packets.ResourcePackResponseCancel {
					if cfg.packs_required {
						return error('client refused resource packs it has to accept')
					}
					h.send_stack(cfg)!
				}
				packets.ResourcePackResponseDownloading {
					// Nothing to send. The server serves no packs.
				}
				packets.ResourcePackResponseDownloadingFinished {
					h.send_stack(cfg)!
				}
				packets.ResourcePackResponseStackFinished {
					return
				}
			}
		}
	}
}

// send_stack tells the client which packs to apply and in what order.
fn (mut h Handshake) send_stack(cfg LoginConfig) ! {
	h.conn.write(&packets.ResourcePackStackPacket{
		texture_pack_required: cfg.packs_required
		base_game_version:     types.BaseGameVersion{
			value: protocol.minecraft_version
		}
	})!
}

// disconnect tells the client why it is being dropped and closes it. A client
// dropped without being told shows "unable to connect to world" instead.
pub fn disconnect(mut c Conn, message string) {
	c.write(&packets.DisconnectPacket{
		reason:  .kicked
		message: packets.DisconnectMessage{
			kick_message: message
		}
	}) or {}
	c.close()
}

// How long an identity field may be. display_name is the gamertag limit. The
// other two are bounded to keep an absurd value from a client out of whatever is
// keyed off them.
const max_display_name = 32
const max_xuid = 32
const max_uuid = 64

// check_identity refuses an identity the rest of the server should not see. The
// client picks these strings and they end up in logs, in messages and in
// anything keyed by player.
fn check_identity(identity Identity) ! {
	name := identity.display_name
	if name.len == 0 || name.len > max_display_name {
		return error('display name of ${name.len} characters is out of range')
	}
	for ch in name {
		if !(ch.is_alnum() || ch == ` ` || ch == `_`) {
			return error('display name holds a character that is not allowed')
		}
	}
	if identity.xuid.len > max_xuid {
		return error('xuid of ${identity.xuid.len} characters is too long')
	}
	if identity.uuid.len > max_uuid {
		return error('uuid of ${identity.uuid.len} characters is too long')
	}
}

// read_identity reads who the client is out of the login request.
//
// A current client sends one token from Microsoft under "Token". With a
// verifier, the identity comes only from the claims it verified, and a request
// with no token is refused: the older chain of JWTs isn't verified here. Without
// one the token's claims are read as they are or the chain's when there is no
// token.
//
// A connection that proved a key while it was opened has to log in with a
// token naming that key. A token captured from another connection names
// another key and is refused. Only such a bound login can be
// xbox_authenticated.
fn read_identity(connection_request []u8, verifier ?LoginVerifier, proven ?ecdsa.PublicKey) !Identity {
	mut r := serializer.new_reader(connection_request)
	length := int(r.le_u32()!)
	request := json2.decode[json2.Any](r.read_raw(length)!.bytestr())!.as_map()
	token := field(request, 'Token')
	mut claims := map[string]json2.Any{}
	mut verified := false
	if mut v := verifier {
		if token == '' {
			return error('login request carries no token to verify')
		}
		claims = v.verify(token)!
		verified = true
	} else if token != '' {
		claims = jwt_payload(token)!
	} else {
		return chain_identity(request)!
	}
	mut bound := false
	if key := proven {
		named := nn.claim_public_key(token, false) or {
			return error('login token names no usable key: ${err}')
		}
		if !key.equal(named) {
			return error('login token names another key than the one this connection proved')
		}
		bound = true
	}
	return token_identity(claims, verified && bound)
}

// chain_identity reads the player out of the older chain of JWTs whose last
// link carries it under extraData.
fn chain_identity(request map[string]json2.Any) !Identity {
	chain := chain_tokens(request)!
	if chain.len == 0 {
		return error('login request carried neither a token nor a certificate chain')
	}
	mut extra := map[string]json2.Any{}
	for link in chain {
		payload := jwt_payload(link)!
		if 'extraData' in payload {
			extra = (payload['extraData'] or { json2.Any('') }).as_map()
		}
	}
	xuid := field(extra, 'XUID')
	return Identity{
		display_name: field(extra, 'displayName')
		xuid:         xuid
		uuid:         token_uuid(field(extra, 'identity'), xuid)
	}
}

// token_identity reads the player out of a token's claims: the gamertag under
// xname and the XUID under xid. proven says whether the token was verified and
// bound to the connection.
fn token_identity(claims map[string]json2.Any, proven bool) Identity {
	xuid := field(claims, 'xid')
	return Identity{
		display_name:       field(claims, 'xname')
		xuid:               xuid
		uuid:               token_uuid(field(claims, 'leguuid'), xuid)
		xbox_authenticated: proven && xuid != ''
	}
}

// token_uuid is the player's UUID.
fn token_uuid(claimed string, xuid string) string {
	if claimed != '' {
		return claimed
	}
	if xuid == '' {
		return rand.uuid_v4()
	}
	mut id := md5.sum('pocket-auth-1-xuid:${xuid}'.bytes())
	id[6] = (id[6] & 0x0f) | 0x30
	id[8] = (id[8] & 0x3f) | 0x80
	h := hex.encode(id)
	return '${h[..8]}-${h[8..12]}-${h[12..16]}-${h[16..20]}-${h[20..]}'
}

// chain_tokens pulls the chain out of the login request's JSON. The game has
// sent it both as a "chain" array and as a "Certificate" string holding that
// same object.
fn chain_tokens(root map[string]json2.Any) ![]string {
	if 'chain' in root {
		return strings_of(root['chain'] or { json2.Any('') })
	}
	if 'Certificate' in root {
		raw := (root['Certificate'] or { json2.Any('') }).str()
		if raw != '' {
			certificate := json2.decode[json2.Any](raw)!.as_map()
			if 'chain' in certificate {
				return strings_of(certificate['chain'] or { json2.Any('') })
			}
		}
	}
	return []string{}
}

fn strings_of(value json2.Any) []string {
	mut out := []string{}
	for entry in value.as_array() {
		out << entry.str()
	}
	return out
}

// jwt_payload decodes a JWT's claims without verifying its signature.
fn jwt_payload(token string) !map[string]json2.Any {
	parts := token.split('.')
	if parts.len != 3 {
		return error('login token is not a JWT')
	}
	return json2.decode[json2.Any](base64.url_decode(parts[1]).bytestr())!.as_map()
}

fn field(values map[string]json2.Any, key string) string {
	return (values[key] or { return '' }).str()
}
