extends Control
## 포인트를 딴 순간에 한 번 뜨는 장면 (이슈 #273, #388 에서 새로 만들었다).
##
## **젤리가 위에서 떨어져 통통 튀고, 새로 딴 포인트 칸 위로 뛰어올라, 착지하는 순간 그 칸이
## 금색으로 터진다.** 칸 세 개가 든 트레이가 먼저 튀어나오고, 착지에서 방울이 튀며
## `+1 포인트!` 가 솟고, 젤리가 한 번 더 뛰며 기뻐한 뒤 모두 사라진다. 마지막 3점째는
## 방울·고리가 훨씬 크고 색종이가 쏟아진다.
##
## 이전 연출(#273)은 띠·리본이 중심이라 이 게임의 주인공인 젤리가 움직이지 않았다 —
## 지금은 **움직이는 것이 젤리 하나**이고 나머지(트레이·글자·방울)는 그 움직임이 만든 결과다.
## 찌그러짐·늘어남은 모두 발밑을 기준으로 건다 (`player.gd` 가 몸을 그리는 것과 같은 이유 —
## 가운데 기준이면 늘어날 때 발이 바닥을 뚫는다).
##
## **편 색은 `as_gain` 이 정한다** — 딴 장면이면 파랑, 잃은 장면이면 빨강. 트레이·글자
## 테두리·배경 빛이 그 색이다. 어느 쪽이 땄는지를 글자로 읽지 않고 색으로 알아채게 하는
## 것이 이 장면의 요점이다 — 3점 선취가 이 게임의 유일한 승패 조건인데, 점수가 오르는
## 순간에 바뀌는 것은 화면 맨 위 카드의 동그라미 하나뿐이어서 젤리를 보고 있던 눈에는
## 아무것도 안 들어왔다.
##
## 그림 파일 없이 `_draw()` 로만 그린다 (`light_burst.gd` 와 같은 방식) — 젤리 얼굴만
## 캐릭터 표에서 가져온다. **언제 띄울지는 `main.gd` 가 정하고** 여기서는 보여주는 일만 한다
## (`main.gd` 의 `_on_player_died` → `_play_point_gain`) — `match_intro.gd` 와 같은 짜임이다.
##
## 화면을 실제로 흐리게(블러) 하지는 않는다. GL Compatibility 에서 화면 텍스처 블러는
## 셰이더가 필요하고 이 저장소의 연출은 전부 `_draw()` 로만 그린다 — 대신 옅은 흰 막을
## 깔아 뒤가 물러나게 한다. 어두운 맵(용암)에서도 글자와 트레이가 뜨는 것은 이 막 덕분이다.
##
## 한 프레임의 모습은 시각 `_elapsed` 하나로 전부 정해진다 (`_draw()` 는 난수도 상태도 들고
## 있지 않다 — 방울·색종이도 번호에서 뽑는다). 그래서 미리보기에서 시각을 박아 원하는
## 대목을 골라 볼 수 있다.

## 처음부터 끝까지 걸리는 시간(초). `Combat.POINT_GAIN_TIME` 을 그대로 쓴다 —
## `main.gd` 가 다음 판과 결과 화면을 이만큼 미루므로 두 값이 갈리면 장면이 잘리거나
## 빈 화면이 남는다. `match_intro.gd` 는 상수를 양쪽에 따로 두었는데, 그러면 한쪽만
## 고쳤을 때 조용히 어긋나므로 여기서는 한 곳만 두고 `main.gd` 도 이것을 읽는다.
const TOTAL := Combat.POINT_GAIN_TIME

# ─────────────────────────── 배치 (기준 화면 1152×648) ───────────────────────────
## 가로는 상수로 두지 않고 `size.x` 에서 잰다 — 기준 화면에 박아 두면 뷰포트 크기를
## 손대는 날 장면만 가운데를 벗어난다.

## 포인트 칸 트레이. 칸 세 개가 가운데를 기준으로 좌우로 벌어진다.
const TRAY_CENTER_Y := 412.0
const TRAY_HALF_W := 150.0
const TRAY_HALF_H := 44.0
## 트레이 테두리 두께.
const TRAY_RIM := 5.0
const PIP_RADIUS := 26.0
const PIP_GAP := 84.0
const PIP_NUMBER_SIZE := 26

