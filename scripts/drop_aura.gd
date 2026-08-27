extends Node2D
## 바닥에 떨어져 주울 수 있는 단검 주변에 도는 빨간 오라 (#250).
##
## **테두리가 실제로 주워지는 거리다** — `Projectile`이 `PICKUP_RANGE`를 `radius`로
## 넘겨 준다(#256, 양날 도끼 충격파가 `landing_radius`를 받는 것과 같은 방식). 폭탄 반경을
## 그린 것과 같은 이유다(#140) — 눈으로 배운 범위가 실제와 어긋나면 표시가 거짓말이 된다.
## 그래서 맥박은 안쪽 빛만 치고 **테두리는 제자리에 가만히 있는다.**
##
## **투사체 씬 루트가 아니라 자식 노드에서 그린다.** 루트에는 미사일 불꽃 때문에 가산 혼합
## (`CanvasItemMaterial`)이 걸려 있는데, 가산은 밝게만 만들 수 있어서 평지 하늘처럼 이미 흰
## 배경 위에서는 아무리 그려도 보이지 않는다 (#112·`blast_radius.gd`와 같은 이유).
## 자식은 그 재질을 물려받지 않으므로 보통의 알파 혼합으로 그려져 어느 맵에서나 같게 읽힌다.
##
## 단검 그림 뒤에 깔리는 것은 **형제 순서**로 한다 — 씬에서 `Visual`·`ArtSprite`보다 앞에
## 있어서 같은 z 레이어 안에서 먼저 그려진다. **`z_index`를 내리면 안 된다**(#146):
## 맵이 자기 배경을 z 0의 불투명 `ColorRect`로 깔기 때문에 원이 그 아래로 사라진다.
##
## 순수 표시라 판정과는 무관하다 — 주워지는 판정은 `projectile.gd`가 한다.
## 켜고 끄는 것도 그쪽이다: 복제되는 `landed` 를 보고 매 프레임 `active` 를 맞춘다.

## 오라의 겉 반지름(px). **주워지는 거리와 같은 값이며 부모가 넣어 준다** (#256).
## 여기에 상수를 두면 같은 숫자가 두 곳에 남아 한쪽만 고쳐질 수 있다 —
## 그러면 테두리 밖에서도 단검이 주워져 이 표시가 거짓말이 된다.
## 0이면 아무것도 그리지 않는다(`blast_radius.gd`와 같은 규칙).
var radius := 0.0:
	set(value):
		radius = value
		queue_redraw()

## 오라의 붉은색.
const FILL := Color(0.97, 0.14, 0.10)
## 단검 자체를 감싸는 작은 빛의 반지름과 옅기. 날이 붉게 달아 있는 것으로 읽힌다.
## 단검 그림보다 **먼저** 그려지므로 진해도 그림을 가리지 않는다.
##
## **겉 반지름에 대한 비율이다** (#256). 절대값(22px)이면 원이 36px로 줄었을 때
## 붉은 띠와 테두리를 덮어 버린다 — 겉이 줄면 안쪽 빛도 같이 줄어야 한다.
## 0.46은 48px일 때의 22px을 그대로 옮긴 비율이고, 36px에서는 16.6px이 된다.
const CORE_RATIO := 0.46
const CORE_ALPHA := 0.7
## 테두리 안쪽에 겹쳐 그리는 붉은 띠.
##
## **원 안을 통째로 채우지 않는다.** 옅은 알파로 넓은 면을 덮으면 배경과 섞여 붉은색이
## 아니라 흐린 회색 얼룩으로 보이고(밝은 하늘에서 특히 그렇다), 진하게 하면 그 안의
## 단검과 지형이 묻힌다. 그래서 얇은 고리를 겹쳐 쌓고 **가장자리로 갈수록 진하게** 한다 —
## 안쪽 겹은 거의 안 보이고 테두리에 가까운 겹이 색을 낸다. 그 사이에 빈 자리를 두면
## 오라가 아니라 고리 두 개로 보이므로, 안쪽 겹은 단검을 감싸는 빛과 맞닿을 만큼 안에서 시작한다.
const BAND_INNER := 0.34
const BAND_STEPS := 10
const BAND_WIDTH := 6.0
const BAND_ALPHA := 0.5
## 테두리 — 주워지는 경계와 정확히 같은 자리라 이 표시의 알맹이다. 채움만 있으면
## 옅은 쪽이 어디서 끝나는지 눈으로 짚을 수 없다 (`blast_radius.gd`와 같은 판단).
const EDGE := Color(1.0, 0.34, 0.26)
const EDGE_ALPHA := 0.9
const EDGE_WIDTH := 2.5
const EDGE_SEGMENTS := 40
## 맥박 속도(라디안/초)와 그 폭. 가만히 있는 원은 맵 무늬로 읽히고, 맥박이 돌면
## "지금 여기 놓여 있다"로 읽힌다. 폭이 크면 주워지는 거리가 변하는 것처럼 보인다.
const PULSE_RATE := 4.2
const PULSE_DEPTH := 0.12

## 지금 오라를 띄우는가. 떨어져서 주울 수 있는 단검일 때만 참이다.
var active := false:
	set(value):
		if active == value:
			return
		active = value
		visible = value
		# 뜰 때마다 맥박을 처음부터 시작한다 — 안 그러면 떨어지는 순간의 밝기가
		# 그때까지 흐른 시간에 따라 달라진다.
		_elapsed = 0.0
		queue_redraw()

var _elapsed := 0.0


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	queue_redraw()


## 단검이 움직여도 다시 그릴 필요가 없다 — 원점을 기준으로 그리므로 노드가
## 옮겨질 때 그려 둔 것이 함께 따라간다 (`blast_radius.gd`와 같다).
func _draw() -> void:
	if not active or radius <= 0.0:
		return
	var pulse := 1.0 + PULSE_DEPTH * sin(_elapsed * PULSE_RATE)
	# 날을 감싸는 작은 빛 — 맥박은 여기서만 돈다.
	Art.draw_glow(self, Vector2.ZERO, radius * CORE_RATIO * pulse, FILL, CORE_ALPHA, 14)
	# 가장자리로 갈수록 진해지는 붉은 띠.
	for i in BAND_STEPS:
		var t := float(i) / float(BAND_STEPS - 1)
		draw_arc(Vector2.ZERO, radius * lerpf(BAND_INNER, 0.985, t), 0.0, TAU,
			EDGE_SEGMENTS, Color(FILL, BAND_ALPHA * t * t * pulse), BAND_WIDTH, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, EDGE_SEGMENTS,
		Color(EDGE, EDGE_ALPHA), EDGE_WIDTH, true)
