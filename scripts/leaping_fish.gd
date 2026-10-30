class_name LeapingFish
extends Area2D
## 노을 바다 맵의 물고기 (#338). 몇 초마다 물속에서 튀어올라 포물선을 그리고 다시 물로 들어간다.
##
## ## 바위와 물 뒤로 지나간다
##
## 맵 씬에서 **`Background` → `Fish` → `Front` → `Splash`** 순서로 둔다. `Front`는 원화에서
## 검은 바위와 바다만 남긴 그림이라, 물고기가 물에서 솟아 바위 뒤로 넘어가는 것처럼 보인다.
## `z_index`로 순서를 잡지 않는다 — 맵 배경이 z 0에 깔려 있어서 내리면 그 밑으로 사라진다(#146).
## 물보라는 물 **앞**에 보여야 하므로 `Front` 뒤의 `Splash` 노드에 그린다(`splash`).
##
## ## 판정은 main.gd 가 한다
##
## 이 노드는 날아가는 동안 겹친 몸체를 `struck`으로 알리기만 한다. 넉백을 줄지는 `main.gd`가
## 정한다(`_on_fish_struck`) — 판이 열려 있는지, 맞은 것이 젤리인지는 거기서 안다.
## **한 번 뛸 때 몸체마다 한 번만** 알린다. 매 틱 알리면 겹쳐 있는 내내 넉백이 다시 걸려
## 젤리가 물고기에 실려 간다.
##
## 좌표는 전부 **맵 칸(1152x648) 기준**이다 — 이 노드는 맵의 자식이라 맵이 가운데로
## 옮겨져도(#329) 같이 움직인다.

## 날아가는 물고기에 닿았다. `direction`은 물고기가 가던 쪽(-1 왼쪽, 1 오른쪽)이다.
signal struck(body: Node2D, direction: float)

## 뛰기 전·후에 물고기 몸통 중심이 머무는 높이. 물 앞그림(`Front`)에 몸 전체가 가려지는
## 깊이다 — 물 윗면이 가장 낮은 자리(≈590)에서도 몸 반쪽(≈41) 아래로 들어간다.
const UNDERWATER_Y := 650.0
## 물보라를 그리는 높이. 원화의 물 윗면 높이를 맵 좌표로 옮긴 값이다.
const SURFACE_Y := 578.0
## 물고기가 뜰 수 있는 가로 범위. 화면 끝에서 바로 솟으면 반쪽만 보인다.
const MIN_X := 60.0
const MAX_X := 1092.0

## 다음 점프까지 기다리는 시간(초). "가끔"이 되도록 넉넉히 잡는다.
const WAIT_MIN := 3.5
const WAIT_MAX := 7.5
## 한 번 뛰는 데 걸리는 시간(초).
const LEAP_TIME_MIN := 1.6
const LEAP_TIME_MAX := 2.2
## 꼭대기 높이(맵 y). 작을수록 높이 뛴다. 110보다 높으면 화면 위 점수판에 가려진다.
## 바위 윗면(275·418)을 넘나들어야 서 있는 젤리를
## 칠 일이 생긴다.
const APEX_MIN_Y := 110.0
const APEX_MAX_Y := 240.0
## 뜨는 자리와 들어가는 자리 사이 거리.
const SPAN_MIN := 320.0
const SPAN_MAX := 900.0

const SPLASH_TIME := 0.55
const SPLASH_DROPS := 7
const SPLASH_COLOR := Color(1, 1, 1, 0.9)

## 물보라를 그릴 노드. 씬에서 `Front` 뒤에 둔 `Splash`를 넘겨준다.
@export var splash: Node2D

@onready var _sprite: Sprite2D = $Sprite2D

var _rng := RandomNumberGenerator.new()
var _wait := 0.0
var _leaping := false
var _t := 0.0
var _duration := 1.0
var _from_x := 0.0
var _to_x := 0.0
var _apex_y := 0.0
var _direction := 1.0
## 이번 점프에서 이미 알린 몸체들.
var _hit: Array[Node2D] = []
## 물보라 하나 = {"x": 맵 x, "age": 초}.
var _splashes: Array[Dictionary] = []


func _ready() -> void:
	_rng.randomize()
	monitorable = false
	_sprite.visible = false
	position = Vector2(MIN_X, UNDERWATER_Y)
	# 맵이 열리자마자 뛰면 무기 고르는 화면 뒤에서 첫 점프가 지나간다 — 한 번 기다리고 뛴다.
	_wait = _rng.randf_range(WAIT_MIN, WAIT_MAX)
	if splash != null:
		splash.draw.connect(_draw_splashes)


func _physics_process(delta: float) -> void:
	_age_splashes(delta)
	if not _leaping:
		# 온라인 클라이언트는 언제 뛸지 스스로 정하지 않는다 (#361) — 기기마다 따로 뽑으면
		# 화면의 물고기와 서버에서 젤리를 미는 물고기가 다른 물고기가 된다. 서버가 뛸 때
		# `_receive_leap` 으로 같은 궤적을 받는다.
		if Network.is_client():
			return
		_wait -= delta
		if _wait <= 0.0:
			_start_leap()
		return
	_t += delta / _duration
	if _t >= 1.0:
		_end_leap()
		return
	_place(_t)
	for body in get_overlapping_bodies():
		if not _hit.has(body):
			_hit.append(body)
			struck.emit(body, _direction)


