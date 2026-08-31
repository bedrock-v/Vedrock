module session

import server.internal.auth
import server.internal.logger
import server.internal.encryption
import server.resourcepack
import bedrock_v.protocol.serializer
import bedrock_v.protocol.current as proto

fn login_chain_json(connection_request []u8) !string {
	mut r := serializer.new_reader(connection_request)
	auth_len := int(r.le_u32()!)
	return r.read_raw(auth_len)!.bytestr()
}

fn (mut s NetworkSession) handle_request_network_settings(p proto.RequestNetworkSettingsPacket) ! {
	client_protocol := p.client_network_version
	s.log.debug('Client requested network settings (protocol ${client_protocol})')
	if client_protocol != proto.selected_protocol {
		status := if client_protocol < proto.selected_protocol {
			proto.PlayStatus.login_failed_client_old
		} else {
			proto.PlayStatus.login_failed_server_old
		}
		s.log.warn('Rejected client with protocol ${client_protocol} (server requires ${proto.selected_protocol})')
		s.transport.send(&proto.PlayStatusPacket{
			status: status
		})!
		s.reject_bootstrap('Incompatible client version. Server requires ${proto.selected_minecraft_version}.')
		return
	}
	s.transport.send(&proto.NetworkSettingsPacket{
		compression_threshold:     u16(s.cfg.compression_threshold)
		compression_algorithm:     proto.PacketCompressionAlgorithm.z_lib
		client_throttle_enabled:   false
		client_throttle_threshold: 0
		client_throttle_scalar:    0.0
	})!
	s.transport.enable_compression(s.cfg.compression_threshold)
	s.state = .login
}

// Identity field bounds. display_name is the vanilla gamertag limit; xuid/uuid
// are bounded to reject absurd values from a hostile or offline client.
const max_display_name = 32
const max_xuid_len = 32
const max_uuid_len = 64

fn (mut s NetworkSession) handle_login(p proto.LoginPacket) ! {
	auth_info_json := login_chain_json(p.connection_request) or {
		s.log.warn('Malformed login connection request: ${err}')
		s.reject_bootstrap('Login failed: malformed connection request')
		return
	}
	claimed := auth.parse_login_chain(auth_info_json, s.cfg.xbox_auth, mut s.hub.oidc_verifier) or {
		s.log.warn('Authentication failed: ${err}')
		s.reject_bootstrap('Login failed: ${err}')
		return
	}
	// parse_login_chain verifies the JWT chain signatures, but with xbox_auth
	// off the display_name/xuid/uuid come from a self-signed offline chain and
	// are NOT proof of identity - only trustworthy when identity.xbox_authenticated.
	// Validate the fields regardless so downstream code (whitelist, ops, grants,
	// data files keyed by these strings) never sees empty or oversized input.
	s.validate_identity(claimed) or {
		s.log.warn('Rejected login from ${s.transport.remote_addr()}: ${err}')
		s.reject_bootstrap('Login failed: invalid identity')
		return
	}
	identity := trusted_identity(claimed)
	if !s.hub.whitelist_allowed(identity.display_name) {
		s.log.info('${identity.display_name} is not white-listed, rejecting login')
		s.reject_bootstrap('You are not white-listed on this server!')
		return
	}
	if s.cfg.max_players > 0 && s.hub.admission_count() >= s.cfg.max_players {
		s.log.info('${identity.display_name} rejected: server is full')
		s.reject_bootstrap('The server is full!')
		return
	}
	// Reserve the identity before resourcepack negotiation. Sessions are not
	// visible in Hub.sessions until client initialization, so pending logins
	// need their own name guard.
	if !s.hub.reserve_player_name(identity.display_name) {
		s.log.info('${identity.display_name} is already connected, rejecting duplicate login')
		s.reject_bootstrap('You are already connected to this server!')
		return
	}
	s.player.identity = identity
	s.transport.mark_logged_in()
	s.player.perm.set_op(s.hub.is_op(identity.display_name))
	// xuid/uuid grants (player_permissions.yml's "xuid:"/"uuid:" lines) are only
	// meaningful for a verified account. trusted_identity has already cleared
	// both for an unverified chain, so an offline login can never match another
	// player's xuid/uuid-keyed grants.
	s.hub.player_grants.apply(mut s.player.perm, identity.display_name, identity.xuid,
		identity.uuid)
	mode := if identity.xbox_authenticated { 'Xbox Live' } else { 'offline' }
	logger.name_thread(identity.display_name)
	s.log.debug('${identity.display_name} authenticated [${mode}] xuid=${identity.xuid} uuid=${identity.uuid}')
	// Negotiate protocol encryption before login_success so the rest of the
	// session runs ciphered. Skipped when the transport already encrypts every
	// byte (NetherNet's DTLS), and gated behind the encryption config flag. If
	// the client sent no public key, or the handshake fails, we fall back to
	// cleartext rather than dropping the player.
	if s.cfg.encryption && !s.transport.disable_encryption() {
		s.start_encryption(identity.client_public_key) or {
			s.log.warn('Encryption handshake skipped for ${identity.display_name}: ${err}')
		}
	}
	s.transport.send(&proto.PlayStatusPacket{
		status: proto.PlayStatus.login_success
	})!
	s.start_resource_packs()!
}

