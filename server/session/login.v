module session

import server.internal.network
import server.internal.auth
import server.internal.encryption
import server.resource
import protocol
import protocol.enums
import protocol.types

fn (mut s NetworkSession) handle_request_network_settings(p protocol.RequestNetworkSettingsPacket) ! {
	s.log.debug('Client requested network settings (protocol ${p.protocol_version})')
	if p.protocol_version != protocol.current_protocol {
		status := if p.protocol_version < protocol.current_protocol {
			enums.PlayStatus.login_failed_client
		} else {
			enums.PlayStatus.login_failed_server
		}
		s.log.warn('Rejected client with protocol ${p.protocol_version} (server requires ${protocol.current_protocol})')
		s.transport.send(&protocol.PlayStatusPacket{
			status: int(status)
		})!
		s.reject_bootstrap('Incompatible client version. Server requires ${protocol.minecraft_version_network}.')
		return
	}
	s.transport.send(&protocol.NetworkSettingsPacket{
		compression_threshold:     s.cfg.compression_threshold
		compression_algorithm:     int(network.compression_flate)
		enable_client_throttling:  false
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

fn (mut s NetworkSession) handle_login(p protocol.LoginPacket) ! {
	identity := auth.parse_login_chain(p.auth_info_json, s.cfg.xbox_auth, mut s.hub.oidc_verifier) or {
		s.log.warn('Authentication failed: ${err}')
		s.reject_bootstrap('Login failed: ${err}')
		return
	}
	// parse_login_chain verifies the JWT chain signatures, but with xbox_auth
	// off the display_name/xuid/uuid come from a self-signed offline chain and
	// are NOT proof of identity - only trustworthy when identity.xbox_authenticated.
	// Validate the fields regardless so downstream code (whitelist, ops, grants,
	// data files keyed by these strings) never sees empty or oversized input.
	s.validate_identity(identity) or {
		s.log.warn('Rejected login from ${s.transport.remote_addr()}: ${err}')
		s.reject_bootstrap('Login failed: invalid identity')
		return
	}
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
	s.hub.player_grants.apply(mut s.player.perm, identity.display_name, identity.xuid,
		identity.uuid)
	mode := if identity.xbox_authenticated { 'Xbox Live' } else { 'offline' }
	s.log.info('${identity.display_name} authenticated [${mode}] xuid=${identity.xuid} uuid=${identity.uuid}')
	// Negotiate protocol encryption before login_success so the rest of the
	// session runs ciphered. Gated behind the encryption config flag (off by
	// default until interop is verified). If the client sent no public key, or
	// the handshake fails, we fall back to cleartext rather than dropping the
	// player.
	if s.cfg.encryption {
		s.start_encryption(identity.client_public_key) or {
			s.log.warn('Encryption handshake skipped for ${identity.display_name}: ${err}')
		}
	}
	s.transport.send(&protocol.PlayStatusPacket{
		status: int(enums.PlayStatus.login_success)
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
	s.transport.send(&protocol.ServerToClientHandshakePacket{
		jwt: result.handshake_jwt
	})!
	s.transport.enable_encryption(mut ctx)
	s.encryption_enabled = true
	s.log.debug('Encryption enabled for ${s.player.identity.display_name}')
}

fn (mut s NetworkSession) handle_client_to_server_handshake(p protocol.ClientToServerHandshakePacket) ! {
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
	// TODO(security): with xbox_auth disabled we accept any self-signed offline
	// chain - display_name/xuid are unverified and a client can impersonate any
	// non-online player. Operators relying on identity must set xbox_auth=true.
}

fn (mut s NetworkSession) start_resource_packs() ! {
	mut entries := []protocol.ResourcePackInfoEntry{}
	if !isnil(s.hub.packs) {
		for pack in s.hub.packs.packs {
			entries << protocol.ResourcePackInfoEntry{
				uuid:       types.uuid_from_bytes(pack.uuid_bytes())
				version:    pack.version
				size_bytes: pack.size
				cdn_url:    pack.cdn_url
			}
		}
	}
	s.transport.send(&protocol.ResourcePacksInfoPacket{
		must_accept: s.packs_must_accept()
		entries:     entries
	})!
	s.state = .resource_packs
}

fn (s &NetworkSession) packs_must_accept() bool {
	return !isnil(s.hub.packs) && s.hub.packs.must_accept
}

fn (mut s NetworkSession) send_pack_stack() ! {
	mut stack := []protocol.ResourcePackStackEntry{}
	if !isnil(s.hub.packs) {
		for pack in s.hub.packs.packs {
			stack << protocol.ResourcePackStackEntry{
				pack_id: pack.uuid
				version: pack.version
			}
		}
	}
	s.transport.send(&protocol.ResourcePackStackPacket{
		must_accept:         s.packs_must_accept()
		resource_pack_stack: stack
		base_game_version:   protocol.minecraft_version_network
		experiments:         types.Experiments{}
	})!
}

fn (mut s NetworkSession) handle_resource_pack_response(p protocol.ResourcePackClientResponsePacket) ! {
	match p.status {
		protocol.resource_response_refused {
			if s.packs_must_accept() {
				s.reject_bootstrap('You must accept the server resource packs to play')
				return
			}
			s.send_pack_stack()!
		}
		protocol.resource_response_send_packs {
			s.send_requested_packs(p.pack_ids)!
		}
		protocol.resource_response_have_all_packs {
			s.send_pack_stack()!
		}
		protocol.resource_response_completed {
			s.start_game()!
		}
		else {
			s.log.debug('Unhandled resource pack response status ${p.status}')
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
		s.transport.send(&protocol.ResourcePackDataInfoPacket{
			pack_id:              pack.id()
			max_chunk_size:       resource.pack_chunk_size
			chunk_count:          pack.chunk_count()
			compressed_pack_size: pack.size
			sha256:               pack.sha256
			is_premium:           false
			pack_type:            resource.pack_type_resources
		})!
	}
}

fn (mut s NetworkSession) handle_resource_pack_chunk_request(p protocol.ResourcePackChunkRequestPacket) ! {
	if isnil(s.hub.packs) {
		return
	}
	pack := s.hub.packs.find(p.pack_id) or {
		s.log.warn('Chunk request for unknown resource pack ${p.pack_id}')
		return
	}
	s.transport.send(&protocol.ResourcePackChunkDataPacket{
		pack_id:     pack.id()
		chunk_index: p.chunk_index
		offset:      u64(p.chunk_index) * u64(resource.pack_chunk_size)
		data:        pack.chunk(p.chunk_index)
	})!
}
