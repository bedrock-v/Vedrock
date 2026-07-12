module item

import time
import server.effect

pub struct ConsumeResult {
pub:
	effects           []effect.Effect
	replacement_id    string
	replacement_count int
}

pub struct PotionType {
	value int
}

pub fn potion_from_meta(meta int) PotionType {
	return PotionType{
		value: meta
	}
}

pub fn (p PotionType) id() int {
	return p.value
}

pub fn (p PotionType) effects() []effect.Effect {
	match p.value {
		5 {
			return [effect.new(effect.night_vision, 1, 3 * 60 * time.second)]
		}
		6 {
			return [effect.new(effect.night_vision, 1, 8 * 60 * time.second)]
		}
		7 {
			return [effect.new(effect.invisibility, 1, 3 * 60 * time.second)]
		}
		8 {
			return [effect.new(effect.invisibility, 1, 8 * 60 * time.second)]
		}
		9 {
			return [effect.new(effect.jump_boost, 1, 3 * 60 * time.second)]
		}
		10 {
			return [effect.new(effect.jump_boost, 1, 8 * 60 * time.second)]
		}
		11 {
			return [effect.new(effect.jump_boost, 2, 90 * time.second)]
		}
		12 {
			return [effect.new(effect.fire_resistance, 1, 3 * 60 * time.second)]
		}
		13 {
			return [effect.new(effect.fire_resistance, 1, 8 * 60 * time.second)]
		}
		14 {
			return [effect.new(effect.speed, 1, 3 * 60 * time.second)]
		}
		15 {
			return [effect.new(effect.speed, 1, 8 * 60 * time.second)]
		}
		16 {
			return [effect.new(effect.speed, 2, 90 * time.second)]
		}
		17 {
			return [effect.new(effect.slowness, 1, 90 * time.second)]
		}
		18 {
			return [effect.new(effect.slowness, 1, 4 * 60 * time.second)]
		}
		19 {
			return [effect.new(effect.water_breathing, 1, 3 * 60 * time.second)]
		}
		20 {
			return [effect.new(effect.water_breathing, 1, 8 * 60 * time.second)]
		}
		21 {
			return [effect.new_instant(effect.instant_health, 1)]
		}
		22 {
			return [effect.new_instant(effect.instant_health, 2)]
		}
		23 {
			return [effect.new_instant(effect.instant_damage, 1)]
		}
		24 {
			return [effect.new_instant(effect.instant_damage, 2)]
		}
		25 {
			return [effect.new(effect.poison, 1, 45 * time.second)]
		}
		26 {
			return [effect.new(effect.poison, 1, 2 * 60 * time.second)]
		}
		27 {
			return [effect.new(effect.poison, 2, 22500 * time.millisecond)]
		}
		28 {
			return [effect.new(effect.regeneration, 1, 45 * time.second)]
		}
		29 {
			return [effect.new(effect.regeneration, 1, 2 * 60 * time.second)]
		}
		30 {
			return [effect.new(effect.regeneration, 2, 22500 * time.millisecond)]
		}
		31 {
			return [effect.new(effect.strength, 1, 3 * 60 * time.second)]
		}
		32 {
			return [effect.new(effect.strength, 1, 8 * 60 * time.second)]
		}
		33 {
			return [effect.new(effect.strength, 2, 90 * time.second)]
		}
		34 {
			return [effect.new(effect.weakness, 1, 90 * time.second)]
		}
		35 {
			return [effect.new(effect.weakness, 1, 4 * 60 * time.second)]
		}
		36 {
			return [effect.new(effect.wither, 1, 40 * time.second)]
		}
		37 {
			return [
				effect.new(effect.resistance, 3, 20 * time.second),
				effect.new(effect.slowness, 4, 20 * time.second),
			]
		}
		38 {
			return [
				effect.new(effect.resistance, 3, 40 * time.second),
				effect.new(effect.slowness, 4, 40 * time.second),
			]
		}
		39 {
			return [
				effect.new(effect.resistance, 5, 20 * time.second),
				effect.new(effect.slowness, 6, 20 * time.second),
			]
		}
		40 {
			return [effect.new(effect.slow_falling, 1, 90 * time.second)]
		}
		41 {
			return [effect.new(effect.slow_falling, 1, 4 * 60 * time.second)]
		}
		42 {
			return [effect.new(effect.slowness, 4, 20 * time.second)]
		}
		else {}
	}

	return []effect.Effect{}
}

pub struct PotionItem {}

fn new_potion_item() PotionItem {
	return PotionItem{}
}

pub fn (i PotionItem) identifier() string {
	return 'minecraft:potion'
}

pub fn (i PotionItem) max_stack_size() int {
	return 1
}

pub fn (i PotionItem) attack_damage() f32 {
	return 0
}

pub fn (i PotionItem) nutrition() int {
	return 0
}

pub fn (i PotionItem) saturation() f32 {
	return 0
}

pub fn (i PotionItem) block_runtime_id() int {
	return 0
}

pub fn (i PotionItem) durability() int {
	return 0
}

pub fn (i PotionItem) mining_speed() f32 {
	return 1.0
}

pub fn (i PotionItem) armor_points() int {
	return 0
}

pub fn (i PotionItem) consume_result(meta int) ConsumeResult {
	return ConsumeResult{
		effects:           potion_from_meta(meta).effects()
		replacement_id:    'minecraft:glass_bottle'
		replacement_count: 1
	}
}
