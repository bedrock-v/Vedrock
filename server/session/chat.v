module session

import protocol
import protocol.enums
import server.cmd
import server.event

fn (mut s NetworkSession) handle_text(p protocol.TextPacket) ! {
	if p.@type != int(enums.TextType.chat) {
		return
	}
	message := p.message.trim_space()
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
	if ctx.is_cancelled() {
		return
	}
	final := ctx.val.message
	s.log.info('<${s.identity.display_name}> ${final}')
	s.hub.broadcast(&protocol.TextPacket{
		@type:       int(enums.TextType.chat)
		source_name: s.identity.display_name
		message:     final
	})
}

fn (mut s NetworkSession) handle_command_request(p protocol.CommandRequestPacket) ! {
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
	s.log.info('${s.identity.display_name} issued command: ${final}')
	ctx := cmd.Context{
		lang:           s.hub.lang
		sender_name:    s.identity.display_name
		player_count:   s.hub.count()
		max_players:    s.cfg.max_players
		server_motd:    s.cfg.motd
		uptime_seconds: s.hub.uptime_seconds()
		tps:            s.hub.tps()
		load:           s.hub.load()
	}
	s.hub.commands.dispatch(final, mut s, ctx)!
}

fn (mut s NetworkSession) send_message(message string) ! {
	s.transport.send(&protocol.TextPacket{
		@type:   int(enums.TextType.raw)
		message: message
	})!
}

fn (mut s NetworkSession) send_translation(message string, parameters []string) ! {
	s.transport.send(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           message
		parameters:        parameters
	})!
}
