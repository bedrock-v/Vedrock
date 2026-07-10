module session

import server.internal.network
import server.internal.auth
import protocol
import protocol.enums
import types

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
		s.disconnect('Incompatible client version. Server requires ${protocol.minecraft_version_network}.')
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

fn (mut s NetworkSession) handle_login(p protocol.LoginPacket) ! {
	identity := auth.parse_login_chain(p.auth_info_json, s.cfg.xbox_auth) or {
		s.log.warn('Authentication failed: ${err}')
		s.disconnect('Login failed: ${err}')
		return
	}
	if !s.hub.whitelist.is_allowed(identity.display_name) {
		s.log.info('${identity.display_name} is not white-listed, rejecting login')
		s.disconnect('You are not white-listed on this server!')
		return
	}
	s.identity = identity
	s.perm.set_op(s.hub.ops.is_op(identity.display_name))
	s.hub.player_grants.apply(mut s.perm, identity.display_name, identity.xuid, identity.uuid)
	mode := if identity.xbox_authenticated { 'Xbox Live' } else { 'offline' }
	s.log.info('${identity.display_name} authenticated [${mode}] xuid=${identity.xuid} uuid=${identity.uuid}')
	s.transport.send(&protocol.PlayStatusPacket{
		status: int(enums.PlayStatus.login_success)
	})!
	s.start_resource_packs()!
}

fn (mut s NetworkSession) start_resource_packs() ! {
	s.transport.send(&protocol.ResourcePacksInfoPacket{
		must_accept: false
		entries:     []protocol.ResourcePackInfoEntry{}
	})!
	s.state = .resource_packs
}

fn (mut s NetworkSession) handle_resource_pack_response(p protocol.ResourcePackClientResponsePacket) ! {
	match p.status {
		protocol.resource_response_have_all_packs {
			s.transport.send(&protocol.ResourcePackStackPacket{
				must_accept:         false
				resource_pack_stack: []protocol.ResourcePackStackEntry{}
				base_game_version:   protocol.minecraft_version_network
				experiments:         types.Experiments{}
			})!
		}
		protocol.resource_response_completed {
			s.start_game()!
		}
		else {
			s.log.debug('Unhandled resource pack response status ${p.status}')
		}
	}
}
