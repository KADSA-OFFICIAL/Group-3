class_name ChainsawWhirl
extends Node2D
## 전기톱 특수의 연출 — 도는 톱날이 그리는 원과, 돌진하며 가르는 바람 (#260).
##
## 특수가 두 단계라서 이 노드도 두 가지를 그린다.
## **제자리 회전("spin")** 동안에는 톱날 끝이 지나간 자리를 원호로 남긴다 — 손에 든
## 그림만 돌면 빠르게 도는 것인지 그냥 기울어진 것인지 읽히지 않는다.
## **돌진("dash")** 동안에는 거기에 더해 젤리 뒤로 흐르는 바람 줄무늬를 그린다 —
## 돌진 속도가 일반 이동의 3.5배(1120px/s)인데 화면에는 젤리가 미끄러지는 것 말고
## 빠르다는 표시가 없었다.
##
## **왜 별도 노드인가**: 씬 루트(`player.tscn`)의 `_draw()`는 자식 스프라이트보다 먼저
## 그려져 젤리 뒤에 깔리고(관통 빛무리가 그 자리를 쓴다), 루트에는 가산 혼합이 걸려 있어
## 밝은 맵에서 옅은 회색이 통째로 사라진다(#112·#146). 잔상(`weapon_trail.gd`)과 같은
## 사정이고, 이 노드도 같은 이유로 **혼합이 걸리지 않은 자식**이다.
##
## 노드 순서상 `WeaponSprite` **앞**에 있어서 원호와 바람이 톱 밑에 깔린다. 위에 그리면
## 지금 든 톱이 지나간 자리에 가려서 어느 것이 지금인지 읽히지 않는다.
## **`z_index`로 올리거나 내리지 않는다** — 맵이 z 0에 깔아 둔 배경과 순서가 어긋난다(#146).
##
## **복제할 것이 없다.** 자리는 이미 복제되는 `position`·`facing`에서 나오고, 도는 각도는
## 복제된 강제 이동 시각(`Player._spin_started_at`)에서 각 피어가 자기 시계로 계산한다 —
## 연기·잔상·찌그러짐과 같은 방식이라 RPC가 늘지 않는다(버전 악수 #228에 영향 없음).
##
## 켜고 끄는 것·중심·반지름·각도는 부모(`Player._update_chainsaw_whirl()`)가 정한다.

## 톱날이 지나간 자리로 남기는 원호의 수. 하나면 남은 자리가 아니라 그냥 호가 되고,
## 많으면 원이 통째로 채워져 도는 것이 안 보인다.
const ARC_COUNT := 4
## 원호 하나가 훑는 각의 폭(라디안). 넷을 이으면 약 2.3rad — 원의 3분의 1이 조금 넘어
## "방금 여기를 지나갔다"로 읽히고, 남은 3분의 2가 비어 있어 도는 것이 보인다.
const ARC_SPAN := 0.58
## 가장 진한 원호의 굵기(px)와 옅기. 톱날(화면에서 약 80x30px)보다 가늘게 잡는다 —
## 굵으면 원호가 무기처럼 보인다.
const ARC_WIDTH := 5.5
const ARC_ALPHA := 0.5
## 원호를 몇 도막으로 나눠 그릴지. 적으면 원이 각져 보인다.
const ARC_POINTS := 10

## 톱날 색에 맞춘 은회색. 원화의 날이 이 색이라, 다른 색으로 남기면 무엇이
## 지나간 자리인지 읽히지 않는다 (`weapon_trail.gd`의 민트와 같은 판단이다).
const BLADE_COLOR := Color(0.88, 0.89, 0.92)

## 바람 줄무늬를 하나 남기는 간격(초). 돌진은 길어도 1초 남짓이라 이 간격이면
## 화면에 여남은 줄이 흐른다.
const WIND_INTERVAL := 0.024
## 줄무늬 하나가 남아 있는 시간(초). 길면 돌진이 끝난 뒤에도 자리에 남아 "지금 어디
## 있나"가 흐려진다.
const WIND_LIFETIME := 0.26
## 줄무늬 길이의 범위(px)와 굵기(px).
const WIND_LENGTH_MIN := 34.0
const WIND_LENGTH_MAX := 78.0
const WIND_WIDTH := 2.6
## 줄무늬가 뿌려지는 세로 범위(px, 발밑이 0이고 위가 음수). 몸(48x72)의 위아래로
## 조금 넘겨 잡아 바람이 젤리를 스치고 지나가는 것으로 보이게 한다.
const WIND_TOP := -78.0
const WIND_BOTTOM := 6.0
## 가장 진한 줄무늬의 옅기. **옅어야 한다** — 진하면 바람이 아니라 빛줄기로 보인다.
const WIND_ALPHA := 0.42

## 바람 색. 날 색보다 조금 푸르다 — 같은 색이면 톱이 남긴 자리와 구분이 안 된다.
const WIND_COLOR := Color(0.86, 0.92, 1.0)

## 지금 톱이 돌고 있는가. 부모가 매 프레임 맞춘다.
##
## **꺼져도 노드를 숨기지 않는다** — 돌진이 끝나는 순간 뒤에 흐르던 바람까지 같이
## 사라지면 젤리가 멈춘 것이 아니라 연출이 잘린 것으로 보인다. 꺼진 뒤에는 원호만
## 그만 그리고 남은 줄무늬는 제 수명대로 옅어진다.
var active := false

