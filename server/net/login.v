module net

import x.json2
import encoding.base64
import bedrock_v.protocol
import bedrock_v.protocol.packets
import bedrock_v.protocol.enums
import bedrock_v.protocol.types
import bedrock_v.protocol.serializer

// default_compression_threshold is the batch size from which messages are
// compressed. The client is told this number and uses it too.
pub const default_compression_threshold = 256

// Identity is who the client says it is.
//
// The login chain's signatures are not checked yet.
pub struct Identity {
pub:
	display_name       string
	xuid               string
	uuid               string
	xbox_authenticated bool
	// client_public_key is the key the client signed its chain with, in the form
	// the chain carries it in. The encryption handshake encrypts to it.
	client_public_key string
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
}

// handshake runs the server side of the login sequence and returns once the
// client is through it.
pub fn handshake(mut c Conn, cfg LoginConfig) !Identity {
	mut h := Handshake{
		conn:   c
		budget: cfg.max_login_messages
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
	conn         &Conn
	budget       int
	spent  		 int
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
				return error('client speaks protocol ${p.client_network_version}, server speaks ${protocol.protocol_id}')
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
			identity := read_identity(p.connection_request)!
			check_identity(identity)!
			// Everything after this goes out encrypted, including the status
			// below. The switch happens before the client is told it is in.
			if !h.conn.encrypted() {
				h.start_encryption(identity.client_public_key)!
			}
			h.conn.write(&packets.PlayStatusPacket{
				status: .login_success
			})!
			return identity
		}
	}
}

fn (mut h Handshake) start_encryption(client_public_key string) ! {
	if client_public_key == '' {
		return error('client sent no public key to encrypt to')
	}
	mut e := prepare_encryption(client_public_key)!
	h.conn.write(&packets.ServerToClientHandshakePacket{
		handshake_web_token: e.jwt
	})!
	h.conn.enable_encryption(mut e.cipher)
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

// read_identity reads the client's claimed identity out of the login request.
//
// The request holds a chain of JWTs. The last link carries the player's name
// and account ids under extraData and each link carries the key the next one
// is signed with. Signatures are not checked here. See Identity.
fn read_identity(connection_request []u8) !Identity {
	mut r := serializer.new_reader(connection_request)
	length := int(r.le_u32()!)
	chain_json := r.read_raw(length)!.bytestr()
	chain := chain_tokens(chain_json)!
	if chain.len == 0 {
		return error('login request carried no certificate chain')
	}
	mut extra := map[string]json2.Any{}
	mut client_key := ''
	for token in chain {
		payload := jwt_payload(token)!
		if 'identityPublicKey' in payload {
			client_key = field(payload, 'identityPublicKey')
		}
		if 'extraData' in payload {
			extra = (payload['extraData'] or { json2.Any('') }).as_map()
		}
	}
	return Identity{
		display_name:      field(extra, 'displayName')
		xuid:              field(extra, 'XUID')
		uuid:              field(extra, 'identity')
		client_public_key: client_key
	}
}

// chain_tokens pulls the chain out of the login request's JSON. The game has
// sent it both as a "chain" array and as a "Certificate" string holding that
// same object.
fn chain_tokens(chain_json string) ![]string {
	root := json2.decode[json2.Any](chain_json)!.as_map()
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
		return error('chain token is not a JWT')
	}
	// A JWT is base64url, which differs in the last two characters of the
	// alphabet and leaves the padding out.
	return json2.decode[json2.Any](base64.url_decode(parts[1]).bytestr())!.as_map()
}

fn field(values map[string]json2.Any, key string) string {
	return (values[key] or { return '' }).str()
}