## 다음 점프를 정해 바로 뛴다. 테스트에서 기다리지 않고 부를 수 있게 공개해 둔다.
func leap_now(from_x: float, to_x: float, apex_y: float, duration: float) -> void:
	_from_x = from_x
	_to_x = to_x
	_apex_y = apex_y
	_duration = maxf(duration, 0.1)
	_direction = signf(to_x - from_x) if to_x != from_x else 1.0
	_t = 0.0
	_hit.clear()
	_leaping = true
	_sprite.visible = true
	_sprite.flip_h = _direction > 0.0  # 원화는 왼쪽을 본다.
	_place(0.0)
	_add_splash(from_x)


func _start_leap() -> void:
	var from_x := _rng.randf_range(MIN_X, MAX_X)
	# 넓은 쪽으로 뛴다 — 가장자리에서 바깥으로 뛰면 거리가 모자라 제자리에서 퐁당한다.
	var direction := 1.0 if from_x < (MIN_X + MAX_X) * 0.5 else -1.0
	var to_x := clampf(from_x + direction * _rng.randf_range(SPAN_MIN, SPAN_MAX), MIN_X, MAX_X)
	var apex_y := _rng.randf_range(APEX_MIN_Y, APEX_MAX_Y)
	var duration := _rng.randf_range(LEAP_TIME_MIN, LEAP_TIME_MAX)
	leap_now(from_x, to_x, apex_y, duration)
	# 전투 화면에 들어온 피어에게만 보낸다 — 경기 사이에 서버가 깔아 둔 임시 맵에도
	# 물고기가 있을 수 있는데, 대기실에 있는 피어에게는 이 노드가 없다.
	if Network.is_server():
		for peer in Lobby.viewers:
			_receive_leap.rpc_id(peer, from_x, to_x, apex_y, duration)


## 서버가 정한 점프 (온라인 클라이언트, #361). 궤적이 같으니 화면의 물고기가 서버의 물고기와 겹친다.
@rpc("authority", "call_remote", "reliable")
func _receive_leap(from_x: float, to_x: float, apex_y: float, duration: float) -> void:
	leap_now(from_x, to_x, apex_y, duration)


func _end_leap() -> void:
	_leaping = false
	_sprite.visible = false
	position = Vector2(_to_x, UNDERWATER_Y)
	_add_splash(_to_x)
	_wait = _rng.randf_range(WAIT_MIN, WAIT_MAX)


func is_leaping() -> bool:
	return _leaping


## 진행도 t(0~1)의 자리와 기울기. 가로는 고르게, 세로는 포물선이다.
## 머리가 늘 날아가는 쪽을 보도록 그 순간의 속도 방향으로 그림을 돌린다.
func _place(t: float) -> void:
	var rise := UNDERWATER_Y - _apex_y
	position = Vector2(lerpf(_from_x, _to_x, t), UNDERWATER_Y - rise * 4.0 * t * (1.0 - t))
	var velocity := Vector2(_to_x - _from_x, -rise * (4.0 - 8.0 * t))
	# 뒤집은 그림(오른쪽을 봄)은 속도 각도 그대로, 안 뒤집은 그림(왼쪽을 봄)은 반대 방향 각도다.
	_sprite.rotation = velocity.angle() if _direction > 0.0 else (-velocity).angle()


func _add_splash(x: float) -> void:
	_splashes.append({"x": x, "age": 0.0})
	if splash != null:
		splash.queue_redraw()


func _age_splashes(delta: float) -> void:
	if _splashes.is_empty():
		return
	for item in _splashes:
		item["age"] += delta
	# filter()는 타입 없는 Array를 돌려주므로 `=`로 받으면 타입이 어긋난다 — assign()으로 담는다.
	_splashes.assign(_splashes.filter(func(item: Dictionary) -> bool: return item["age"] < SPLASH_TIME))
	if splash != null:
		splash.queue_redraw()


## `splash` 노드의 `draw` 신호에서 불린다 — 그 노드 위에 그린다. 물방울이 부채꼴로 튀었다가
## 떨어지며 옅어진다.
func _draw_splashes() -> void:
	for item in _splashes:
		var age: float = item["age"]
		var k := age / SPLASH_TIME
		var color := SPLASH_COLOR
		color.a *= 1.0 - k
		var base := Vector2(item["x"], SURFACE_Y)
		for i in SPLASH_DROPS:
			var spread := lerpf(-0.9, 0.9, float(i) / float(SPLASH_DROPS - 1))
			var launch := Vector2(sin(spread) * 150.0, -cos(spread) * 260.0)
			var pos := base + launch * age + Vector2(0.0, 600.0 * age * age)
			splash.draw_circle(pos, lerpf(7.0, 3.0, k), color)
