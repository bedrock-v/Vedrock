module session

import protocol.version.v898.packets as packets_898
import protocol.version.v924.packets as packets_924
import protocol.version.v924.enums as enums_924
import server.cmd
import server.event

fn (mut s NetworkSession) handle_text(p packets_924.TextPacket) ! {
	if p.message_type !is enums_924.TextChat {
		return
	}
	message := p.message_type.message.trim_space()
	if message == '' {
		return
	}
	if message.starts_with('/') {
		s.run_command(message)!
		return
	}
	mut ctx := event.new_context(event.ChatData{
		player:  s
		message: message
	})
	s.hub.events.player_chat(mut ctx)
	if mut h := s.handler {
		h.on_player_chat(mut ctx)
	}
	if ctx.is_cancelled() {
		return
	}
	final := ctx.val.message
	s.log.info('<${s.player.identity.display_name}> ${final}')
	s.hub.broadcast(&packets_924.TextPacket{
		message_type: enums_924.TextChat{
			player_name: s.player.identity.display_name
			message:     final
		}
	})
}

fn (mut s NetworkSession) handle_command_request(p packets_898.CommandRequestPacket) ! {
	s.run_command(p.command)!
}

fn (mut s NetworkSession) run_command(line string) ! {
	mut cctx := event.new_context(event.CommandData{
		player:  s
		command: line
	})
	s.hub.events.player_command(mut cctx)
	if cctx.is_cancelled() {
		return
	}
	final := cctx.val.command
	s.log.info('${s.player.identity.display_name} issued command: ${final}')
	chunk_cache_entries, chunk_cache_bytes := s.hub.chunk_cache_totals()
	ctx := cmd.Context{
		lang:                          s.hub.lang
		sender_name:                   s.player.identity.display_name
		player_count:                  s.hub.count()
		max_players:                   s.cfg.max_players
		server_motd:                   s.cfg.motd
		uptime_seconds:                s.hub.uptime_seconds()
		tps:                           s.hub.tps()
		load:                          s.hub.load()
		memory_used_bytes:             i64(gc_memory_use())
		memory_heap_bytes:             i64(gc_heap_usage().heap_size)
		active_chunk_generation_count: s.hub.active_chunk_generation_count()
		chunk_cache_entries:           i64(chunk_cache_entries)
		chunk_cache_bytes:             chunk_cache_bytes
	}
	s.hub.dispatch_command(final, mut s, ctx)!
}

// send_message satisfies cmd.Sender but delivery is asynchronous. Commands
// may message another player's session, so the packet goes through deliver;
// socket failures are handled by the outbound writer.
fn (mut s NetworkSession) send_message(message string) ! {
	s.deliver(&packets_924.TextPacket{
		message_type: enums_924.TextRaw{
			message: message
		}
	})
}

fn (mut s NetworkSession) send_translation(message string, parameters []string) ! {
	s.deliver(&packets_924.TextPacket{
		localize:     true
		message_type: enums_924.TextTranslate{
			message:        message
			parameter_list: parameters
		}
	})
}