// start_encryption runs the server side of the Bedrock encryption handshake:
// derive the key from the client public key, send the signed
// ServerToClientHandshake in cleartext, then switch the transport to encrypted.
// The client replies with an (encrypted) ClientToServerHandshake, handled as a
// confirmation. Does nothing if the client provided no public key.
fn (mut s NetworkSession) start_encryption(client_public_key string) ! {
	if client_public_key == '' {
		return error('client provided no public key')
	}
	result := encryption.prepare_handshake(client_public_key)!
	mut ctx := encryption.new_context(result.key)!
	// Must be flushed in cleartext before the cipher is installed.
	s.transport.send(&proto.ServerToClientHandshakePacket{
		handshake_web_token: result.handshake_jwt
	})!
	s.transport.enable_encryption(mut ctx)
	s.encryption_enabled = true
	s.log.debug('Encryption enabled for ${s.player.identity.display_name}')
}

fn (mut s NetworkSession) handle_client_to_server_handshake(_ proto.ClientToServerHandshakePacket) ! {
	if !s.encryption_enabled {
		s.log.debug('Unexpected ClientToServerHandshake without an active cipher')
		return
	}
	s.log.debug('Client confirmed encryption handshake')
}

// validate_identity rejects empty, oversized, or malformed identity fields
// before they reach the whitelist, permission grants, or on-disk player data.
fn (s &NetworkSession) validate_identity(identity auth.Identity) ! {
	name := identity.display_name
	if name.len == 0 || name.len > max_display_name {
		return error('display_name length ${name.len} out of range')
	}
	// Bedrock gamertags are alphanumerics and spaces. Reject control chars and
	// path/format-hostile characters that could poison logs or data-file paths.
	for c in name {
		if !(c.is_alnum() || c == ` ` || c == `_`) {
			return error('display_name contains invalid character')
		}
	}
	if identity.xuid.len > max_xuid_len {
		return error('xuid too long')
	}
	// An empty uuid is allowed - player_key falls back to the (charset-checked)
	// display_name and playerdb sanitises the final key. Only cap the max length
	// so an oversized value can't bloat identifiers.
	if identity.uuid.len > max_uuid_len {
		return error('uuid too long')
	}
}

