extends Node2D
## 폭탄이 터지는 순간의 폭발 (#262).
##
## 그림 파일 없이 `_draw()`로만 그린다 — `cannon_burst.gd`·`hit_sparks.gd`·`swap_burst.gd`와
## 같은 규칙이다. **판정과 전혀 얽히지 않는다.** 서버가 폭발을 정한 뒤 각 피어가 자기 화면에
## 띄우고(`main.gd`의 `_play_bomb_blast`), 다 재생하면 스스로 `queue_free()`한다.
##
## **이 연출이 없으면 안 되는 이유**: 폭탄은 닿지 않아도 맞는 유일한 무기인데, 터지는
## 순간 화면에서 일어나는 일이 "폭탄 그림이 사라진다"뿐이었다. 맞는 쪽은 왜 32(강화 48)이
## 줄었는지 볼 것이 없고, 쓰는 쪽은 얼마나 가까이 던져야 하는지 배울 것이 없다.
## 반경 표시(#140)·착지 충격파(#167)와 같은 문제이고 같은 답이다.
##
## ── 참고한 화면에서 가져온 것 ──
## 사용자가 준 영상에서 한 번 터질 때 일어나는 일은 넷이었고 **서로 다른 박자**로 움직였다.
##   1. 알맹이 섬광 — 가장 먼저, 가장 짧게. 터진 지점을 못박는다
##   2. 불꽃살 — 가늘고 길게 사방으로 내뻗는다. 이 연출에서 가장 눈에 띄는 것이 이것이다
##   3. 충격 고리 — 뒤늦게 시작해 **판정 반경까지 정확히** 퍼진다
##   4. 잔 불티 — 흩어져 처지며 마지막까지 남는다
## 넓게 번지는 빛(`_draw_bloom`)은 그 넷을 한 폭발로 묶어 주는 바탕이다.
##
## **가산 혼합을 쓰지 않는다** (씬에 `CanvasItemMaterial`이 없다). 대포 총 폭발
## (`cannon_burst.gd`)과 갈리는 점이고, 이유는 크기다 — 가산은 밝게만 만들 수 있어서
## 평지 하늘(0.82, 0.93, 0.99)처럼 이미 흰 배경 위에서는 주황이 하얗게 씻겨 사라진다
## (#112·#146). 48px짜리 알맹이라면 그래도 흰 심이 남지만, 이것은 지름 400px이라
## **화면 절반이 통째로 안 보이는 일**이 된다. 반경 표시(`blast_radius.gd`)가 보통 알파를
## 고른 것과 같은 판단이고, 실제로 그 원과 같은 자리에 그려지므로 결이 맞아야 한다.
##
## 원점은 **폭탄이 터진 자리**다 (`Projectile._explode()`가 자기 `position`을 싣는다).

## 연출 전체가 사는 시간(초). 대포 총 폭발(0.36)보다 길다 — 반경이 네 배라 같은 시간에
## 퍼지면 눈으로 좇을 수 없는 속도가 된다.
const DURATION := 0.55

# ─────────────────────────── 1. 알맹이 섬광 ───────────────────────────
## 흰 알맹이의 반지름 (판정 반경에 대한 비율). 200px 반경에서 32px — 젤리 몸통(48px)의
## 3분의 2라, 터진 자리를 못박되 그 자리에 있던 젤리를 통째로 가리지는 않는다.
const CORE_RATIO := 0.16
## 알맹이가 살아 있는 시간(초). **전체의 4분의 1도 안 된다** — 섬광은 번쩍이는 것이라
## 오래 남으면 터진 것이 아니라 켜진 것이 된다.
const CORE_TIME := 0.13

