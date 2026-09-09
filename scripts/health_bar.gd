extends Node2D
## 피격 체력 바 — 젤리 **머리 위**에 잠깐 떴다 사라진다 (이슈 #317).
##
## 화면 좌우 맨 위 카드에 늘 떠 있던 체력 바를 걷어내고 그 정보를 젤리 옆으로 옮긴 것이다
## (요청). 늘 보이는 대신 **맞은 뒤 `SHOW_TIME` 초 동안만** 뜬다 — 체력은 맞는 순간에
## 알면 되는 값이고, 눈이 젤리를 보고 있는 그 자리에 떠야 읽힌다. 화면 구석에 있던
## 시절에는 몇 대 맞았는지를 알려면 싸움에서 눈을 떼야 했다.
##
## **`gauge_bar.gd` 와 같은 짜임이다**: 부모(`Player`)의 값을 읽어 그리기만 하고 아무 판단도
## 하지 않는다. 뜨는 시각(`Player.hurt_at`)도 서버가 내려준 피격 신호가 정하므로
## (`_receive_hit`·`_receive_dot` 은 `call_local`) **두 기기에 같은 순간 같은 눈금**이 뜬다.
## 여기서 시각을 직접 재면 늦게 도착한 쪽만 늦게 사라진다.
##
## 씬 루트(`Player`)에는 가산 혼합이 걸려 있지만 이 노드는 자기 재질이 없어 평소 혼합으로
## 그린다 — 게이지 바와 같은 이유로, 이것은 빛이 아니라 눈금이라 어떤 배경 위에서도
## 제 색으로 읽혀야 한다.

## 맞은 뒤 이만큼 떠 있다가 사라진다(초, 요청). 연달아 맞으면 `Player.hurt_at` 이
## 갱신되므로 그때부터 다시 이만큼이다.
const SHOW_TIME := 2.0
## 사라지기 직전 이 시간 동안 옅어진다. `SHOW_TIME` **안쪽**이라 다 합쳐서 2초다 —
## 뒤에 덧붙이면 요청한 2초보다 오래 남는다. 툭 꺼지면 "버그로 사라졌다"로 읽힌다.
const FADE_OUT := 0.35

## 바의 크기(px)와 놓을 높이. 젤리 몸통(48px)보다 조금 넓어 머리 위에 얹힌 것으로 보인다.
## 게이지 바(`gauge_bar.gd` 의 -60, 두께 7)와 머리(약 -44) 사이에 끼워 넣은 자리라
## 두 바가 같이 떠도 겹치지 않는다.
const WIDTH := 52.0
const HEIGHT := 8.0
const CENTER_Y := -50.0

const BG_COLOR := Color(0.16, 0.14, 0.22, 0.85)
const BORDER_COLOR := Color(0.88, 0.86, 0.94, 0.55)

## 남은 체력에 따라 초록 → 노랑 → 빨강. 길이만으로도 읽히지만, 죽기 직전이라는 것은
## 길이보다 색이 먼저 눈에 걸린다 — 바가 2초만 떠 있어서 한눈에 읽혀야 한다.
const FULL_COLOR := Color(0.44, 0.84, 0.46)
const HALF_COLOR := Color(0.98, 0.78, 0.28)
const LOW_COLOR := Color(0.92, 0.28, 0.32)

## 이번에 깎인 몫이 잠깐 남는 흰 자국. **이 바가 뜨는 이유 자체를 보여 준다** —
## 남은 체력만 그리면 "지금 얼마인가"만 알 수 있고 "방금 얼마나 맞았나"는 안 보인다.
const GHOST_COLOR := Color(1.0, 0.96, 0.96, 0.9)
## 흰 자국이 남은 체력 자리까지 줄어드는 데 걸리는 시간(초).
const GHOST_TIME := 0.4

## 참조를 들고 있지 않고 매번 부모를 본다 (`gauge_bar.gd` 와 같은 방식).
var _player: Node = null


func _ready() -> void:
	_player = get_parent()
	visible = false


## 뜰 때와 사라질 때가 매 프레임 바뀌므로 보이는 동안에는 계속 다시 그린다.
func _process(_delta: float) -> void:
	var alpha := _alpha()
	visible = alpha > 0.0
	if not visible:
		return
	self_modulate.a = alpha
	queue_redraw()


## 지금 이 바의 진하기(0~1). 뜰 이유가 없으면 0이다.
##
## **죽은 젤리에는 안 뜬다** — 마지막 일격은 빈 바를 남기는데, 누워 있는 젤리 위에 빈
## 칸이 2초 더 떠 있으면 아직 뭔가 남은 것처럼 보인다. 낙사(`server_kill`)처럼 데미지
## 없이 죽는 경우도 같이 걸러진다.
func _alpha() -> float:
	if _player == null or not _player.alive:
		return 0.0
	var since: float = _now() - _player.hurt_at
	if _player.hurt_at < 0.0 or since < 0.0 or since > SHOW_TIME:
		return 0.0
	var left := SHOW_TIME - since
	if left >= FADE_OUT:
		return 1.0
	return left / FADE_OUT


func _draw() -> void:
	if _player == null:
		return
	var ratio: float = clampf(_player.hp / Combat.MAX_HP, 0.0, 1.0)
	var half := WIDTH * 0.5
	var box := Rect2(-half, CENTER_Y - HEIGHT * 0.5, WIDTH, HEIGHT)
	var inner := box.grow(-1.0)

	draw_rect(box, BG_COLOR, true)

	# 맞기 직전 자리에서 남은 체력 자리로 줄어드는 흰 자국을 **먼저** 깐다.
	# 그 위에 남은 체력을 덮어 그리므로 튀어나온 부분만 희게 남는다.
	var ghost: float = clampf(_player.hurt_from_hp / Combat.MAX_HP, 0.0, 1.0)
	var shrink: float = clampf((_now() - _player.hurt_at) / GHOST_TIME, 0.0, 1.0)
	ghost = lerpf(ghost, ratio, shrink)
	if ghost > ratio:
		_draw_fill(inner, ghost, GHOST_COLOR)

	if ratio > 0.0:
		_draw_fill(inner, ratio, _fill_color(ratio))

	# 테두리를 마지막에 덧그려 채움이 밖으로 새어 보이지 않게 한다.
	draw_rect(box, BORDER_COLOR, false, 1.0)


## 안쪽 칸을 왼쪽에서부터 `ratio` 만큼 칠한다.
func _draw_fill(inner: Rect2, ratio: float, color: Color) -> void:
	var bar := inner
	bar.size.x = maxf(inner.size.x * ratio, 1.0)
	draw_rect(bar, color, true)


## 남은 체력 색. 절반을 기준으로 위쪽은 노랑→초록, 아래쪽은 빨강→노랑으로 섞는다.
func _fill_color(ratio: float) -> Color:
	if ratio >= 0.5:
		return HALF_COLOR.lerp(FULL_COLOR, (ratio - 0.5) * 2.0)
	return LOW_COLOR.lerp(HALF_COLOR, ratio * 2.0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