// trusted_identity strips the account identifiers from an unverified login.
// A self-signed offline chain carries whatever xuid and uuid the client felt
// like sending, and those two fields are the ones the rest of the server treats
// as an account: permission grants key off them, the save file is named after
// them, and the player list broadcasts the xuid to every other client as the
// Xbox profile to look up. Clearing them here means an offline session is only
// ever its display name - which is charset checked, held for the length of the
// session, and never claims to be an Xbox account.
//
// The display name itself stays unverified in offline mode: a client picks its
// own, so it can take the name (and with it the ops entry and save file) of any
// player who is not currently connected. That is inherent to running with
// xbox-auth off, which is why it defaults to on.
fn trusted_identity(identity auth.Identity) auth.Identity {
	if identity.xbox_authenticated {
		return identity
	}
	return auth.Identity{
		...identity
		xuid: ''
		uuid: ''
	}
}

fn (mut s NetworkSession) start_resource_packs() ! {
	mut entries := []proto.ResourcePackEntry{}
	if !isnil(s.hub.packs) {
		for pack in s.hub.packs.packs {
			entries << proto.ResourcePackEntry{
				id:      proto.uuid_from_bytes(pack.uuid_bytes())
				version: pack.version
				size:    u64(pack.size)
				cdn_url: pack.cdn_url
			}
		}
	}
	s.transport.send(&proto.ResourcePacksInfoPacket{
		resource_pack_required: s.packs_must_accept()
		resource_packs:         entries
	})!
	s.state = .resource_packs
}

fn (s &NetworkSession) packs_must_accept() bool {
	return !isnil(s.hub.packs) && s.hub.packs.must_accept
}

fn (mut s NetworkSession) send_pack_stack() ! {
	mut stack := []proto.PackEntry{}
	if !isnil(s.hub.packs) {
		for pack in s.hub.packs.packs {
			stack << proto.PackEntry{
				id:      pack.uuid
				version: pack.version
			}
		}
	}
	s.transport.send(&proto.ResourcePackStackPacket{
		texture_pack_required: s.packs_must_accept()
		addon_list:            stack
		base_game_version:     proto.BaseGameVersion{
			value: proto.selected_minecraft_version
		}
		experiments:           proto.Experiments{}
	})!
}

fn (mut s NetworkSession) handle_resource_pack_response(p proto.ResourcePackClientResponsePacket) ! {
	response := proto.resource_pack_response(p.response)
	match response {
		proto.ResourcePackResponseCancel {
			if s.packs_must_accept() {
				s.reject_bootstrap('You must accept the server resource packs to play')
				return
			}
			s.send_pack_stack()!
		}
		proto.ResourcePackResponseDownloading {
			s.send_requested_packs(response.downloading_packs)!
		}
		proto.ResourcePackResponseDownloadingFinished {
			s.send_pack_stack()!
		}
		proto.ResourcePackResponseStackFinished {
			s.start_game()!
		}
	}
}

fn (mut s NetworkSession) send_requested_packs(pack_ids []string) ! {
	if isnil(s.hub.packs) {
		return
	}
	for id in pack_ids {
		pack := s.hub.packs.find(id) or {
			s.log.warn('Client requested unknown resource pack ${id}')
			continue
		}
		// CDN packs are fetched by the client directly - nothing to upload.
		if pack.is_cdn() {
			continue
		}
		s.transport.send(&proto.ResourcePackDataInfoPacket{
			resource_name: pack.id()
			chunk_size:    u32(resourcepack.pack_chunk_size)
			chunk_amount:  u32(pack.chunk_count())
			file_size:     u64(pack.size)
			file_hash:     pack.sha256.bytes()
			is_premium:    false
			pack_type:     proto.PackType.resources
		})!
	}
}

fn (mut s NetworkSession) handle_resource_pack_chunk_request(p proto.ResourcePackChunkRequestPacket) ! {
	if isnil(s.hub.packs) {
		return
	}
	pack := s.hub.packs.find(p.resource_name) or {
		s.log.warn('Chunk request for unknown resource pack ${p.resource_name}')
		return
	}
	s.transport.send(&proto.ResourcePackChunkDataPacket{
		resource_name: pack.id()
		chunk_id:      p.chunk
		byte_offset:   u64(p.chunk) * u64(resourcepack.pack_chunk_size)
		chunk_data:    pack.chunk(int(p.chunk))
	})!
}
