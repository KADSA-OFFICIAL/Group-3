extends Weapon
## 총: 기본 발사. 바라보는 방향으로 투사체를 쏜다.

const PROJECTILE := preload("res://scripts/weapons/projectile.gd")


func _init() -> void:
	damage = 8.0
	cooldown = 0.3


func _perform_attack() -> void:
	var projectile: Area2D = PROJECTILE.new()
	projectile.direction = wielder.facing
	projectile.damage = damage
	projectile.shooter = wielder
	projectile.global_position = wielder.global_position + Vector2(wielder.facing * 30.0, -4.0)
	get_tree().current_scene.add_child(projectile)