# ─────────────────────────── 2. 불꽃살 ───────────────────────────
## 사방으로 내뻗는 살의 수. 참고한 화면은 열 갈래 남짓이었다 — 적으면 별표(✳) 도형이
## 되고, 많으면 살이 아니라 꽉 찬 원이 된다.
const RAY_COUNT := 11
## 가장 긴 살이 닿는 거리 (판정 반경에 대한 비율). **1.0을 넘기지 않는다** —
## 판정 밖까지 불이 뻗으면 "저기 서 있어도 맞나" 하는 거짓말이 된다.
const RAY_REACH := 0.96
## 살의 굵기(px). 참고한 화면의 요점이 **가늘고 길다**는 것이라, 반경에 비례시키지 않고
## 고정으로 둔다 — 비례시키면 200px 반경에서 뭉툭한 삼각형이 된다.
const RAY_WIDTH := 13.0
## 살 안에 얹는 흰 심의 굵기 비율.
const RAY_CORE_RATIO := 0.4
## 살 **끝**의 굵기 비율(뿌리에 대한). 0이면 완전한 삼각형인데, 그러면 끝이 한 점으로
## 모여 안티에일리어싱 없이 지저분해진다 — 조금 남겨 두면 바늘처럼 보인다.
const RAY_TIP_RATIO := 0.12
## 살이 다 뻗은 뒤 **뿌리부터** 지워지기 시작하는 시점(0~1). 끝까지 뿌리가 남아 있으면
## 뻗어 나간 것이 아니라 별 모양 도형이 놓여 있는 것으로 보인다.
const RAY_RETREAT := 0.42
## 살이 살아 있는 시간의 비율(0~1). 고리보다 먼저 사라진다.
const RAY_LIFE := 0.66

# ─────────────────────────── 3. 충격 고리 ───────────────────────────
## 고리가 뜨기까지의 시간(초). 알맹이보다 **늦게** 시작한다 — 같이 시작하면 알맹이에
## 삼켜져 안 보인다.
const RING_DELAY := 0.04
## 고리가 판정 반경에 닿는 시점(0~1). 여기서부터 끝까지는 그 자리에서 옅어지기만 한다 —
## **경계를 보여 주는 것이 이 고리의 일이라, 닿은 자리에 잠깐 머물러야 눈에 남는다.**
const RING_ARRIVE := 0.55
## 처음 반지름의 비율. 0이면 한 점에서 시작해 앞머리가 튀는 것처럼 보인다.
const RING_START_RATIO := 0.2
## 띠의 두께(px). 처음이 가장 두껍고 퍼지면서 얇아진다.
const RING_WIDTH := 14.0
## 고리를 몇 조각으로 나눠 그릴지. 200px 반지름에서 이 정도면 각진 데가 안 보인다.
const RING_SEGMENTS := 64

# ─────────────────────────── 4. 잔 불티 ───────────────────────────
const MOTE_COUNT := 18
## 불티가 날아가는 거리 (판정 반경에 대한 비율). 살보다 조금 더 나간다 — 터져서 튄
## 것이라 경계에 얽매이지 않는다.
const MOTE_REACH := 1.08
const MOTE_SIZE := 3.4
## 날아가는 동안 아래로 처지는 정도(px). 곧게만 날면 불티가 아니라 도형이 된다
## (`hit_sparks.gd`·`cannon_burst.gd`와 같은 이유·같은 결).
const MOTE_DROOP := 60.0

# ─────────────────────────── 바탕 빛 ───────────────────────────
## 번지는 빛이 닿는 거리 (판정 반경에 대한 비율).
const BLOOM_RATIO := 0.78
## 가장 진할 때의 옅기. **옅어야 한다** — 진하면 반경 안의 지형과 젤리가 통째로 묻힌다
## (반경 표시의 채움을 0.16으로 잡은 것과 같은 이유).
const BLOOM_ALPHA := 0.34
## 빛이 가장 진해지는 시점(0~1). 터지자마자가 아니라 아주 조금 뒤다.
const BLOOM_PEAK := 0.12

## 가운데는 하얗고 바깥으로 갈수록 붉다.
##
## **`blast_radius.gd`의 경계색과 같은 주황이다** — 터지기 전에 그 색 원으로 "여기까지
## 맞는다"를 배웠는데 터질 때 다른 색이 나오면 둘이 이어지지 않는다. 같은 자리에 같은
## 색으로 터져야 "아까 그 원이 이렇게 됐다"로 읽힌다.
const CORE_COLOR := Color(1.0, 1.0, 1.0)
const MID_COLOR := Color(1.0, 0.82, 0.35)
const EDGE_COLOR := Color(1.0, 0.42, 0.24)

