class_name Projectile
extends Area2D
## 무기에서 발사되는 투사체. 노드 구성은 코드로 생성한다.

const LIFETIME := 2.0

var direction := 1
var speed := 520.0
var damage := 8.0
var shooter: Player


func _ready() -> void:
	add_to_group("projectiles")
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	collision.shape = circle
	add_child(collision)

	var visual := ColorRect.new()
	visual.size = Vector2(12, 4)
	visual.position = Vector2(-6, -2)
	visual.color = Color(1.0, 0.9, 0.3)
	add_child(visual)

	body_entered.connect(_on_body_entered)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	if body == shooter:
		return
	var target := body as Player
	if target:
		target.take_damage(damage, Vector2(direction * 140.0, -60.0))
	queue_free()
