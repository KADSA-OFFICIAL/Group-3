extends Node2D
## 대포 총 포탄이 맞은 자리에서 터지는 푸른 충격.
##
## 그림 파일 없이 `_draw()`로만 그린다 — `hit_sparks.gd`·`swap_burst.gd`와 같은 규칙이다.
## **판정과 전혀 얽히지 않는다.** 서버가 명중을 정한 뒤 각 피어가 자기 화면에 띄우고
## (`main.gd`의 `_play_cannon_burst`), 다 재생하면 스스로 `queue_free()`한다.
##
## **가산 혼합을 쓴다** (씬에 `CanvasItemMaterial`). 단검의 빨간 알갱이(#250)가 보통
## 알파 혼합인 것과 반대다 — 저쪽은 "작은 빨간 점"이 요점이라 하얗게 씻기면 안 되지만,
## 이쪽은 흰 알맹이가 타오르는 큰 섬광이라 겹칠수록 밝아져야 한다.
##
## 원점은 **포탄이 닿은 자리**다 (`Projectile.burst`). 번개처럼 발밑으로 내려보내면
## 어디에 맞았는지가 아니라 어디에 서 있었는지가 남는다.
##
## ── 네 겹으로 짠 이유 ──
## 참고한 화면에서 한 발이 맞을 때 일어나는 일은 넷이었고, 넷이 **서로 다른 박자**로
## 움직였다. 하나로 뭉치면 "밝아졌다 꺼지는 원"이 되어 터진 것으로 안 읽힌다.
##   1. 알맹이 섬광 — 가장 먼저, 가장 짧게. 맞은 지점을 못박는다
##   2. 바늘살 — 알맹이와 함께 뻗어 나가 길이로 세기를 보여 준다
##   3. 초승달 충격파 — 뒤늦게 시작해 가장 오래 남으며 밖으로 퍼진다
##   4. 잔 알갱이 — 사방으로 흩어져 처지며 마지막까지 남는다
const DURATION := 0.36

# ─────────────────────────── 1. 알맹이 섬광 ───────────────────────────
## 흰 알맹이의 반지름(px). 젤리 몸통(48px)의 3분의 1 남짓 — 맞은 자리를 덮되 젤리를 가리지 않는다.
const CORE_RADIUS := 18.0
## 알맹이가 살아 있는 시간(초). **전체의 3분의 1도 안 된다** — 섬광은 번쩍이는 것이라
## 오래 남으면 터진 것이 아니라 켜진 것이 된다.
const CORE_TIME := 0.11

# ─────────────────────────── 2. 바늘살 ───────────────────────────
## 사방으로 뻗는 가는 살의 수.
const RAY_COUNT := 9
## 가장 긴 살의 길이(px). 젤리 몸통(48px)보다 길어야 "터졌다"로 읽힌다 — 다만 처음
## 잡은 74 는 좌우로 148px, 젤리 셋 너비여서 터진 자리보다 연출이 커 보였다.
const RAY_LENGTH := 56.0
## 살의 굵기(px).
##
## 4.6 → **7.2**. 가산 혼합에서는 **굵기가 곧 밝기다** — 짙은 파랑(0.16, 0.44, 1.0)을
## 알파 0.7로 얹어도 1px 선이 더하는 빛은 거의 없어서, 처음 그린 것은 터진 것이 아니라
## 긁힌 자국으로 보였다. 미사일 꼬리가 넓은 폴리곤을 세 겹 쌓아 가운데를 태우는 것과
## 같은 이유다(`Projectile._draw`) — 얇은 선을 여러 개 그리는 것으로는 안 된다.
const RAY_WIDTH := 7.2
## 살 안에 얹는 흰 심의 굵기 비율. 0.35 는 4.6px 굵기에서 1.6px 라 눈에 안 남았다.
## 굵기를 7.2 로 올린 뒤에도 그 비율이면 2.5px 라, 비율째로 올려 심이 남게 했다.
const RAY_CORE_RATIO := 0.45
## 살이 다 뻗은 뒤 뿌리부터 지워지기 시작하는 시점(0~1). 끝까지 뿌리가 남아 있으면
## 뻗어 나간 것이 아니라 별 모양 도형이 놓여 있는 것으로 보인다.
const RAY_RETREAT := 0.45
## 살이 살아 있는 시간의 비율(0~1). 초승달보다 먼저 사라진다.
const RAY_LIFE := 0.62

