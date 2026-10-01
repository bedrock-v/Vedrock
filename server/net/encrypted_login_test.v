module net

import encoding.base64
import x.json2
import bedrock_v.protocol
import bedrock_v.protocol.packets
import bedrock_v.protocol.serializer

// FakeClient is a client on a transport that does not encrypt, which is the case
// the game's own encryption exists for.
struct FakeClient {
mut:
	keys        &ServerKeyPair
	step        int
	compression bool
	cipher      &Cipher = unsafe { nil }
	// omit_key leaves the public key out of the login chain which is a client
	// the server can't encrypt to.
	omit_key bool
	// received is what the server sent, decrypted and decoded.
	received []protocol.Packet
}

fn new_fake_client() &FakeClient {
	return &FakeClient{
		keys: new_server_key_pair() or { panic(err) }
	}
}

fn (mut c FakeClient) public_key() string {
	return base64.encode(c.keys.public_key_der() or { panic(err) })
}

fn (mut c FakeClient) read_message() ![]u8 {
	step := c.step
	c.step++
	if step == 0 {
		return c.send([protocol.Packet(&packets.RequestNetworkSettingsPacket{
			client_network_version: i32(protocol.protocol_id)
		})])!
	}
	if step == 1 {
		return c.send([protocol.Packet(&packets.LoginPacket{
			client_network_version: i32(protocol.protocol_id)
			connection_request:     c.connection_request()
		})])!
	}
	if step == 2 {
		return c.send([protocol.Packet(&packets.ClientToServerHandshakePacket{})])!
	}
	if step == 3 {
		return c.send([protocol.Packet(&packets.ResourcePackClientResponsePacket{
			response: packets.ResourcePackResponseDownloadingFinished{}
		})])!
	}
	if step == 4 {
		return c.send([protocol.Packet(&packets.ResourcePackClientResponsePacket{
			response: packets.ResourcePackResponseStackFinished{}
		})])!
	}
	return error('the client has nothing left to send')
}

// send frames packets the way the client has to by now. It compresses once it
// has the network settings and encrypts once it has the token.
fn (mut c FakeClient) send(ps []protocol.Packet) ![]u8 {
	mut encoded := [][]u8{}
	for p in ps {
		encoded << protocol.encode_packet_to_bytes(p)
	}
	batch := encode_batch(encoded, c.compression, default_compression_threshold)!
	if c.cipher != unsafe { nil } {
		return c.cipher.encrypt(batch)
	}
	return batch
}

fn (mut c FakeClient) write_message(b []u8) ! {
	message := if c.cipher != unsafe { nil } { c.cipher.decrypt(b)! } else { b }
	batch := decode_batch(message, c.compression)!
	pool := protocol.new_pool()
	for raw in batch {
		mut r := serializer.new_reader(raw)
		p := pool.decode(mut r)!
		c.received << p
		if p is packets.NetworkSettingsPacket {
			c.compression = true
		}
		if p is packets.ServerToClientHandshakePacket {
			c.install_cipher(p.handshake_web_token)!
		}
	}
}

fn (mut c FakeClient) install_cipher(token string) ! {
	parts := token.split('.')
	if parts.len != 3 {
		return error('the handshake token is not a JWT')
	}
	header := json2.decode[json2.Any](base64.url_decode(parts[0]).bytestr())!.as_map()
	payload := json2.decode[json2.Any](base64.url_decode(parts[1]).bytestr())!.as_map()
	server_public := (header['x5u'] or { json2.Any('') }).str()
	salt := base64.url_decode((payload['salt'] or { json2.Any('') }).str())
	if salt.len == 0 {
		return error('the handshake token carries no salt')
	}
	secret := c.keys.derive_shared_secret(server_public)!
	c.cipher = new_cipher(derive_key(salt, secret))!
}

fn (mut c FakeClient) connection_request() []u8 {
	extra := json2.Any({
		'displayName': json2.Any('Scher')
		'XUID':        json2.Any('2535000000000000')
		'identity':    json2.Any('00000000-0000-0000-0000-000000000001')
	})
	claims := json2.encode({
		'extraData':         extra
		'identityPublicKey': json2.Any(if c.omit_key { '' } else { c.public_key() })
	})
	token := '${base64.url_encode('{"alg":"ES384"}'.bytes())}.${base64.url_encode(claims.bytes())}.signature'
	chain := json2.encode({
		'chain': json2.Any([json2.Any(token)])
	})
	mut w := serializer.new_writer()
	w.le_u32(u32(chain.len))
	w.write_raw(chain.bytes())
	return w.bytes()
}

fn (mut c FakeClient) remote() string {
	return 'fake'
}

fn (mut c FakeClient) encrypted() bool {
	return false
}

fn (mut c FakeClient) close() {}

fn test_a_login_over_a_cleartext_transport_is_encrypted() {
	mut client := new_fake_client()
	mut conn := new_conn(mut client)
	identity := handshake(mut conn, LoginConfig{}) or { panic(err) }

	assert identity.display_name == 'Scher'
	assert conn.encrypting(), 'the session is in the clear on a transport that does not encrypt'

	mut names := []string{}
	for p in client.received {
		names << p.name()
	}
	assert names == ['NetworkSettingsPacket', 'ServerToClientHandshakePacket', 'PlayStatusPacket',
		'ResourcePacksInfoPacket', 'ResourcePackStackPacket']
}

fn test_a_login_without_a_client_key_is_refused() {
	mut client := new_fake_client()
	client.omit_key = true
	mut conn := new_conn(mut client)
	if _ := handshake(mut conn, LoginConfig{}) {
		assert false, 'a client that cannot be encrypted to logged in anyway'
	}
	assert !conn.encrypting()
}
