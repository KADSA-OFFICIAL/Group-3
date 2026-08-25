extends Node2D
## 양날 도끼가 착지할 때 **좌우로 갈라져 나가는 땅** (#167).
##
## `light_burst.gd`(검)·`lightning_strike.gd`(삼지창)와 같은 규칙이다 — 그림 파일 없이
## `_draw()`로만 그리고, 노드에 가산 혼합이 걸려 있어 겹칠수록 하얘진다.
## **판정과 전혀 얽히지 않는다.** 서버가 착지를 정한 뒤 각 피어가 자기 화면에 띄우고
## (`main.gd`의 `_play_shockwave`), 다 재생하면 스스로 `queue_free()`한다.
##
## **이 연출이 없으면 안 되는 이유**: 착지 데미지는 눈에 보이는 것이 하나도 없다.
## 맞는 쪽은 도끼가 옆에 떨어졌을 뿐인데 체력이 줄어서 왜 맞았는지 알 수 없고, 쓰는 쪽은
## 얼마나 가까이 떨어뜨려야 하는지 알 수 없다. 폭탄 반경을 화면에 그린 이유(#140)와 같다.
##
## **고리가 아니라 좌우로 뻗는 두 줄이다.** 판정도 가로 거리로만 재기 때문이다
## (`main.gd`의 `_tick_ruptures()`) — 원으로 그리면 위아래도 맞을 것처럼 보인다.
##
## 원점은 **떨어진 자리(발밑)**다. `radius`와 `speed`는 판정에 쓰는 값 그대로 넘어온다:
## 앞선이 화면에서 가 있는 곳이 곧 지금 맞는 경계다. 둘이 따로 놀면 이 연출은
## 오히려 거짓말이 된다.

## 앞선이 끝까지 간 뒤 옅어지는 데 쓰는 시간(초).
const FADE_TIME := 0.26
## 갈라진 틈의 두께(px). 앞선 쪽이 두껍고 원점 쪽으로 갈수록 얇아진다.
const CRACK_WIDTH := 12.0
## 틈을 그릴 때 위아래로 흔드는 폭(px). 직선으로 그으면 자석 자국처럼 보인다.
const JAG := 8.0
## 틈 한 줄을 몇 토막으로 꺾어 그릴지. 많을수록 잘게 갈라진다.
const JAG_STEPS := 9
## 솟아오르는 돌조각 수(한쪽당)와 그 밑변·높이(px).
const SHARD_COUNT := 7
const SHARD_BASE := 24.0
const SHARD_HEIGHT := 46.0
## 돌조각이 솟았다 가라앉는 데 걸리는 시간(초). 앞선이 지나간 자리부터 센다.
const SHARD_LIFE := 0.28
## 앞선에 붙어 터지는 흙먼지의 크기(px).
const DUST_RADIUS := 18.0

## 도끼 날의 붉은색에 맞춘다 — 무엇이 떨어져서 생긴 것인지 색으로 읽히게 한다.
const CRACK_COLOR := Color(1.0, 0.45, 0.32)
const CORE_COLOR := Color(1.0, 0.92, 0.86)

## 좌우로 각각 뻗는 거리(px). `main.gd`가 무기 표의 `landing_radius`를 그대로 넘긴다.
var radius := 160.0
## 앞선이 뻗어 나가는 속도(px/s). 무기 표의 `landing_rupture_speed` 그대로다.
var speed := 900.0

var _elapsed := 0.0
## 돌조각. `at`은 원점에서의 거리 비율(0~1), `side`는 -1/+1이다.
var _shards: Array[Dictionary] = []


func _ready() -> void:
	# 모양은 노드 이름으로 씨앗을 잡은 난수라 **양쪽 화면에 같게** 뜬다.
	# 이름은 각 피어가 같은 순서로 붙이므로 같다.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for side in [-1.0, 1.0]:
		for i in SHARD_COUNT:
			_shards.append({
				# 원점에 붙지 않게 0.12 부터 둔다 — 발밑은 젤리가 가린다.
				"at": rng.randf_range(0.12, 1.0),
				"side": side,
				"size": rng.randf_range(0.55, 1.0),
				"lean": rng.randf_range(-0.35, 0.35),
			})


