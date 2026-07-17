class_name Weapon
extends Node2D
## 모든 무기의 베이스 클래스. 새 무기는 이 클래스를 상속하고 _perform_attack()을 구현한 뒤
## GameManager.WEAPONS에 등록한다. 스킬 발동 조건은 쿨타임(기획서 3번 항목).

var damage := 10.0
var cooldown := 0.5
var wielder: Player

var _cooldown_left := 0.0


func _process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func try_attack() -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = cooldown
	_perform_attack()


func _perform_attack() -> void:
	pass


## 근접 판정 헬퍼: wielder가 바라보는 방향의 상대에게 데미지를 준다.
func melee_hit(hit_range: float, knockback_power: float) -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		var target := node as Player
		if target == null or target == wielder:
			continue
		var to_target: Vector2 = target.global_position - wielder.global_position
		if absf(to_target.y) > 50.0 or to_target.length() > hit_range:
			continue
		if signf(to_target.x) != signf(wielder.facing) and to_target.x != 0.0:
			continue
		target.take_damage(damage, Vector2(wielder.facing * knockback_power, -knockback_power * 0.5))
		return target
	return null