## 폭발 반경(px). `main.gd`가 판정에 쓰는 `explosion_radius`를 그대로 넘긴다 —
## 보이는 것과 맞는 범위가 어긋나면 이 연출이 거짓말이 된다.
var radius := 200.0

var _elapsed := 0.0
var _rays: Array[Dictionary] = []
var _motes: Array[Dictionary] = []


func _ready() -> void:
	# 양쪽 화면에 같은 모양이 뜨도록 위치로 씨앗을 잡는다 (`cannon_burst.gd`와 같은 방식).
	# **`main.gd`가 위치를 먼저 넣고 붙이는 것이 이 씨앗의 전제다** — 나중에 넣으면
	# 모든 폭발이 (0, 0)으로 같은 모양이 된다.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))
	for i in RAY_COUNT:
		# 고르게 두른 뒤 조금씩 흔든다. 완전 무작위로 뽑으면 한쪽에 뭉친다.
		var angle := TAU * float(i) / float(RAY_COUNT) + rng.randf_range(-0.22, 0.22)
		_rays.append({
			"dir": Vector2.RIGHT.rotated(angle),
			# **길이를 크게 흩는다.** 다 같으면 별표 도형이 되고, 들쭉날쭉해야 터져서
			# 튄 것으로 읽힌다 — 참고한 화면에서 가장 눈에 띈 점이 이것이었다.
			"reach": rng.randf_range(0.5, 1.0),
			"width": rng.randf_range(0.5, 1.0),
		})
	for i in MOTE_COUNT:
		var angle := TAU * float(i) / float(MOTE_COUNT) + rng.randf_range(-0.24, 0.24)
		_motes.append({
			"dir": Vector2.RIGHT.rotated(angle),
			"reach": rng.randf_range(0.42, 1.0),
			"size": MOTE_SIZE * rng.randf_range(0.55, 1.0),
		})


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_elapsed / DURATION, 0.0, 1.0)
	# 그리는 순서가 곧 쌓이는 순서다 — 바탕 빛 위에 고리, 그 위에 살, 그 위에 알맹이.
	_draw_bloom(t)
	_draw_ring()
	_draw_rays(t)
	_draw_core()
	_draw_motes(t)


## 바탕 — 반경 안을 넓게 물들이는 빛. 넷을 한 폭발로 묶는다.
##
## 빠르게 진해졌다 천천히 옅어진다. 반대로 하면 터진 것이 아니라 불이 켜지는 것으로 보인다.
func _draw_bloom(t: float) -> void:
	var strength := 0.0
	if t < BLOOM_PEAK:
		strength = t / BLOOM_PEAK
	else:
		var fall := (t - BLOOM_PEAK) / (1.0 - BLOOM_PEAK)
		strength = (1.0 - fall) * (1.0 - fall)
	if strength <= 0.0:
		return
	Art.draw_glow(self, Vector2.ZERO, radius * BLOOM_RATIO, EDGE_COLOR,
		BLOOM_ALPHA * strength)
	Art.draw_glow(self, Vector2.ZERO, radius * BLOOM_RATIO * 0.45, MID_COLOR,
		BLOOM_ALPHA * 0.7 * strength)


## 1. 알맹이 섬광. 크게 떴다가 줄어들며 꺼진다 — 커지면서 꺼지면 연기처럼 보인다.
func _draw_core() -> void:
	if _elapsed >= CORE_TIME:
		return
	var life := 1.0 - _elapsed / CORE_TIME
	var core := radius * CORE_RATIO * (0.5 + 0.5 * life)
	Art.draw_glow(self, Vector2.ZERO, core * 2.4, MID_COLOR, 0.55 * life)
	draw_circle(Vector2.ZERO, core, Color(MID_COLOR, 0.9 * life))
	draw_circle(Vector2.ZERO, core * 0.55, Color(CORE_COLOR, 1.0 * life))


