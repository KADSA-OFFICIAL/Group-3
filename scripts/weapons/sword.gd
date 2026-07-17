extends Weapon
## 검: 짧은 쿨타임의 근접 공격. (기획서: 돌진/처형 스킬은 추후 확장)

const HIT_RANGE := 56.0


func _init() -> void:
	damage = 15.0
	cooldown = 0.4


func _perform_attack() -> void:
	melee_hit(HIT_RANGE, 220.0)
