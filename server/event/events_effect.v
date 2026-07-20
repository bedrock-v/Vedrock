module event

import server.player

// EffectAddData is dispatched before an effect is applied to a player.
// Cancelling it rejects the effect entirely. effect_name/level/duration_ticks
// are primitives rather than the effect.Effect/Type themselves.
pub struct EffectAddData {
pub:
	effect_name    string
	level          int
	duration_ticks int
pub mut:
	player player.View
}

// EffectRemoveData is dispatched before an effect is removed from a player,
// whether it expired naturally or was removed early. Cancelling it keeps the
// effect active.
pub struct EffectRemoveData {
pub:
	effect_name string
pub mut:
	player player.View
}
