module default

import server.cmd

// water_permission gates /water. Registered as an operator-only default from
// register_all so it lines up with the other command nodes.
pub const water_permission = 'vedrock.cmd.water'

// WaterCommand places a water source at the sender's feet and lets it flow.
// Handy for testing the liquid spread engine in-world.
pub struct WaterCommand {}

pub fn (c WaterCommand) name() string {
	return 'water'
}

pub fn (c WaterCommand) description() string {
	return 'Places flowing water at your position'
}

pub fn (c WaterCommand) aliases() []string {
	return []
}

pub fn (c WaterCommand) permission() string {
	return water_permission
}

pub fn (c WaterCommand) arguments() []cmd.Argument {
	return []
}

pub fn (c WaterCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if !sender.is_player() {
		sender.send_message(ctx.lang.t('cmd.player_only'))!
		return
	}
	x, y, z := sender.position()
	sender.place_water(int(x), int(y), int(z))
	sender.send_message('Placed water.')!
}
