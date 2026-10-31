module server

import bedrock_v.protocol.enums
import server.network
import server.world
import server.world.block
import server.world.chunk
import server.world.generator

// Config is a server's settings.
pub struct Config {
pub:
	// listeners are what this server accepts clients on, one function each,
	// called when the server starts.
	//
	// A server with none accepts nobody and there is no default.
	listeners []network.ListenerFn
	motd      string = 'Vedrock'
	// sub_motd is the second line of the server's entry in the game's list.
	// When you unset, it is world_name, as Bedrock Dedicated Server shows its level
	// name there.
	sub_motd string
	// max_players is how many players are admitted at once, and what a client is
	// told before it joins. A client takes a slot when it arrives. This also
	// bounds how many can be logging in. Zero admits any number.
	max_players int = 20
	// network_id is the id NetherNet signalling knows this server by.
	network_id u64
	// media_port is the UDP port every player's connection runs over, the one a
	// firewall has to let through. The server fails to start when it is taken.
	// Zero gives each connection a port the kernel picks.
	media_port u16 = 19133
	// world_name names the world players join.
	world_name string = 'world'
	// generator fills the chunks the world has never had. The default is a flat
	// world of grass, dirt and bedrock.
	generator world.Generator = default_generator()
	// game_type is the game mode players join in.
	game_type enums.GameType = .creative
	login     network.LoginConfig
	verifier  ?network.LoginVerifier
}

// status is what every listener tells a client before it joins. One server
// describes itself one way, whichever listener is answering.
fn (cfg &Config) status() network.Status {
	return network.Status{
		motd:        cfg.motd
		sub_motd:    if cfg.sub_motd != '' { cfg.sub_motd } else { cfg.world_name }
		max_players: cfg.max_players
		network_id:  cfg.network_id
	}
}

// default_generator is a flat world of grass on two layers of dirt on bedrock,
// in the plains.
fn default_generator() world.Generator {
	return generator.new_flat(chunk.plains_biome, [
		block.State{
			name:       'minecraft:bedrock'
			properties: [block.Property{'infiniburn_bit', block.Value(u8(0))}]
		},
		block.State{
			name: 'minecraft:dirt'
		},
		block.State{
			name: 'minecraft:dirt'
		},
		block.State{
			name: 'minecraft:grass_block'
		},
	]) or { panic(err) }
}
