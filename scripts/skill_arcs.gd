class_name SkillArcs
extends Node2D
## 능력을 켜는 특수가 켜져 있는 동안 몸을 감싸고 튀는 전격 (망치·광선검).
##
## 참고한 화면에서 일어나던 일은 하나였다: **잠깐씩 나타나는 청백색 번개 가지가
## 몸 주변을 기어다닌다.** 한 모양으로 가만히 있으면 번개가 아니라 파란 철사로 보이므로,
## 삼지창 번개(`lightning_strike.gd`)와 같은 규칙을 쓴다 — **줄기를 갈아 끼우며 떤다.**
##
## **왜 별도 노드인가**: 씬 루트(`player.tscn`)의 `_draw()`는 자식 스프라이트보다 **먼저**
## 그려져서 젤리 뒤에 깔린다(관통 빛무리가 그 자리를 쓴다). 전격은 몸 **위로** 기어야
## 읽히므로 `Body`·`WeaponSprite` 뒤에 오는 형제여야 한다. 잔상(`weapon_trail.gd`)이
## 별도 노드인 것과 같은 사정이고, 이유만 반대다 — 그쪽은 밑에 깔려야 했다.
##
## **`z_index`로 올리지 않는다** — 맵이 z 0에 깔아 둔 배경과의 순서가 어긋난다(#146).
## 형제 순서로만 정한다.
##
## 가산 혼합(씬의 `CanvasItemMaterial`)을 쓴다. 번개는 타오르는 빛이라 겹칠수록 하얘야
## 하고, 밝은 맵에서 묻히지 않도록 넓고 옅은 것 위에 좁고 흰 것을 겹쳐 그린다
## (#112·#146 이 그 얘기다 — `lightning_strike.gd`와 같은 세 겹).
##
## **양쪽 화면의 모양이 같지 않아도 된다.** 켜졌는지는 복제되는 버프에서 나오고
## (`Player._stun_grant_until`·`_pierce_until`), 가지 모양은 매 0.07초 새로 뽑는 난수다 —
## 연기·젤리 찌그러짐과 같이 각 피어가 자기 화면 것을 그린다. 복제할 것이 없다.
##
## 켜고 끄는 것은 부모(`Player._update_skill_arcs()`)가 정한다.

## 한 번에 도는 가지 수. 많으면 젤리가 안 보이고, 적으면 번개가 아니라 선 하나가 된다.
const ARC_COUNT := 3
## 가지를 갈아 끼우는 간격(초). 삼지창 번개의 0.06과 같은 대역이다 —
## 이보다 길면 떠는 것이 아니라 깜빡이는 것으로 보인다.
const RESEED_INTERVAL := 0.07

## 가지가 도는 원의 반지름(px). 몸통 반폭(24)보다 10px 밖이라 몸에서 삐져나온다 —
## 30 으로 딱 붙였을 때는 번개가 아니라 몸 윤곽선으로 보였다.
const ORBIT_RADIUS := 34.0
## 원의 중심을 몸 가운데로 올린다(px). 원점은 발밑이라 그대로 두면 땅에서 튄다.
const ORBIT_CENTER := Vector2(0.0, -26.0)
## 가지 하나가 원 위에서 훑는 각의 폭(라디안). TAU를 채우면 몸을 완전히 둘러 고리가 된다.
const ARC_SPAN := 1.5
## 가지를 몇 도막으로 꺾을지. 적으면 지그재그가 성기고 많으면 지저분해진다.
const SEGMENTS := 7
## 꺾이는 폭(px). 원 밖으로도 안으로도 튄다. 작으면 매끄러운 고리가 되어 번개가 아니다.
const JAG := 13.0

