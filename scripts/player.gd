class_name Player
extends CharacterBody2D
## 2인 로컬 대전용 플레이어. player_id에 따라 p1_*/p2_* 입력 액션을 사용한다.

signal died(player_id: int)
signal health_changed(player_id: int, health: float)

const SPEED := 260.0
const ACCEL := 2200.0
const JUMP_VELOCITY := -430.0
const MAX_HEALTH := 100.0

@export var player_id := 1

var health := MAX_HEALTH
var facing := 1
var stun_left := 0.0
var weapon: Weapon

@onready var body_rect: ColorRect = $Body
@onready var weapon_mount: Node2D = $WeaponMount


func _ready() -> void:
	add_to_group("players")
	body_rect.color = Color(0.35, 0.55, 1.0) if player_id == 1 else Color(1.0, 0.4, 0.4)
	_equip(GameManager.weapon_for(player_id))


func _equip(weapon_id: String) -> void:
	if weapon:
		weapon.queue_free()
	var weapon_script: GDScript = load(GameManager.WEAPONS[weapon_id]["script"])
	weapon = weapon_script.new()
	weapon.wielder = self
	weapon_mount.add_child(weapon)


func reset(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	health = MAX_HEALTH
	stun_left = 0.0
	health_changed.emit(player_id, health)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	stun_left = maxf(stun_left - delta, 0.0)
	var direction := 0.0
	if stun_left <= 0.0:
		direction = Input.get_axis(_action("left"), _action("right"))
		if Input.is_action_just_pressed(_action("up")) and is_on_floor():
			velocity.y = JUMP_VELOCITY
		if Input.is_action_just_pressed(_action("attack")) and weapon:
			weapon.try_attack()

	velocity.x = move_toward(velocity.x, direction * SPEED, ACCEL * delta)
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
		weapon_mount.position.x = 24.0 * facing
	move_and_slide()


func take_damage(amount: float, knockback: Vector2 = Vector2.ZERO) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	velocity += knockback
	health_changed.emit(player_id, health)
	if health <= 0.0:
		died.emit(player_id)


func apply_stun(duration: float) -> void:
	stun_left = maxf(stun_left, duration)


func _action(action_name: String) -> String:
	return "p%d_%s" % [player_id, action_name]
