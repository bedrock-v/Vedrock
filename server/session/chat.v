module session

import encoding.utf8
import server.cmd
import server.event
import server.player.chat
import protocol.current as proto

// The wire message is an unbounded string, while the vanilla client caps chat
// at 512 characters and a command line well below that. Without a bound here
// one client could make the server fan out megabytes of text to every player.
const max_chat_message_bytes = 512
const max_command_bytes = 1024

// sanitize_chat_message strips what a player must not be able to put in a line
// other players see: formatting codes ("§", which can forge another player's
// chat line or the server's own messages) and control characters such as the
// newline that would forge whole extra lines.
fn sanitize_chat_message(text string) string {
	mut out := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		c := text[i]
		if c == 0xc2 && i + 1 < text.len && text[i + 1] == 0xa7 {
			i += 2
			continue
		}
		if c < 0x20 || c == 0x7f {
			i++
			continue
		}
		out << c
		i++
	}
	return out.bytestr().trim_space()
}

fn (mut s NetworkSession) handle_text(p proto.TextPacket) ! {
	text := proto.text_chat(p.message_type) or { return }
	if text.message.len > max_chat_message_bytes {
		return error('chat message of ${text.message.len} bytes exceeds the limit')
	}
	if !utf8.validate_str(text.message) {
		return error('chat message is not valid UTF-8')
	}
	message := sanitize_chat_message(text.message)
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
	s.hub.broadcast(&proto.TextPacket{
		message_type: proto.TextChat{
			player_name: s.player.identity.display_name
			message:     final
		}
	})
}

fn (mut s NetworkSession) handle_command_request(p proto.CommandRequestPacket) ! {
	if p.command.len > max_command_bytes {
		return error('command line of ${p.command.len} bytes exceeds the limit')
	}
	if !utf8.validate_str(p.command) {
		return error('command line is not valid UTF-8')
	}
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
	s.deliver(&proto.TextPacket{
		message_type: proto.TextRaw{
			message: message
		}
	})
}

fn (mut s NetworkSession) send_translation(message string, parameters []string) ! {
	s.deliver(&proto.TextPacket{
		localize:     true
		message_type: proto.TextTranslate{
			message:        message
			parameter_list: parameters
		}
	})
}

// subscriber_id identifies this session in a chat channel. The runtime id is
// unique for as long as the session is connected, which is exactly as long as
// it stays subscribed.
fn (s &NetworkSession) subscriber_id() u64 {
	return s.runtime_id
}

// message satisfies chat.Subscriber. Chat written to a channel this session is
// subscribed to arrives here as plain text.
fn (mut s NetworkSession) message(text string) {
	s.send_message(text) or {}
}

// join_global_chat subscribes the session to the chat every online player
// receives. It is undone by leave_global_chat when the session goes away.
fn (mut s NetworkSession) join_global_chat() {
	mut global := chat.global()
	global.subscribe(s)
}

fn (mut s NetworkSession) leave_global_chat() {
	mut global := chat.global()
	global.unsubscribe(s.runtime_id)
}