## 젤리가 서는 바닥(발밑 y). 트레이 윗면(`368`)보다 조금 아래 — 트레이 위에 선 것으로 읽힌다.
const GROUND_Y := 376.0
## 젤리 그림의 세로 길이와 가로 상한(px). 가로로 긴 포즈가 트레이를 넘지 않게 한다.
const JELLY_HEIGHT := 124.0
const JELLY_MAX_WIDTH := 150.0
## 떨어지기 시작하는 발밑 y. 화면 밖이라 위에서 날아 들어온다.
const DROP_FROM_Y := -170.0

## 딴 사람의 이름.
const NAME_Y := 496.0
const NAME_SIZE := 26

## `+1 포인트!` 글자. 젤리 머리 위, 가운데에 뜬다. 마지막 포인트는 더 크다.
const GAIN_TEXT := "+1 포인트!"
const GAIN_Y := 204.0
const GAIN_SIZE := 46
const GAIN_SIZE_FINAL := 58
const GAIN_OUTLINE := 7

# ─────────────────────────── 시각표 (초) ───────────────────────────
## 트레이가 튀어나오는 데 걸리는 시간.
const TRAY_POP := 0.28
## 젤리가 떨어지기 시작하는 시각과 걸리는 시간.
const DROP_AT := 0.08
const DROP_TIME := 0.30
const LAND_FIRST_AT := DROP_AT + DROP_TIME
## 뛰기 직전에 웅크리는 시간 — 이것이 없으면 점프가 갑자기 튀어 올라 공이 튕기는 것처럼 보인다.
const CROUCH_TIME := 0.10
## 새 칸으로 뛰는 시각·걸리는 시간·높이(px).
const JUMP_AT := 0.86
const JUMP_TIME := 0.38
const JUMP_HEIGHT := 120.0
## 칸 위에 내려앉는 시각 — 칸이 터지고 방울이 튀고 글자가 솟는 기준 시각이다.
const LAND_AT := JUMP_AT + JUMP_TIME
## 기뻐서 한 번 더 뛰는 시각·걸리는 시간·높이.
const CHEER_AT := 1.62
const CHEER_TIME := 0.34
const CHEER_HEIGHT := 34.0
## 맨 끝에서 모든 것이 사라지는 데 걸리는 시간.
const FADE_TIME := 0.30
const FADE_AT := TOTAL - FADE_TIME

## 찌그러짐이 가라앉는 속도와 흔들림 속도 — `exp(-DAMP·a)·cos(FREQ·a)`.
const WOBBLE_DAMP := 7.0
const WOBBLE_FREQ := 24.0

# ─────────────────────────── 방울·고리·색종이 ───────────────────────────
const DROP_COUNT := 14
const DROP_COUNT_FINAL := 26
const DROP_GRAVITY := 1100.0
const CONFETTI_COUNT := 44
## 바닥에 퍼지는 납작한 고리가 다 퍼지는 데 걸리는 시간과 마지막 반경(px).
const RING_TIME := 0.46
const RING_RADIUS := 150.0
const RING_RADIUS_FINAL := 270.0

# ─────────────────────────── 색 ───────────────────────────
## 내가 딴 포인트 — 파랑. 참고 영상(포켓몬 TCG 포켓)에서 뽑은 값이다.
const BAND_MINE := Color(0.055, 0.82, 1.0)
const STRIPE_MINE := Color(0.125, 0.49, 0.97)
const PLAQUE_MINE := Color(0.09, 0.69, 0.99)
const PIP_MINE := Color(0.145, 0.47, 0.89)
const PIP_RIM_MINE := Color(0.215, 0.54, 0.97)

## 상대가 딴 포인트 — 빨강. 파랑 쪽과 **같은 밝기·짙기 구조**로 색만 옮겼다.
## 밝기까지 낮추면 상대가 딸 때마다 화면이 어두워져 벌 받는 것처럼 보인다.
## 트레이는 파랑 쪽보다 더 낮춰 잡았다 — 빨강은 초록 성분이 이미 거의 없어서 파랑 쪽처럼
## 초록만 조금 빼면(#0ED1FE → #17B1FC) 배경 빛과 구별되지 않고 트레이가 사라진다.
const BAND_THEIRS := Color(1.0, 0.30, 0.32)
const STRIPE_THEIRS := Color(0.86, 0.13, 0.24)
const PLAQUE_THEIRS := Color(0.84, 0.18, 0.27)
const PIP_THEIRS := Color(0.78, 0.15, 0.24)
const PIP_RIM_THEIRS := Color(0.89, 0.24, 0.32)