## 지금 돌진 중인가 (제자리 회전 중이면 false). 바람 줄무늬는 이때만 난다.
var dashing := false
## 톱을 쥔 자리 (부모 기준 지역 좌표). 원호의 중심이다.
var pivot := Vector2.ZERO
## 톱날 끝이 지금 있는 각(라디안). 부모가 도는 각도에서 계산해 넣는다.
var tip_angle := 0.0
## 원호의 반지름(px) — 화면에 그려진 톱날 끝까지의 거리다.
var radius := 40.0
## 도는 쪽 (1 시계방향 / -1 반시계방향). 원호는 지나온 쪽, 즉 반대편에 남는다.
var spin_sign := 1.0
## 바람이 흐르는 쪽 (1 오른쪽 / -1 왼쪽). 젤리가 가는 쪽의 반대다.
var wind_sign := -1.0

## 남아 있는 바람 줄무늬. 각 항목은 시작점(**전역 좌표**)과 길이·나이다.
##
## 전역으로 들고 있다가 그릴 때 지역으로 되돌린다 — 이 노드는 젤리에 붙어 함께
## 움직이므로 지역으로 들고 있으면 바람이 젤리를 따라와서 흐르지 않는다
## (`weapon_trail.gd`가 잔상을 그렇게 든다).
var _winds: Array[Dictionary] = []
var _next_wind := 0.0
var _elapsed := 0.0
var _rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	if not active and _winds.is_empty():
		return
	_elapsed += delta
	if active and dashing and _elapsed >= _next_wind:
		_spawn_wind()
	_age_winds(delta)
	queue_redraw()


## 들고 있는 바람 줄무늬를 통째로 버린다. 순간이동·라운드 초기화·무기 교체에서
## 부모가 부른다 — 안 버리면 옛 자리의 바람이 새 자리에서 한 번 더 그려진다
## (`WeaponTrail.clear()`와 같은 자리다).
func clear() -> void:
	if _winds.is_empty():
		return
	_winds.clear()
	queue_redraw()


## 바람 줄무늬 하나를 지금 젤리가 있는 자리에 남긴다.
##
## 세로 자리는 매번 다시 뽑는다 — 같은 높이에서만 나면 바람이 아니라 줄 몇 개가 된다.
func _spawn_wind() -> void:
	_next_wind = _elapsed + WIND_INTERVAL
	var at := global_position + Vector2(
		_rng.randf_range(-10.0, 10.0),
		_rng.randf_range(WIND_TOP, WIND_BOTTOM),
	)
	_winds.append({
		"at": at,
		"length": _rng.randf_range(WIND_LENGTH_MIN, WIND_LENGTH_MAX),
		"age": 0.0,
	})


## 나이를 먹이고 다 된 것을 지운다.
func _age_winds(delta: float) -> void:
	if _winds.is_empty():
		return
	var kept: Array[Dictionary] = []
	for wind in _winds:
		wind["age"] = float(wind["age"]) + delta
		if float(wind["age"]) < WIND_LIFETIME:
			kept.append(wind)
	_winds = kept


func _draw() -> void:
	_draw_winds()
	if active:
		_draw_arcs()


## 톱날이 지나간 자리 — 지금 각에서 **뒤로** 이어지는 원호 몇 개.
##
## 앞쪽에 그리면 아직 지나가지 않은 자리에 자국이 남아 도는 쪽이 거꾸로 읽힌다.
func _draw_arcs() -> void:
	for i in ARC_COUNT:
		var fade := 1.0 - float(i) / float(ARC_COUNT)
		# 도는 쪽의 반대로 물러나며 잇는다. 사이를 조금 띄워 도막이 나뉘어 보이게 한다.
		var end := tip_angle - spin_sign * ARC_SPAN * float(i)
		var start := end - spin_sign * ARC_SPAN * 0.8
		# 옅고 넓은 것 위에 진한 심을 겹쳐 빛나는 날의 자국으로 읽히게 한다
		# (잔상·연기와 같은 방식).
		draw_arc(pivot, radius, minf(start, end), maxf(start, end), ARC_POINTS,
			Color(BLADE_COLOR, ARC_ALPHA * fade * 0.4), ARC_WIDTH * 1.5, true)
		draw_arc(pivot, radius, minf(start, end), maxf(start, end), ARC_POINTS,
			Color(BLADE_COLOR, ARC_ALPHA * fade), ARC_WIDTH * fade, true)


## 젤리 뒤로 흐르는 바람 줄무늬. 나이를 먹을수록 옅어지고 길어진다 —
## 길이가 그대로면 흐르는 것이 아니라 줄이 켜졌다 꺼지는 것으로 보인다.
func _draw_winds() -> void:
	for wind in _winds:
		var life := float(wind["age"]) / WIND_LIFETIME
		var fade := 1.0 - life
		var stored: Vector2 = wind["at"]
		var head := to_local(stored)
		var span: float = float(wind["length"]) * (0.45 + 0.55 * life)
		var tail := head + Vector2(wind_sign * span, 0.0)
		draw_line(head, tail, Color(WIND_COLOR, WIND_ALPHA * fade * 0.45),
			WIND_WIDTH * 2.2, true)
		draw_line(head, tail, Color(WIND_COLOR, WIND_ALPHA * fade), WIND_WIDTH, true)