## 세 겹의 굵기(px). 넓고 옅은 것 위에 좁고 흰 것을 겹쳐 가운데를 태운다.
##
## **파란 겹이 흰 심보다 훨씬 넓어야 한다.** 가산 혼합에서는 겹친 만큼 하얘지므로
## 처음 잡은 7/3.6/1.4 는 셋이 거의 같은 자리에서 타서 통째로 흰 선이 되었다 —
## 청백색 번개가 아니라 몸을 두른 흰 테두리로 보였다.
const WIDTH_EDGE := 12.0
const WIDTH_MID := 5.0
const WIDTH_CORE := 1.4

## 가지 끝에 붙는 작은 불꽃점의 반지름(px). 끝이 그냥 끊기면 잘린 선으로 보인다.
const TIP_RADIUS := 4.0

## 청백색. 참고한 화면의 전격이 이 색이었다 — 가운데는 하얗게 태운다.
const CORE_COLOR := Color(1.0, 1.0, 1.0)
const MID_COLOR := Color(0.62, 0.92, 1.0)
const EDGE_COLOR := Color(0.20, 0.55, 1.0)

## 지금 전격이 켜져 있는가. 부모가 매 프레임 맞춘다.
##
## 끄는 순간 한 번 더 그려야 화면에서 지워진다 — 관통 빛무리가 `_aura_shown` 으로
## 같은 일을 하는데, 이쪽은 노드가 따로라 `visible` 로 끝난다.
var active := false:
	set(value):
		if active == value:
			return
		active = value
		visible = value
		if not value:
			_arcs.clear()
		else:
			_reseed()
		queue_redraw()

var _elapsed := 0.0
var _next_reseed := 0.0
## 도는 가지들. 하나마다 꺾인 점들(지역 좌표)이다.
var _arcs: Array[PackedVector2Array] = []


func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	if _elapsed >= _next_reseed:
		_reseed()
	queue_redraw()


## 가지를 새로 뽑는다. 원 위의 서로 다른 자리에서 시작해 각자 조금씩 훑는다.
func _reseed() -> void:
	_next_reseed = _elapsed + RESEED_INTERVAL
	_arcs.clear()
	var rng := RandomNumberGenerator.new()
	for i in ARC_COUNT:
		# 고르게 두른 뒤 흔든다. 완전 무작위로 뽑으면 세 가지가 한쪽에 뭉친다.
		var start := TAU * float(i) / float(ARC_COUNT) + rng.randf_range(-0.5, 0.5)
		var span := ARC_SPAN * rng.randf_range(0.6, 1.0)
		# 도는 쪽을 반씩 나눈다 — 다 같은 쪽으로 훑으면 몸이 도는 것처럼 보인다.
		if rng.randf() < 0.5:
			span = -span
		var points := PackedVector2Array()
		for s in SEGMENTS + 1:
			var t := float(s) / float(SEGMENTS)
			var angle := start + span * t
			# 양 끝은 원 위에 얹고 가운데만 튄다 — 끝이 흔들리면 붙어 있지 않은 선이 된다.
			var wobble := sin(PI * t) * rng.randf_range(-JAG, JAG)
			var radius := ORBIT_RADIUS + wobble
			points.append(ORBIT_CENTER + Vector2.RIGHT.rotated(angle) * radius)
		_arcs.append(points)


func _draw() -> void:
	if not active:
		return
	for points in _arcs:
		if points.size() < 2:
			continue
		# 넓고 파란 것 → 좁고 하늘색 → 가는 흰 심.
		draw_polyline(points, Color(EDGE_COLOR, 0.7), WIDTH_EDGE, true)
		draw_polyline(points, Color(MID_COLOR, 0.55), WIDTH_MID, true)
		draw_polyline(points, Color(CORE_COLOR, 0.85), WIDTH_CORE, true)
		# 양 끝의 불꽃점.
		for at in [points[0], points[-1]]:
			Art.draw_glow(self, at, TIP_RADIUS * 1.8, EDGE_COLOR, 0.5, 8)
			draw_circle(at, TIP_RADIUS * 0.5, Color(CORE_COLOR, 0.9))