# ─────────────────────────── 3. 초승달 충격파 ───────────────────────────
## 초승달이 뜨기까지의 시간(초). 알맹이보다 **늦게** 시작한다 — 같이 시작하면
## 알맹이에 삼켜져 안 보인다.
const ARC_DELAY := 0.03
## 다 퍼졌을 때의 반지름(px). 알맹이(18)의 두 배 반 남짓 나간다.
const ARC_RADIUS := 48.0
## 처음 반지름의 비율. 0이면 한 점에서 시작해 앞머리가 튀는 것처럼 보인다.
const ARC_START_RATIO := 0.35
## 초승달이 열린 각(라디안). TAU 를 채우면 고리가 되어 폭발이 아니라 파문으로 읽힌다.
const ARC_SPAN := 2.5
## 초승달이 열린 쪽. 참고한 화면에서는 아래쪽으로 휘어 있었다 — 맞은 젤리가
## 뒤로 밀리는 쪽(넉백)과 어긋나지 않게 가로로는 씨앗이 정한다(`_ready()`).
const ARC_BASE_ANGLE := PI * 0.5
## 띠의 두께(px). 처음이 가장 두껍고 퍼지면서 얇아진다.
## 7.0 → **10.0**: 살(RAY_WIDTH)과 같은 이유다 — 가산 혼합에서 얇은 호는 안 보인다.
const ARC_WIDTH := 10.0
## 호를 몇 조각으로 나눠 그릴지. 작으면 각진 다각형이 보인다.
const ARC_SEGMENTS := 20

# ─────────────────────────── 4. 잔 알갱이 ───────────────────────────
const MOTE_COUNT := 10
const MOTE_DISTANCE := 46.0
const MOTE_SIZE := 2.6
## 날아가는 동안 아래로 처지는 정도(px). 곧게만 날면 알갱이가 아니라 도형이 된다
## (`hit_sparks.gd`와 같은 이유·같은 결).
const MOTE_DROOP := 26.0

## 가운데는 하얗고 바깥으로 갈수록 파랗다 — 날아온 구슬(`Projectile.ORB_*`)과 같은 색이라
## "저 파란 포탄이 터진 것"으로 이어 읽힌다. 색이 갈라지면 다른 무기의 연출로 보인다.
const CORE_COLOR := Color(1.0, 1.0, 1.0)
const MID_COLOR := Color(0.62, 0.88, 1.0)
const EDGE_COLOR := Color(0.16, 0.44, 1.0)

var _elapsed := 0.0
var _rays: Array[Dictionary] = []
var _motes: Array[Dictionary] = []
var _arc_angle := ARC_BASE_ANGLE


func _ready() -> void:
	# 양쪽 화면에 같은 모양이 뜨도록 위치로 씨앗을 잡는다 (`hit_sparks.gd`와 같은 방식).
	# **`main.gd`가 위치를 먼저 넣고 붙이는 것이 이 씨앗의 전제다** — 나중에 넣으면
	# 모든 피격이 (0, 0)으로 같은 모양이 된다.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))
	for i in RAY_COUNT:
		# 고르게 두른 뒤 조금씩 흔든다. 완전 무작위로 뽑으면 한쪽에 뭉친다.
		var angle := TAU * float(i) / float(RAY_COUNT) + rng.randf_range(-0.28, 0.28)
		_rays.append({
			"dir": Vector2.RIGHT.rotated(angle),
			# **길이를 크게 흩는다.** 다 같으면 별표(✳) 도형이 되고, 들쭉날쭉해야
			# 터져서 튄 것으로 읽힌다 — 참고한 화면에서 가장 눈에 띈 점이 이것이었다.
			"length": RAY_LENGTH * rng.randf_range(0.38, 1.0),
			"width": RAY_WIDTH * rng.randf_range(0.55, 1.0),
		})
	for i in MOTE_COUNT:
		var angle := TAU * float(i) / float(MOTE_COUNT) + rng.randf_range(-0.3, 0.3)
		_motes.append({
			"dir": Vector2.RIGHT.rotated(angle),
			"distance": MOTE_DISTANCE * rng.randf_range(0.4, 1.0),
			"size": MOTE_SIZE * rng.randf_range(0.6, 1.0),
		})
	# 초승달이 좌우 어느 쪽으로 휘는지만 씨앗이 정한다. 아래로 휘는 것은 고정이다.
	_arc_angle = ARC_BASE_ANGLE + rng.randf_range(-0.5, 0.5)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_elapsed / DURATION, 0.0, 1.0)
	_draw_arc_wave(t)
	_draw_rays(t)
	_draw_core()
	_draw_motes(t)


