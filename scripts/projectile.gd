class_name Projectile
extends Area2D
## 허공을 나는 것 (화살·총알·표창·산탄·던진 단검·폭탄 등).
##
## 서버만 이동과 판정을 하고, 클라이언트는 동기화된 위치를 그린다.
## 상대 무기에 막히지 않는다 — 회피로만 피한다.
##
## 스폰·디스폰은 main.gd의 ProjectileSpawner(MultiplayerSpawner)가 맡는다.
## 서버에서 queue_free()하면 클라이언트에서도 함께 사라진다.

## 서버가 이 투사체를 없애야 할 때 알린다.
signal finished(projectile: Node)
## 바닥에 남은 것(단검)을 주인이 주웠다.
signal picked_up(peer_id: int, projectile: Node)

## 허공을 나는 것은 공유 무적을 타지 않는다. 항상 "projectile" 이다.
const SOURCE := "projectile"
## 단검을 주울 수 있는 거리. 젤리 몸통(48px)에 닿으면 줍는 셈이다.
const PICKUP_RANGE := 48.0
## 중력을 받는 것(표창·폭탄·떨어진 단검)에 적용할 가속도.
const GRAVITY := 980.0

## 쏜 플레이어의 peer id. 자기 자신은 맞지 않는다.
var shooter_peer := 0
var damage := 0.0
var knockback := Combat.Knockback.WEAK
var stun := 0.0
## 상대를 관통해서 계속 날아가는가 (활 특수).
var pierce_targets := false
var use_gravity := false
## 벽·바닥에 닿았을 때 — "vanish" 사라짐 / "stay" 남음 / "return" 즉시 회수.
var on_solid := "vanish"
## 거리에 따라 데미지가 줄어드는 무기(샷건)용. 0 이면 감소 없음.
var falloff_min_damage := 0.0
var falloff_distance := 0.0
## 이 peer의 젤리를 자동으로 따라간다 (단검). 0 이면 직선.
var homing_peer := 0
## 이 시간이 지나면 스스로 터진다 (폭탄). 0 이면 안 터진다.
var fuse := 0.0
## 터질 때 이 반경 안을 때린다 (폭탄). 0 이면 단발 명중.
var explosion_radius := 0.0
## 바닥에 남았을 때 이 peer의 주인이 주울 수 있다 (단검).
var pickup_owner := 0

var velocity := Vector2.ZERO

var _spawn_time := 0.0
var _landed := false
var _origin := Vector2.ZERO
var _hit_peers := {}
var _done := false

@onready var visual: ColorRect = $Visual


## 모든 피어에서 스폰 데이터로 호출된다 (add_child 전).
func setup(data: Dictionary) -> void:
	shooter_peer = data["shooter_peer"]
	damage = data["damage"]
	knockback = data["knockback"]
	stun = data.get("stun", 0.0)
	pierce_targets = data.get("pierce_targets", false)
	use_gravity = data.get("use_gravity", false)
	on_solid = data.get("on_solid", "vanish")
	falloff_min_damage = data.get("falloff_min_damage", 0.0)
	falloff_distance = data.get("falloff_distance", 0.0)
	homing_peer = data.get("homing_peer", 0)
	fuse = data.get("fuse", 0.0)
	explosion_radius = data.get("explosion_radius", 0.0)
	pickup_owner = data.get("pickup_owner", 0)
	velocity = data["velocity"]
	position = data["position"]
	_origin = position


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_spawn_time = _now()
	if velocity.x < 0.0:
		visual.position.x = -visual.size.x


func _physics_process(delta: float) -> void:
	# 이동은 서버만 계산한다. 클라이언트는 동기화된 위치를 받는다.
	if not multiplayer.is_server() or _done:
		return

	# 도화선 (폭탄) — 바닥에 놓여 있어도 시간이 되면 터진다.
	if fuse > 0.0 and _now() - _spawn_time >= fuse:
		_explode()
		return

	# 바닥에 남은 것은 주인이 다가오면 회수된다 (단검).
	if _landed:
		if pickup_owner != 0:
			var owner_jelly := _find_jelly(pickup_owner)
			if owner_jelly != null and position.distance_to(owner_jelly.global_position) <= PICKUP_RANGE:
				_done = true
				picked_up.emit(pickup_owner, self)
		return

	# 유도 (단검) — 상대를 향해 방향을 계속 고친다.
	if homing_peer != 0:
		var target := _find_jelly(homing_peer)
		if target != null:
			velocity = (target.global_position - position).normalized() * Combat.PROJECTILE_SPEED

	if use_gravity:
		velocity.y += GRAVITY * delta
	position += velocity * delta

	# 맵에서 완전히 벗어나면 정리한다.
	var screen := get_viewport_rect().size
	if Combat.is_out_of_bounds(position, screen) or position.y < -Combat.FALL_MARGIN_SIDE:
		_finish()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _find_jelly(peer_id: int) -> Node:
	for jelly: Node in get_tree().get_nodes_in_group("jellies"):
		if jelly.owner_peer_id == peer_id:
			return jelly
	return null


## 폭탄 — 반경 안의 상대를 때리고 사라진다.
func _explode() -> void:
	if _done:
		return
	for jelly: Node in get_tree().get_nodes_in_group("jellies"):
		if jelly.owner_peer_id == shooter_peer or not jelly.alive:
			continue
		if position.distance_to(jelly.global_position) <= explosion_radius:
			jelly.server_apply_hit(damage, knockback, position.x, stun, SOURCE)
	_finish()


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server() or _done:
		return

	if body is Player:
		var peer_id: int = body.owner_peer_id
		if peer_id == shooter_peer or _hit_peers.has(peer_id) or not body.alive:
			return
		# 폭탄은 닿으면 터진다 (문서: "피격하거나 일정 시간이 지나면").
		if explosion_radius > 0.0:
			_explode()
			return
		_hit_peers[peer_id] = true
		body.server_apply_hit(_damage_at(position), knockback, _origin.x, stun, SOURCE)
		# 주울 수 있는 것(단검)은 맞힌 뒤에도 사라지지 않고 바닥으로 떨어진다.
		# 안 그러면 한 번만 쓸 수 있는 무기가 된다.
		if pickup_owner != 0:
			homing_peer = 0
			velocity = Vector2.ZERO
			use_gravity = true
			return
		if not pierce_targets:
			_finish()
		return

	# 벽·바닥·기물
	match on_solid:
		"vanish", "return":
			_finish()
		"stay":
			velocity = Vector2.ZERO
			_landed = true


## 샷건처럼 거리에 따라 데미지가 줄어드는 경우.
func _damage_at(where: Vector2) -> float:
	if falloff_distance <= 0.0:
		return damage
	var traveled: float = _origin.distance_to(where)
	var t: float = clampf(traveled / falloff_distance, 0.0, 1.0)
	return lerpf(damage, falloff_min_damage, t)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(self)
