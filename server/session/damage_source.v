module session

import math

// DamageSource identifies what caused damage dealt to a player. It decides
// fire resistance immunity and resistance effect reduction & supplies the
// %death.attack.* translation key-parameters for the death message.
pub interface DamageSource {
	// ignored_by_fire_resistance reports whether the fire_resistance effect
	// completely blocks this damage (fire, lava).
	ignored_by_fire_resistance() bool
	// reduced_by_resistance reports whether the resistance effect's damage
	// multiplier applies to this source.
	reduced_by_resistance() bool
	// reduced_by_armor reports whether worn armor takes a share of this
	// damage. Sources that reach past armor entirely (drowning, the void,
	// potion damage) answer false and leave equipment untouched.
	reduced_by_armor() bool
	// attacker_label is the display string used for the player_hurt event's
	// informational attacker_name field. Empty for sources with no
	// attacker (fall, void, drowning, fire, lava).
	attacker_label() string
	// death_message_key returns the %death.attack.* translation key and its
	// ordered parameters for a victim named victim_name.
	death_message_key(victim_name string) (string, []string)
}

// AttackDamageSource is damage from another entity's melee attack.
pub struct AttackDamageSource {
pub:
	attacker_name string
}

pub fn (s AttackDamageSource) ignored_by_fire_resistance() bool {
	return false
}

pub fn (s AttackDamageSource) reduced_by_resistance() bool {
	return true
}

pub fn (s AttackDamageSource) reduced_by_armor() bool {
	return true
}

pub fn (s AttackDamageSource) attacker_label() string {
	return s.attacker_name
}

pub fn (s AttackDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.player', [victim_name, s.attacker_name]
}

// ProjectileDamageSource is damage from a projectile.
pub struct ProjectileDamageSource {
pub:
	attacker_name string
}

pub fn (s ProjectileDamageSource) ignored_by_fire_resistance() bool {
	return false
}

pub fn (s ProjectileDamageSource) reduced_by_resistance() bool {
	return true
}

pub fn (s ProjectileDamageSource) reduced_by_armor() bool {
	return true
}

pub fn (s ProjectileDamageSource) attacker_label() string {
	return s.attacker_name
}

pub fn (s ProjectileDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.arrow', [victim_name, s.attacker_name]
}

// MobAttackDamageSource is damage from a hostile mob's own melee attack.
// Kept distinct from AttackDamageSource and ProjectileDamageSource.
pub struct MobAttackDamageSource {
pub:
	attacker_name string
}

pub fn (s MobAttackDamageSource) ignored_by_fire_resistance() bool {
	return false
}

pub fn (s MobAttackDamageSource) reduced_by_resistance() bool {
	return true
}

pub fn (s MobAttackDamageSource) reduced_by_armor() bool {
	return true
}

pub fn (s MobAttackDamageSource) attacker_label() string {
	return s.attacker_name
}

pub fn (s MobAttackDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.mob', [victim_name, s.attacker_name]
}

// MagicDamageSource is damage from a potion/status effect (instant damage,
// poison, wither, etc.).
pub struct MagicDamageSource {}

pub fn (s MagicDamageSource) ignored_by_fire_resistance() bool {
	return false
}

pub fn (s MagicDamageSource) reduced_by_resistance() bool {
	return true
}

pub fn (s MagicDamageSource) reduced_by_armor() bool {
	return false
}

pub fn (s MagicDamageSource) attacker_label() string {
	return ''
}

pub fn (s MagicDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.magic', [victim_name]
}

// FallDamageSource is damage from falling too far.
pub struct FallDamageSource {}

pub fn (s FallDamageSource) ignored_by_fire_resistance() bool {
	return false
}

pub fn (s FallDamageSource) reduced_by_resistance() bool {
	return true
}

pub fn (s FallDamageSource) reduced_by_armor() bool {
	return true
}

pub fn (s FallDamageSource) attacker_label() string {
	return ''
}

pub fn (s FallDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.fell.accident.generic', [victim_name]
}

// VoidDamageSource is damage from falling below the world.
pub struct VoidDamageSource {}

pub fn (s VoidDamageSource) ignored_by_fire_resistance() bool {
	return false
}

pub fn (s VoidDamageSource) reduced_by_resistance() bool {
	return false
}

pub fn (s VoidDamageSource) reduced_by_armor() bool {
	return false
}

pub fn (s VoidDamageSource) attacker_label() string {
	return ''
}

pub fn (s VoidDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.outOfWorld', [victim_name]
}

// DrowningDamageSource is damage from running out of breath underwater.
pub struct DrowningDamageSource {}

pub fn (s DrowningDamageSource) ignored_by_fire_resistance() bool {
	return false
}

pub fn (s DrowningDamageSource) reduced_by_resistance() bool {
	return false
}

pub fn (s DrowningDamageSource) reduced_by_armor() bool {
	return false
}

pub fn (s DrowningDamageSource) attacker_label() string {
	return ''
}

pub fn (s DrowningDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.drown', [victim_name]
}

// StarvationDamageSource is damage from an empty hunger bar.
pub struct StarvationDamageSource {}

pub fn (s StarvationDamageSource) ignored_by_fire_resistance() bool {
	return false
}

pub fn (s StarvationDamageSource) reduced_by_resistance() bool {
	return false
}

pub fn (s StarvationDamageSource) reduced_by_armor() bool {
	return false
}

pub fn (s StarvationDamageSource) attacker_label() string {
	return ''
}

pub fn (s StarvationDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.starve', [victim_name]
}

// FireDamageSource is damage from burning while on fire.
pub struct FireDamageSource {}

pub fn (s FireDamageSource) ignored_by_fire_resistance() bool {
	return true
}

pub fn (s FireDamageSource) reduced_by_resistance() bool {
	return true
}

pub fn (s FireDamageSource) reduced_by_armor() bool {
	return true
}

pub fn (s FireDamageSource) attacker_label() string {
	return ''
}

pub fn (s FireDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.onFire', [victim_name]
}

// LavaDamageSource is damage from touching lava.
pub struct LavaDamageSource {}

pub fn (s LavaDamageSource) ignored_by_fire_resistance() bool {
	return true
}

pub fn (s LavaDamageSource) reduced_by_resistance() bool {
	return true
}

pub fn (s LavaDamageSource) reduced_by_armor() bool {
	return true
}

pub fn (s LavaDamageSource) attacker_label() string {
	return ''
}

pub fn (s LavaDamageSource) death_message_key(victim_name string) (string, []string) {
	return '%death.attack.lava', [victim_name]
}

// resistance_multiplier reduces incoming damage by 20% per Resistance
// level, reaching full immunity at level 5. Effect levels are 1-indexed.
fn resistance_multiplier(level int) f32 {
	return math.max(f32(0), f32(1.0) - f32(0.2) * f32(level))
}