## 1. 알맹이 섬광. 크게 떴다가 줄어들며 꺼진다 — 커지면서 꺼지면 연기처럼 보인다.
func _draw_core() -> void:
	if _elapsed >= CORE_TIME:
		return
	var life := 1.0 - _elapsed / CORE_TIME
	var radius := CORE_RADIUS * (0.45 + 0.55 * life)
	Art.draw_glow(self, Vector2.ZERO, radius * 1.9, EDGE_COLOR, 0.5 * life)
	draw_circle(Vector2.ZERO, radius, Color(MID_COLOR, 0.75 * life))
	draw_circle(Vector2.ZERO, radius * 0.5, Color(CORE_COLOR, 0.95 * life))


## 2. 바늘살. 뻗는 것은 빠르게 시작해 느려지고(감속), 뿌리는 뒤늦게 물러난다.
func _draw_rays(t: float) -> void:
	if t >= RAY_LIFE:
		return
	var local := t / RAY_LIFE
	# 감속. 등속으로 뻗으면 자라나는 것으로 보인다.
	var reach := 1.0 - (1.0 - local) * (1.0 - local)
	# 뿌리가 물러나는 정도. RAY_RETREAT 전에는 0 이라 살이 알맹이에 붙어 있다.
	var root := 0.0
	if local > RAY_RETREAT:
		root = (local - RAY_RETREAT) / (1.0 - RAY_RETREAT)
	var fade := 1.0 - local * local
	for ray in _rays:
		var dir: Vector2 = ray["dir"]
		var far: float = float(ray["length"]) * reach
		var near := far * root
		var width: float = float(ray["width"]) * (0.35 + 0.65 * fade)
		# 넓고 파란 것 → 좁고 하늘색 → 가는 흰 심. 미사일 꼬리와 같은 세 겹이다.
		draw_line(dir * near, dir * far, Color(EDGE_COLOR, 0.85 * fade), width)
		draw_line(dir * near, dir * far, Color(MID_COLOR, 0.8 * fade), width * 0.7)
		draw_line(dir * near, dir * far, Color(CORE_COLOR, 0.95 * fade),
			width * RAY_CORE_RATIO)


## 3. 초승달 충격파. 퍼지면서 얇아지고, 넷 중 **가장 오래** 남는다.
func _draw_arc_wave(t: float) -> void:
	if _elapsed < ARC_DELAY:
		return
	var local := clampf((_elapsed - ARC_DELAY) / (DURATION - ARC_DELAY), 0.0, 1.0)
	# 감속하며 퍼진다 — 충격파는 처음이 가장 빠르다.
	var grow := 1.0 - (1.0 - local) * (1.0 - local)
	var radius := ARC_RADIUS * (ARC_START_RATIO + (1.0 - ARC_START_RATIO) * grow)
	var width := ARC_WIDTH * (1.0 - 0.7 * local)
	var fade := (1.0 - local) * (1.0 - local)
	# 바깥의 파란 띠와 그 안의 가는 하늘색 심. 살과 같은 세 겹 짜임이다.
	draw_arc(Vector2.ZERO, radius, _arc_angle - ARC_SPAN * 0.5, _arc_angle + ARC_SPAN * 0.5,
		ARC_SEGMENTS, Color(EDGE_COLOR, 0.9 * fade), width)
	draw_arc(Vector2.ZERO, radius, _arc_angle - ARC_SPAN * 0.45, _arc_angle + ARC_SPAN * 0.45,
		ARC_SEGMENTS, Color(MID_COLOR, 0.8 * fade), width * 0.5)
	draw_arc(Vector2.ZERO, radius, _arc_angle - ARC_SPAN * 0.36, _arc_angle + ARC_SPAN * 0.36,
		ARC_SEGMENTS, Color(CORE_COLOR, 0.7 * fade), width * 0.2)


## 4. 잔 알갱이. 흩어져 처지며 끝에서만 빠르게 사라진다 (`hit_sparks.gd`와 같은 감쇠).
func _draw_motes(t: float) -> void:
	var reach := 1.0 - (1.0 - t) * (1.0 - t)
	var fade := 1.0 - t * t
	for mote in _motes:
		var dir: Vector2 = mote["dir"]
		var flown: float = float(mote["distance"]) * reach
		var at := dir * flown + Vector2(0.0, MOTE_DROOP * t * t)
		var size: float = float(mote["size"]) * (0.5 + 0.5 * fade)
		draw_circle(at, size * 1.8, Color(EDGE_COLOR, 0.5 * fade))
		draw_circle(at, size, Color(CORE_COLOR, 0.85 * fade))