## 앞선이 끝까지 가는 데 걸리는 시간. 판정과 같은 값에서 나온다.
func _travel_time() -> float:
	if speed <= 0.0:
		return 0.0
	return radius / speed


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _travel_time() + FADE_TIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var front := minf(_elapsed * speed, radius)
	if front <= 1.0:
		return
	# 앞선이 끝까지 간 뒤부터 옅어진다 — 가는 동안은 진하게 남아 있어야 앞선이 보인다.
	var over := maxf(_elapsed - _travel_time(), 0.0)
	var fade := 1.0 - clampf(over / FADE_TIME, 0.0, 1.0)

	for side in [-1.0, 1.0]:
		_draw_crack(side, front, fade)
		# 앞선 머리의 흙먼지 — 여기가 지금 맞는 경계다.
		Art.draw_glow(self, Vector2(side * front, 0.0), DUST_RADIUS, CORE_COLOR, 0.55 * fade)
		Art.draw_glow(self, Vector2(side * front, 0.0), DUST_RADIUS * 1.9, CRACK_COLOR, 0.6 * fade)

	for shard: Dictionary in _shards:
		_draw_shard(shard, front, fade)


## 원점에서 앞선까지 이어지는 갈라진 틈 한 줄. 앞선 쪽이 두껍다.
func _draw_crack(side: float, front: float, fade: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) + int(side)   # 흔들림도 양쪽 화면에 같게
	var previous := Vector2.ZERO
	for step in range(1, JAG_STEPS + 1):
		var ratio := float(step) / float(JAG_STEPS)
		var point := Vector2(side * front * ratio, rng.randf_range(-JAG, JAG))
		if step == JAG_STEPS:
			point.y = 0.0   # 앞선 머리는 흙먼지와 맞춰 바닥에 둔다
		# 원점 쪽은 얇고 앞선 쪽이 두껍다 — 갈라짐이 앞으로 밀려 나가는 것으로 읽힌다.
		var width := CRACK_WIDTH * (0.35 + 0.65 * ratio) * fade
		draw_line(previous, point, Color(CRACK_COLOR, 0.9 * fade), width, true)
		if step > 1:
			draw_line(previous, point, Color(CORE_COLOR, 0.4 * fade), width * 0.4, true)
		previous = point


## 솟아오르는 돌조각 하나. **앞선이 지나간 뒤에** 솟았다 가라앉는다.
func _draw_shard(shard: Dictionary, front: float, fade: float) -> void:
	var at: float = shard["at"]
	var side: float = shard["side"]
	var x := side * radius * at
	if absf(x) > front:
		return   # 앞선이 아직 여기까지 안 왔다
	# 앞선이 지나간 뒤로 흐른 시간. 그만큼 솟았다 가라앉는다.
	var age := (front - absf(x)) / maxf(speed, 1.0)
	var life := clampf(age / SHARD_LIFE, 0.0, 1.0)
	var rise := sin(PI * life)           # 올라갔다 내려온다
	if rise <= 0.01:
		return
	var size: float = shard["size"]
	var lean: float = shard["lean"]
	var half := SHARD_BASE * size * 0.5
	var tip := -SHARD_HEIGHT * size * rise
	# 위로 삐죽한 삼각형. 밑변은 바닥에 붙어 있고 꼭대기만 솟는다.
	var points := PackedVector2Array([
		Vector2(x - half, 0.0),
		Vector2(x + half, 0.0),
		Vector2(x + tip * lean, tip),
	])
	draw_colored_polygon(points, Color(CRACK_COLOR, 0.75 * fade))
	# 꼭대기에 밝은 점을 얹어 돌부리로 읽히게 한다.
	Art.draw_glow(self, Vector2(x + tip * lean, tip), 5.0 * size, CORE_COLOR, 0.5 * fade)
