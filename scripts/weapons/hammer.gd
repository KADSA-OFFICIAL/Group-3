extends Weapon
## 망치: 느리지만 강한 근접 공격 + 타격 시 기절 효과(기획서 스킬).

const HIT_RANGE := 60.0
const STUN_DURATION := 1.0


func _init() -> void:
	damage = 25.0
	cooldown = 1.2


func _perform_attack() -> void:
	var target := melee_hit(HIT_RANGE, 300.0)
	if target:
		target.apply_stun(STUN_DURATION)