## 2. 불꽃살. 뻗는 것은 빠르게 시작해 느려지고(감속), 뿌리는 뒤늦게 물러난다.
func _draw_rays(t: float) -> void:
	if t >= RAY_LIFE:
		return
	var local := t / RAY_LIFE
	# 감속. 등속으로 뻗으면 자라나는 것으로 보인다.
	var reach := 1.0 - (1.0 - local) * (1.0 - local)
	# 뿌리가 물러나는 정도. `RAY_RETREAT` 전에는 0이라 살이 알맹이에 붙어 있다.
	var root := 0.0
	if local > RAY_RETREAT:
		root = (local - RAY_RETREAT) / (1.0 - RAY_RETREAT)
	var fade := 1.0 - local * local
	for ray in _rays:
		var dir: Vector2 = ray["dir"]
		var far: float = radius * RAY_REACH * float(ray["reach"]) * reach
		var near := far * root
		var width: float = RAY_WIDTH * float(ray["width"]) * (0.3 + 0.7 * fade)
		# 넓고 붉은 것 → 좁고 노란 것 → 가는 흰 심. 대포 총 살과 같은 세 겹이다.
		_needle(dir, near, far, width, Color(EDGE_COLOR, 0.85 * fade))
		_needle(dir, near, far, width * 0.66, Color(MID_COLOR, 0.8 * fade))
		_needle(dir, near, far, width * RAY_CORE_RATIO, Color(CORE_COLOR, 0.9 * fade))


## 살 한 겹 — **뿌리가 넓고 끝이 뾰족한 바늘**.
##
## `draw_line`으로 그리면 굵기가 일정해서 끝이 뭉툭한 막대가 되고, 열한 개가 놓이면
## 터진 것이 아니라 도미노를 늘어놓은 것으로 보인다. 참고한 화면에서 가장 눈에 띈 것이
## "가늘고 길게 내뻗는다"였고, 그 인상은 굵기가 끝으로 갈수록 줄어드는 데서 온다.
func _needle(dir: Vector2, near: float, far: float, width: float, color: Color) -> void:
	if far <= near or width <= 0.0:
		return
	var perp := dir.orthogonal()
	var root := width * 0.5
	var tip := root * RAY_TIP_RATIO
	draw_colored_polygon(PackedVector2Array([
		dir * near + perp * root,
		dir * far + perp * tip,
		dir * far - perp * tip,
		dir * near - perp * root,
	]), color)


## 3. 충격 고리. **판정 반경에 정확히 닿고**, 닿은 뒤에는 그 자리에서 옅어진다.
##
## 이 연출에서 유일하게 "얼마나 맞는가"를 말하는 겹이라, 크기가 수치에서 나온다.
func _draw_ring() -> void:
	if _elapsed < RING_DELAY:
		return
	var local := clampf((_elapsed - RING_DELAY) / (DURATION - RING_DELAY), 0.0, 1.0)
	# 퍼지는 구간과 머무는 구간을 나눈다.
	var grow := clampf(local / RING_ARRIVE, 0.0, 1.0)
	# 감속하며 퍼진다 — 충격파는 처음이 가장 빠르다.
	grow = 1.0 - (1.0 - grow) * (1.0 - grow)
	var ring := radius * (RING_START_RATIO + (1.0 - RING_START_RATIO) * grow)
	var width := RING_WIDTH * (1.0 - 0.72 * local)
	var fade := (1.0 - local) * (1.0 - local)
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, RING_SEGMENTS,
		Color(EDGE_COLOR, 0.9 * fade), width, true)
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, RING_SEGMENTS,
		Color(MID_COLOR, 0.75 * fade), width * 0.45, true)


## 4. 잔 불티. 흩어져 처지며 끝에서만 빠르게 사라진다 (`hit_sparks.gd`와 같은 감쇠).
func _draw_motes(t: float) -> void:
	var reach := 1.0 - (1.0 - t) * (1.0 - t)
	var fade := 1.0 - t * t
	for mote in _motes:
		var dir: Vector2 = mote["dir"]
		var flown: float = radius * MOTE_REACH * float(mote["reach"]) * reach
		var at := dir * flown + Vector2(0.0, MOTE_DROOP * t * t)
		var size: float = float(mote["size"]) * (0.45 + 0.55 * fade)
		draw_circle(at, size * 1.9, Color(EDGE_COLOR, 0.55 * fade))
		draw_circle(at, size, Color(MID_COLOR, 0.9 * fade))