## 채워진 칸은 **양쪽 다 금색**이다. 포인트라는 물건의 색이라서 편에 따라 바뀌지 않는다 —
## 트레이 색이 이미 누가 땄는지를 말하고 있고, 칸까지 같은 색이면 채워진 칸이 묻힌다.
const PIP_FILLED := Color(0.99, 0.88, 0.18)
const WHITE := Color(1.0, 1.0, 1.0)

## 전투 화면을 덮는 막의 값.
const SCRIM_ALPHA := 0.50

## 이름·숫자를 적을 글꼴. 한글이 들어가므로 프로젝트 글꼴을 쓴다 —
## Godot 기본 글꼴에는 한글 글리프가 없어서 `+1 포인트!` 가 네모로 나온다.
##
## `_draw()` 로 그리는 글자는 테마를 타지 않으므로 여기서 직접 든다 (요청).
## 화면의 다른 글자와 같은 것을 써야 해서 테마가 쓰는 것과 같은 자원을 가리킨다 —
## `korean_font.tres`(계통 글꼴)를 직접 들면 이 장면만 옛 글꼴로 남는다.
const FONT := preload("res://resources/display_font.tres")

## 시작한 뒤 흐른 시간(초). 음수면 돌고 있지 않다.
var _elapsed := -1.0

var _scorer_name := ""
## 이번에 채워질 칸의 번호(0부터). 3점째면 2다.
var _new_pip := 0
var _is_final := false
## 방울·색종이의 모양을 사람마다 조금 다르게 하는 값. 이름에서 잡는다.
var _salt := 0.0

var _avatar: Texture2D = null
## 원화의 투명 여백을 뺀 영역. 매 프레임 재지 않으려고 여기 담아 둔다 —
## `Art.content_rect()` 는 텍스처의 이미지를 받아 읽는다.
var _avatar_region := Rect2()

var _band_color := BAND_MINE
var _stripe_color := STRIPE_MINE
var _plaque_color := PLAQUE_MINE
var _pip_color := PIP_MINE
var _pip_rim_color := PIP_RIM_MINE


func _ready() -> void:
	visible = false


## 처음부터 다시 튼다.
##
## `as_gain` 이 이 장면의 색을 정한다 — 딴 장면이면 파랑, 아니면 빨강.
## `score_after` 는 딴 **뒤의** 점수라서 채워질 칸은 그보다 하나 앞이다.
## `is_final` 이면 경기를 끝내는 포인트라 방울·고리가 더 크고 색종이가 쏟아진다.
func play(scorer_name: String, character_id: String, score_after: int,
		as_gain: bool, is_final: bool) -> void:
	_scorer_name = scorer_name
	_new_pip = clampi(score_after - 1, 0, Combat.POINTS_TO_WIN - 1)
	_is_final = is_final
	_salt = float(hash(scorer_name) % 997)
	# 이긴 포즈로 보여준다 (#176) — 포인트를 딴 사람의 얼굴이다.
	_avatar = Characters.pose_texture(character_id, Characters.POSE_WIN)
	_avatar_region = Art.content_rect(_avatar) if _avatar != null else Rect2()
	_apply_palette(as_gain)
	_elapsed = 0.0
	modulate.a = 1.0
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _elapsed >= TOTAL:
		_elapsed = -1.0
		visible = false
		modulate.a = 1.0
		return
	# 맨 끝에서는 모든 것이 한꺼번에 사라진다 — 그리는 쪽마다 따로 옅게 하면
	# 겹친 면이 이중으로 비쳐 보이므로 노드 전체의 투명도 하나로 한다.
	modulate.a = clampf((TOTAL - _elapsed) / FADE_TIME, 0.0, 1.0)
	queue_redraw()


func _apply_palette(as_gain: bool) -> void:
	_band_color = BAND_MINE if as_gain else BAND_THEIRS
	_stripe_color = STRIPE_MINE if as_gain else STRIPE_THEIRS
	_plaque_color = PLAQUE_MINE if as_gain else PLAQUE_THEIRS
	_pip_color = PIP_MINE if as_gain else PIP_THEIRS
	_pip_rim_color = PIP_RIM_MINE if as_gain else PIP_RIM_THEIRS


# ─────────────────────────── 움직임 ───────────────────────────
## 0→1 로 가면서 1 을 넘었다 돌아오는 곡선(ease-out-back). 팝업에 쓴다.
func _back(p: float) -> float:
	var q := clampf(p, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * q * q * q + 1.70158 * q * q


## 착지 뒤에 흔들리며 가라앉는 값. `a` 가 0 일 때 1(가장 눌린 모습)이고 0 으로 수렴한다.
func _wobble(a: float) -> float:
	return exp(-WOBBLE_DAMP * a) * cos(WOBBLE_FREQ * a)


## 포물선 한 번(0→1). 꼭대기에서 0, 양끝에서 1 인 속도 비율도 같이 돌려준다 —
## 빠를 때 세로로 늘어나고 꼭대기에서 원래대로 돌아오게 하려는 값이다.
func _arc(p: float) -> Vector2:
	return Vector2(4.0 * p * (1.0 - p), absf(2.0 * p - 1.0))


func _pip_center(index: int) -> Vector2:
	var offset := (float(index) - float(Combat.POINTS_TO_WIN - 1) * 0.5) * PIP_GAP
	return Vector2(size.x * 0.5 + offset, TRAY_CENTER_Y)


## 이 시각의 젤리: `[발밑 좌표, 크기 배율]`. 아직 나타나지 않았으면 빈 배열.
##
## 단계는 위에서 아래로 시각표 순서다 — 떨어짐 → 착지 → (웅크림) → 점프 → 착지 → 환호 → 가라앉음.
func _jelly_state(t: float) -> Array:
	if t < DROP_AT:
		return []
	var home := Vector2(size.x * 0.5, GROUND_Y)
	var target := Vector2(_pip_center(_new_pip).x, GROUND_Y)

	if t < LAND_FIRST_AT:
		# 가속하며 떨어진다. 떨어지는 동안은 세로로 길쭉하다.
		var p := (t - DROP_AT) / DROP_TIME
		return [Vector2(home.x, lerpf(DROP_FROM_Y, GROUND_Y, p * p)), Vector2(0.86, 1.22)]

	if t < JUMP_AT - CROUCH_TIME:
		var v := _wobble(t - LAND_FIRST_AT)
		return [home, Vector2(1.0 + 0.34 * v, 1.0 - 0.34 * v)]

	if t < JUMP_AT:
		var c := (t - (JUMP_AT - CROUCH_TIME)) / CROUCH_TIME
		return [home, Vector2(1.0 + 0.20 * c, 1.0 - 0.26 * c)]

	if t < LAND_AT:
		var p := (t - JUMP_AT) / JUMP_TIME
		var arc := _arc(p)
		var pos := Vector2(lerpf(home.x, target.x, p), GROUND_Y - JUMP_HEIGHT * arc.x)
		var stretch := 1.0 + 0.24 * arc.y
		return [pos, Vector2(1.0 - 0.14 * arc.y, stretch)]

	if t < CHEER_AT:
		var v := _wobble(t - LAND_AT)
		return [target, Vector2(1.0 + 0.42 * v, 1.0 - 0.42 * v)]

	if t < CHEER_AT + CHEER_TIME:
		var p := (t - CHEER_AT) / CHEER_TIME
		var arc := _arc(p)
		return [Vector2(target.x, GROUND_Y - CHEER_HEIGHT * arc.x),
				Vector2(1.0 - 0.08 * arc.y, 1.0 + 0.14 * arc.y)]

	var settle := _wobble(t - CHEER_AT - CHEER_TIME)
	return [target, Vector2(1.0 + 0.26 * settle, 1.0 - 0.26 * settle)]


# ─────────────────────────── 그리기 ───────────────────────────
func _draw() -> void:
	if _elapsed < 0.0:
		return
	var t := _elapsed

	_draw_scrim(t)
	_draw_aura(t)

	var tray_scale := _back(t / TRAY_POP)
	if tray_scale > 0.02:
		var tray_xf := Transform2D(0.0, Vector2.ONE * tray_scale, 0.0,
				Vector2(size.x * 0.5, TRAY_CENTER_Y))
		_draw_tray(tray_xf)
		for i in Combat.POINTS_TO_WIN:
			_draw_pip(i, t, tray_xf)
		draw_set_transform_matrix(Transform2D.IDENTITY)

	_draw_name(t)
	_draw_jelly(t)
	_draw_splash(t)
	_draw_gain_text(t)
	_draw_confetti(t)


## 전투 화면을 덮는 옅은 흰 막. 막에 편 색을 아주 조금 섞는다 — 완전한 흰 막은 어느
## 맵에서나 같아서 화면 전체가 이 장면의 편을 들고 있다는 느낌이 나지 않는다.
func _draw_scrim(t: float) -> void:
	var alpha := SCRIM_ALPHA * clampf(t / 0.12, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(WHITE.lerp(_band_color, 0.12), alpha))


## 무대 뒤에서 번지는 편 색의 빛. 착지하는 순간 한 번 맥동하고, 그 자리(칸)에서 흰 빛이 터진다.
func _draw_aura(t: float) -> void:
	var center := Vector2(size.x * 0.5, 330.0)
	var swell := clampf(t / 0.30, 0.0, 1.0)
	Art.draw_glow(self, center, 360.0, _band_color, 0.42 * swell, 22)
	if t < LAND_AT:
		return
	var a := t - LAND_AT
	var flash := exp(-5.0 * a)
	var at := Vector2(_pip_center(_new_pip).x, GROUND_Y)
	Art.draw_glow(self, at, 170.0 * (1.5 if _is_final else 1.0), WHITE, 0.55 * flash, 18)


## 칸 세 개를 담은 알약 모양 트레이. 흰 테두리 안이 편 색이다.
func _draw_tray(xf: Transform2D) -> void:
	draw_set_transform_matrix(xf)
	var half := Vector2(TRAY_HALF_W, TRAY_HALF_H)
	draw_colored_polygon(_round_rect(half + Vector2.ONE * TRAY_RIM, TRAY_HALF_H + TRAY_RIM),
			WHITE)
	draw_colored_polygon(_round_rect(half, TRAY_HALF_H), _plaque_color)


## 원점이 가운데인 둥근 사각형의 꼭짓점. 한 장의 다각형이라 반투명이어도 겹쳐 비치지 않는다.
func _round_rect(half: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 8
	var inner := half - Vector2.ONE * radius
	# 오른쪽 위부터 시계 방향 — 모서리마다 중심과 시작 각도.
	var corners := [
		[Vector2(inner.x, -inner.y), -PI * 0.5],
		[Vector2(inner.x, inner.y), 0.0],
		[Vector2(-inner.x, inner.y), PI * 0.5],
		[Vector2(-inner.x, -inner.y), PI],
	]
	for corner in corners:
		var c: Vector2 = corner[0]
		var start: float = corner[1]
		for i in steps + 1:
			var ang := start + (PI * 0.5) * float(i) / float(steps)
			pts.append(c + Vector2(cos(ang), sin(ang)) * radius)
	return pts


## 칸 하나. 이번에 딴 칸은 착지하는 순간 금색이 되며 눌렸다 튀어 오른다.
## 뛰어오르는 동안에는 "여기로 간다"는 표시로 두근거린다.
func _draw_pip(index: int, t: float, tray_xf: Transform2D) -> void:
	var is_new := index == _new_pip
	var earned := index < _new_pip or (is_new and t >= LAND_AT)
	var pip_scale := 1.0
	if is_new:
		if t >= LAND_AT:
			var a := t - LAND_AT
			# 0 에서 시작해 부풀었다 돌아온다 — 젤리에 눌린 칸이 튕겨 오르는 모습.
			pip_scale = 1.0 + 0.55 * exp(-5.5 * a) * sin(17.0 * a)
		elif t >= JUMP_AT - CROUCH_TIME:
			pip_scale = 1.0 + 0.07 * sin((t - JUMP_AT) * 28.0)
	var local := Vector2((float(index) - float(Combat.POINTS_TO_WIN - 1) * 0.5) * PIP_GAP, 0.0)
	draw_set_transform_matrix(tray_xf * Transform2D(0.0, Vector2.ONE * pip_scale, 0.0, local))
	var fill := PIP_FILLED if earned else _pip_color
	var rim := WHITE if earned else _pip_rim_color
	# 금색 칸의 숫자는 트레이의 진한 테두리 색이다 — 편 색이 숫자에도 남아야
	# 파랑 판과 빨강 판이 같은 그림으로 보이지 않는다.
	var number := _stripe_color if earned else _pip_color.darkened(0.42)
	draw_circle(Vector2.ZERO, PIP_RADIUS, rim)
	draw_circle(Vector2.ZERO, PIP_RADIUS - 3.0, fill)
	_draw_centered(str(index + 1), Vector2(0.0, PIP_NUMBER_SIZE * 0.36), PIP_NUMBER_SIZE, number)


## 딴 사람의 이름. 흰 글자에 편 색 테두리를 둘러 어느 맵 위에서도 읽힌다.
##
## **테두리는 얇아야 한다.** 한글 획은 이 글자 크기에서 3px쯤이라, 테두리를 5px 주면
## 양쪽에서 획을 덮어 흰 속이 사라지고 글자가 통째로 진한 색이 된다.
func _draw_name(t: float) -> void:
	var alpha := clampf(t / TRAY_POP, 0.0, 1.0)
	if alpha <= 0.0:
		return
	_draw_centered(_scorer_name, Vector2(size.x * 0.5, NAME_Y), NAME_SIZE,
			Color(WHITE, alpha), 3, Color(_stripe_color.darkened(0.2), alpha))


## 젤리와 바닥 그림자. 그림자는 높이 올라갈수록 작고 옅어져서 "떠 있다"를 알려 준다.
func _draw_jelly(t: float) -> void:
	var state := _jelly_state(t)
	if state.is_empty():
		return
	var feet: Vector2 = state[0]
	var squash: Vector2 = state[1]

	var height := GROUND_Y - feet.y
	var near := clampf(1.0 - height / 420.0, 0.0, 1.0)
	if near > 0.0:
		draw_set_transform(Vector2(feet.x, GROUND_Y + 3.0), 0.0, Vector2(1.0, 0.22))
		draw_circle(Vector2.ZERO, 56.0 * (0.5 + 0.5 * near), Color(0.0, 0.0, 0.0, 0.24 * near))

	if _avatar != null and _avatar_region.size.x > 0.0 and _avatar_region.size.y > 0.0:
		var fit := minf(JELLY_HEIGHT / _avatar_region.size.y,
				JELLY_MAX_WIDTH / _avatar_region.size.x)
		var draw_size := _avatar_region.size * fit
		# 발밑이 원점이라 찌그러져도 바닥에서 떨어지지 않는다.
		draw_set_transform(feet, 0.0, squash)
		draw_texture_rect_region(_avatar, Rect2(Vector2(-draw_size.x * 0.5, -draw_size.y),
				draw_size), _avatar_region)
	else:
		# 원화가 없는 캐릭터도 장면은 돌아야 한다 — 편 색 방울로 대신한다.
		draw_set_transform(feet, 0.0, squash)
		draw_circle(Vector2(0.0, -JELLY_HEIGHT * 0.4), JELLY_HEIGHT * 0.4, _band_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 착지에서 벌어지는 일 전부: 바닥에 퍼지는 납작한 고리와 위로 튀는 방울.
func _draw_splash(t: float) -> void:
	if t < LAND_AT:
		return
	var a := t - LAND_AT
	var pip_x := _pip_center(_new_pip).x

	var ring_p := a / RING_TIME
	if ring_p < 1.0:
		var eased := 1.0 - pow(1.0 - ring_p, 2.5)
		var radius := lerpf(24.0, RING_RADIUS_FINAL if _is_final else RING_RADIUS, eased)
		draw_set_transform(Vector2(pip_x, GROUND_Y + 4.0), 0.0, Vector2(1.0, 0.26))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(WHITE, 0.9 * (1.0 - ring_p)),
				lerpf(12.0, 2.0, ring_p), true)
		if _is_final:
			draw_arc(Vector2.ZERO, radius * 0.7, 0.0, TAU, 48,
					Color(PIP_FILLED, 0.8 * (1.0 - ring_p)), lerpf(10.0, 2.0, ring_p), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var origin := Vector2(pip_x, TRAY_CENTER_Y - PIP_RADIUS)
	var count := DROP_COUNT_FINAL if _is_final else DROP_COUNT
	var fastest := 640.0 if _is_final else 470.0
	for i in count:
		var life := lerpf(0.55, 0.85, _rand(i, 3.0))
		if a >= life:
			continue
		# 위쪽 부채꼴로 흩어진다 — 아래로 쏘면 트레이에 묻힌다.
		var angle := lerpf(-2.95, -0.19, (float(i) + _rand(i, 1.0) * 0.8) / float(count))
		var velocity := Vector2.RIGHT.rotated(angle) * lerpf(250.0, fastest, _rand(i, 2.0))
		var pos := origin + velocity * a + Vector2(0.0, 0.5 * DROP_GRAVITY * a * a)
		var k := a / life
		var radius := lerpf(5.0 + 5.0 * _rand(i, 9.0), 1.5, k)
		var alpha := 1.0 if k < 0.7 else (1.0 - k) / 0.3
		# 금색과 편 색 방울이 번갈아 튄다. 진한 테두리를 한 겹 깔아야 밝은 맵에서도 보인다.
		var body := PIP_FILLED if i % 2 == 0 else WHITE.lerp(_band_color, 0.45)
		draw_circle(pos, radius + 2.0, Color(_stripe_color.darkened(0.15), 0.6 * alpha))
		draw_circle(pos, radius, Color(body, alpha))


## `+1 포인트!`. 착지에서 칸이 터진 뒤에 튀어나온다 — 먼저 뜨면 무엇 때문에 뜬 글자인지 모른다.
func _draw_gain_text(t: float) -> void:
	if t < LAND_AT:
		return
	var a := t - LAND_AT
	var pop := _back(a / 0.28)
	if pop <= 0.02:
		return
	var font_size := GAIN_SIZE_FINAL if _is_final else GAIN_SIZE
	# 튀어나오며 좌우로 흔들린 뒤 가만히 떠서 숨 쉰다.
	var tilt := 0.14 * exp(-6.0 * a) * sin(22.0 * a)
	var bob := 4.0 * sin(a * 6.0)
	draw_set_transform(Vector2(size.x * 0.5, GAIN_Y + bob), tilt, Vector2.ONE * pop)
	_draw_centered(GAIN_TEXT, Vector2(0.0, font_size * 0.36), font_size, WHITE,
			GAIN_OUTLINE, _stripe_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 마지막 3점째에만 쏟아지는 색종이. 위에서 흔들리며 떨어지고, 뒤집힐 때 얇아진다.
func _draw_confetti(t: float) -> void:
	if not _is_final or t < LAND_AT:
		return
	var a := t - LAND_AT
	var palette := [PIP_FILLED, WHITE, _band_color, _stripe_color.lightened(0.25)]
	for i in CONFETTI_COUNT:
		var fall := a - _rand(i, 4.0) * 0.35
		if fall < 0.0:
			continue
		var y := -20.0 + fall * lerpf(260.0, 430.0, _rand(i, 6.0))
		if y > size.y + 20.0:
			continue
		var x := size.x * (0.06 + 0.88 * _rand(i, 5.0)) + 26.0 * sin(fall * 5.0 + float(i))
		var angle := fall * lerpf(-9.0, 9.0, _rand(i, 7.0)) + float(i)
		var w := lerpf(8.0, 15.0, _rand(i, 8.0))
		var tumble := 0.25 + 0.75 * absf(sin(fall * 7.0 + float(i)))
		draw_set_transform(Vector2(x, y), angle, Vector2(1.0, tumble))
		draw_rect(Rect2(-w * 0.5, -w * 0.3, w, w * 0.6), palette[i % palette.size()])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 글자 하나를 가운데 맞춰 적는다. `outline` 이 0보다 크면 테두리를 먼저 두른다.
## `center` 는 글자의 가로 중심과 **밑선**이다.
##
## `Font` 쪽 함수가 아니라 `CanvasItem` 쪽을 쓴다 — 글자는 `draw_set_transform()` 으로
## 크기·기울기를 바꿔 가며 그리는데, RID 를 받는 `Font.draw_string()` 은 그 변형을 타지 않는다.
func _draw_centered(text: String, center: Vector2, font_size: int, color: Color,
		outline := 0, outline_color := Color(0, 0, 0, 0)) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var at := Vector2(center.x - width * 0.5, center.y)
	if outline > 0:
		draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
				outline, outline_color)
	draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


## 번호 `i` 와 갈래 `salt` 에서 0~1 값을 뽑는다. 상태를 들고 있지 않아서 같은 시각이면
## 늘 같은 모양이고, 사람(이름)마다 조금씩 다르다.
func _rand(i: int, salt: float) -> float:
	return fposmod(sin(float(i) * 12.9898 + (salt + _salt) * 78.233) * 43758.5453, 1.0)
