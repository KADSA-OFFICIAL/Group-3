extends Control
## 포인트를 딴 순간에 한 번 뜨는 장면 (이슈 #273).
##
## 띠가 왼쪽에서 쓸려 들어와 딴 사람의 젤리 얼굴·이름·포인트 칸 세 개를 보여주고,
## **이번에 딴 칸**에 흰 빛이 터지며 금색으로 채워진다. 그 뒤에 `+1 포인트!` 가 뜬다.
##
## **띠 색은 보는 사람 기준이다** — 내가 땄으면 파랑, 상대가 땄으면 빨강. 서버가 보내는
## 신호는 하나인데 두 기기가 서로 다른 색을 띄운다. 어느 쪽이 땄는지를 글자로 읽지 않고
## 색으로 알아채게 하는 것이 이 장면의 요점이다 — 3점 선취가 이 게임의 유일한 승패
## 조건인데, 지금까지 점수가 오르는 순간에 바뀌는 것은 화면 맨 위 카드의 동그라미
## 하나뿐이어서 젤리를 보고 있던 눈에는 아무것도 안 들어왔다.
##
## 그림 파일 없이 `_draw()` 로만 그린다 (`light_burst.gd` 와 같은 방식) — 젤리 얼굴만
## 캐릭터 표에서 가져온다. **언제 띄울지는 서버가 정하고** 여기서는 보여주는 일만 한다
## (`main.gd` 의 `_on_player_died` → `_play_point_gain`) — `match_intro.gd` 와 같은 짜임이다.
##
## 화면을 실제로 흐리게(블러) 하지는 않는다. GL Compatibility 에서 화면 텍스처 블러는
## 셰이더가 필요하고 이 저장소의 연출은 전부 `_draw()` 로만 그린다 — 대신 옅은 흰 막을
## 깔아 뒤가 물러나게 한다. 어두운 맵(용암)에서도 띠와 글자가 뜨는 것은 이 막 덕분이다.

## 처음부터 끝까지 걸리는 시간(초). `Combat.POINT_GAIN_TIME` 을 그대로 쓴다 —
## 서버가 다음 판과 결과 화면을 이만큼 미루므로 두 값이 갈리면 장면이 잘리거나
## 빈 화면이 남는다. `match_intro.gd` 는 상수를 양쪽에 따로 두었는데, 그러면 한쪽만
## 고쳤을 때 조용히 어긋나므로 여기서는 한 곳만 두고 서버도 이것을 읽는다.
const TOTAL := Combat.POINT_GAIN_TIME

# ─────────────────────────── 배치 (기준 화면 1152×648) ───────────────────────────
## 띠의 위 경계와 높이(px). 화면 가운데에 걸치되 위쪽으로 조금 올려 잡았다 —
## 얼굴이 띠 위로 솟기 때문에 띠를 정가운데에 두면 덩어리가 아래로 처져 보인다.
const BAND_TOP := 246.0
const BAND_HEIGHT := 196.0
## 띠 맨 위를 지나는 진한 줄의 두께. 이것이 없으면 띠가 그냥 색 판때기로 보인다.
const STRIPE_HEIGHT := 22.0
## 쓸려 들어오는 앞머리의 가로 반지름. 클수록 코가 길어져 "쓸려 온다"로 읽힌다.
const NOSE_WIDTH := 96.0

## 얼굴 동그라미. **띠 위 경계에 걸친다** — 위쪽이 띠 밖으로 나오면서 띠 하나에
## 갇히지 않고, 그래서 얼굴이 이 장면의 주인공으로 읽힌다.
## 가로 위치는 상수로 두지 않고 `size.x` 에서 잰다 — 기준 화면(1152×648)에 박아 두면
## 뷰포트 크기를 손대는 날 얼굴만 가운데를 벗어난다.
const AVATAR_RADIUS := 62.0
const AVATAR_Y := 237.0
## 동그라미 안에서 젤리가 차지하는 비율. 1.0 이면 테두리에 닿아 갑갑하다.
const AVATAR_FILL := 0.78
## 테두리 두께.
const AVATAR_RIM := 4.0

## 이름 글자의 밑선과 크기.
const NAME_BASELINE := 334.0
const NAME_SIZE := 26

## 포인트 칸을 얹는 리본. 좌우가 화살처럼 들어가고 나온다.
const PLAQUE_TOP := 348.0
const PLAQUE_HEIGHT := 70.0
const PLAQUE_HALF := 134.0
## 좌우 화살의 깊이.
const PLAQUE_NOTCH := 22.0

## 포인트 칸. 3개가 가운데를 기준으로 좌우로 벌어진다.
const PIP_RADIUS := 24.0
const PIP_GAP := 68.0
const PIP_CENTER_Y := 383.0
const PIP_NUMBER_SIZE := 26

## `+1 포인트!` 글자. 얼굴 오른쪽 위, 띠보다 위에 뜬다 — 띠 안에 넣으면 이름·칸과
## 세 줄이 되어 어느 것을 봐야 하는지 알 수 없다.
const GAIN_TEXT := "+1 포인트!"
## 가로 위치는 화면 폭에 대한 비율이다 (얼굴과 같은 이유).
const GAIN_X_RATIO := 0.77
const GAIN_Y := 205.0
const GAIN_SIZE := 34
const GAIN_OUTLINE := 4

# ─────────────────────────── 시각표 (초) ───────────────────────────
## 띠가 화면을 다 건너는 데 걸리는 시간. 짧아야 "쓸려" 온다.
const SWEEP_IN := 0.22
## 띠 안의 것들이 나타나기 시작하는 시각과 걸리는 시간.
const CONTENT_AT := 0.16
const CONTENT_TIME := 0.20
## 빛덩이가 터지는 시각과 다 자라는 데 걸리는 시간.
const BURST_AT := 0.60
const BURST_GROW := 0.12
## 다 자란 채로 머무는 시간.
const BURST_HOLD := 0.06
## 칸 크기로 줄어드는 데 걸리는 시간.
const BURST_SHRINK := 0.22
## 칸이 금색으로 바뀌는 시각. 빛덩이가 거의 다 줄어든 뒤라야 "빛이 칸이 되었다"로 보인다.
const FILL_AT := 0.90
## 퍼지는 고리가 다 퍼지는 데 걸리는 시간.
const RING_TIME := 0.40
## `+1 포인트!` 가 뜨는 시각과 튀어나오는 데 걸리는 시간.
const GAIN_AT := 0.74
const GAIN_POP := 0.16
## 띠가 되돌아 빠져나가기 시작하는 시각. 들어온 길로 되돌아간다.
const SWEEP_OUT_AT := TOTAL - 0.30

# ─────────────────────────── 색 ───────────────────────────
## 내가 딴 포인트 — 파랑. 참고 영상(포켓몬 TCG 포켓)에서 뽑은 값이다.
const BAND_MINE := Color(0.055, 0.82, 1.0)
const STRIPE_MINE := Color(0.125, 0.49, 0.97)
const PLAQUE_MINE := Color(0.09, 0.69, 0.99)
const PIP_MINE := Color(0.145, 0.47, 0.89)
const PIP_RIM_MINE := Color(0.215, 0.54, 0.97)

## 상대가 딴 포인트 — 빨강. 파랑 쪽과 **같은 밝기·짙기 구조**로 색만 옮겼다.
## 밝기까지 낮추면 상대가 딸 때마다 화면이 어두워져 벌 받는 것처럼 보인다.
## 리본은 파랑 쪽보다 더 낮춰 잡았다 — 빨강은 초록 성분이 이미 거의 없어서 파랑 쪽처럼
## 초록만 조금 빼면(#0ED1FE → #17B1FC) 띠와 구별되지 않고 리본이 사라진다.
const BAND_THEIRS := Color(1.0, 0.30, 0.32)
const STRIPE_THEIRS := Color(0.86, 0.13, 0.24)
const PLAQUE_THEIRS := Color(0.84, 0.18, 0.27)
const PIP_THEIRS := Color(0.78, 0.15, 0.24)
const PIP_RIM_THEIRS := Color(0.89, 0.24, 0.32)

## 채워진 칸은 **양쪽 다 금색**이다. 포인트라는 물건의 색이라서 편에 따라 바뀌지 않는다 —
## 띠 색이 이미 누가 땄는지를 말하고 있고, 칸까지 같은 색이면 채워진 칸이 띠에 묻힌다.
const PIP_FILLED := Color(0.99, 0.88, 0.18)
const WHITE := Color(1.0, 1.0, 1.0)

## 전투 화면을 덮는 막의 가장 짙을 때 값.
const SCRIM_ALPHA := 0.55

## 빛덩이·고리가 칸 반지름의 몇 배까지 커지는지. 마지막 3점째는 훨씬 크게 터진다 —
## 참고 영상도 그렇고, 경기가 끝나는 포인트가 앞의 둘과 같은 크기로 지나가면
## 승부가 갈린 순간이 안 남는다.
const BALL_SCALE := 2.6
const BALL_SCALE_FINAL := 4.6
const RING_SCALE := 4.4
const RING_SCALE_FINAL := 9.0
## 마지막 포인트에만 뜨는, 화면을 훑고 지나가는 옅고 굵은 고리.
const HALO_SCALE_FINAL := 20.0

## 줄어드는 동안 빛덩이 안에서 뻗는 빛살의 개수.
const SPOKE_COUNT := 14
## 고리와 함께 바깥으로 튀어 나가는 짧은 흰 조각의 개수.
const SHARD_COUNT := 10

const RING_SEGMENTS := 48

## 이름·숫자를 적을 글꼴. 한글이 들어가므로 프로젝트 글꼴을 쓴다 —
## Godot 기본 글꼴에는 한글 글리프가 없어서 `+1 포인트!` 가 네모로 나온다.
##
## `_draw()` 로 그리는 글자는 테마를 타지 않으므로 여기서 직접 든다 (요청).
## 화면의 다른 글자와 같은 것을 써야 해서 테마가 쓰는 것과 같은 자원을 가리킨다 —
## `korean_font.tres`(계통 글꼴)를 직접 들면 이 장면만 옛 글꼴로 남는다.
const FONT := preload("res://resources/display_font.tres")

## 칸 위에서 빛이 터지는 순간. `main.gd` 가 이때 소리를 낸다 (이슈 #273).
##
## **소리를 여기서 직접 내지 않는다** — 소리 하나가 씬 하나이고 그 씬을 부르는 자리가
## 곧 소리가 나는 조건이라는 짜임을 지킨다(`sfx_oneshot.gd`). 그림 노드가 소리까지 들면
## 소리만 바꾸고 싶을 때 이 파일을 건드려야 한다(`match_intro.gd` 와 같은 이유).
##
## **장면이 열리는 순간이 아니라 빛이 터지는 순간이다.** 뽑아 둔 소리는 띠가 들어오는
## 소리가 아니라 칸이 채워지는 소리라서, 0초에 내면 소리가 그림보다 0.6초 앞선다.
##
## **채워지는 칸 번호(0부터)를 함께 싣는다.** 포인트마다 소리가 달라서 받는 쪽이 어느
## 소리인지 알아야 하는데, 그것을 `main.gd` 가 따로 기억하면 장면과 소리가 어긋날
## 자리가 하나 생긴다 — 장면이 자기가 채우는 칸을 그대로 말해 주면 그럴 수 없다.
signal burst_started(pip_index: int)

## 시작한 뒤 흐른 시간(초). 음수면 돌고 있지 않다.
var _elapsed := -1.0

var _scorer_name := ""
## 이번에 채워질 칸의 번호(0부터). 3점째면 2다.
var _new_pip := 0
var _is_final := false

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
## `as_gain` 이 이 장면의 색을 정한다 — 딴 사람이 나면(또는 관전자면) 파랑, 아니면 빨강.
## `score_after` 는 딴 **뒤의** 점수라서 채워질 칸은 그보다 하나 앞이다.
## `is_final` 이면 경기를 끝내는 포인트라 빛이 더 크게 터진다.
func play(scorer_name: String, character_id: String, score_after: int,
		as_gain: bool, is_final: bool) -> void:
	_scorer_name = scorer_name
	_new_pip = clampi(score_after - 1, 0, Combat.POINTS_TO_WIN - 1)
	_is_final = is_final
	# 이긴 포즈로 보여준다 (#176) — 포인트를 딴 사람의 얼굴이다.
	_avatar = Characters.pose_texture(character_id, Characters.POSE_WIN)
	_avatar_region = Art.content_rect(_avatar) if _avatar != null else Rect2()
	_apply_palette(as_gain)
	_elapsed = 0.0
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	var before := _elapsed
	_elapsed += delta
	# 빛이 터지는 시각을 **넘어선 그 프레임에** 한 번만 알린다. `_elapsed >= BURST_AT` 로
	# 보면 터진 뒤 매 프레임 소리가 나가고, 따로 깃발을 두면 `play()` 마다 되돌려야 한다.
	if before < BURST_AT and _elapsed >= BURST_AT:
		burst_started.emit(_new_pip)
	if _elapsed >= TOTAL:
		_elapsed = -1.0
		visible = false
		return
	queue_redraw()


func _apply_palette(as_gain: bool) -> void:
	_band_color = BAND_MINE if as_gain else BAND_THEIRS
	_stripe_color = STRIPE_MINE if as_gain else STRIPE_THEIRS
	_plaque_color = PLAQUE_MINE if as_gain else PLAQUE_THEIRS
	_pip_color = PIP_MINE if as_gain else PIP_THEIRS
	_pip_rim_color = PIP_RIM_MINE if as_gain else PIP_RIM_THEIRS


# ─────────────────────────── 그리기 ───────────────────────────
## 한 프레임의 모습은 시각 하나로 전부 정해진다 — `_elapsed` 만 박아 놓으면 그 순간이
## 그대로 그려지므로 미리보기 씬에서 원하는 대목을 골라 볼 수 있다.
func _draw() -> void:
	if _elapsed < 0.0:
		return
	var t := _elapsed
	var edge := _band_edge(t)
	if edge <= 0.0:
		return

	_draw_scrim(t)
	_draw_band(edge)

	var content := _content_alpha(t)
	if content <= 0.0:
		return
	_draw_plaque(content)
	for i in Combat.POINTS_TO_WIN:
		_draw_pip(i, t, content)
	_draw_avatar(t, content)
	_draw_name(content)
	_draw_burst(t, content)
	_draw_gain_text(t, content)


## 띠의 앞머리가 지금 어디까지 왔는가(px). 들어올 때는 왼쪽에서 오른쪽으로, 나갈 때는
## 같은 길을 되돌아간다 — 반대쪽으로 빼면 한 번 더 화면을 훑어서 두 동작으로 보인다.
func _band_edge(t: float) -> float:
	var full := size.x + NOSE_WIDTH
	if t < SWEEP_IN:
		# 뒤로 갈수록 느려진다 — 앞이 빨라야 쓸려 온 것으로 보인다.
		var p := t / SWEEP_IN
		return full * (1.0 - pow(1.0 - p, 3.0))
	if t < SWEEP_OUT_AT:
		return full
	var q := clampf((t - SWEEP_OUT_AT) / (TOTAL - SWEEP_OUT_AT), 0.0, 1.0)
	return full * (1.0 - q * q)


## 띠 안의 것들이 얼마나 진하게 보이는가. 띠가 자리를 잡은 뒤에 뒤따라 나타나고,
## 띠가 빠질 때는 먼저 사라진다 — 함께 움직이면 글자가 화면을 가로질러 날아간다.
func _content_alpha(t: float) -> float:
	if t < CONTENT_AT:
		return 0.0
	if t < CONTENT_AT + CONTENT_TIME:
		return (t - CONTENT_AT) / CONTENT_TIME
	if t < SWEEP_OUT_AT:
		return 1.0
	return clampf(1.0 - (t - SWEEP_OUT_AT) / (TOTAL - SWEEP_OUT_AT) * 2.2, 0.0, 1.0)


## 전투 화면을 덮는 옅은 흰 막. 띠보다 먼저 차고 나중에 빠진다.
func _draw_scrim(t: float) -> void:
	var alpha := SCRIM_ALPHA
	if t < 0.12:
		alpha *= t / 0.12
	elif t >= SWEEP_OUT_AT:
		alpha *= clampf(1.0 - (t - SWEEP_OUT_AT) / (TOTAL - SWEEP_OUT_AT), 0.0, 1.0)
	# 막에 띠 색을 아주 조금 섞는다 — 완전한 흰 막은 어느 맵에서나 같아서
	# 화면 전체가 이 장면의 편을 들고 있다는 느낌이 나지 않는다.
	var tint := WHITE.lerp(_band_color, 0.12)
	draw_rect(Rect2(Vector2.ZERO, size), Color(tint, alpha))


## 앞머리를 지난 띠. 진한 줄과 몸통을 같은 코 모양으로 잘라 한 덩어리로 보이게 한다.
func _draw_band(edge: float) -> void:
	draw_colored_polygon(_slab(BAND_TOP + STRIPE_HEIGHT, BAND_TOP + BAND_HEIGHT, edge),
			_band_color)
	draw_colored_polygon(_slab(BAND_TOP, BAND_TOP + STRIPE_HEIGHT, edge), _stripe_color)


## 앞머리가 `edge` 까지 온 상태에서 `y0`~`y1` 구간의 띠 조각.
##
## 코는 띠 전체 높이를 지름으로 하는 타원의 오른쪽 절반이다. 조각마다 따로 둥글리면
## 진한 줄과 몸통 사이에 계단이 생기므로, 높이는 항상 띠 전체를 기준으로 잰다.
func _slab(y0: float, y1: float, edge: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, y0))
	var steps := 12
	for i in steps + 1:
		var y := lerpf(y0, y1, float(i) / float(steps))
		pts.append(Vector2(_nose_x(y, edge), y))
	pts.append(Vector2(0.0, y1))
	return pts


func _nose_x(y: float, edge: float) -> float:
	var center_y := BAND_TOP + BAND_HEIGHT * 0.5
	var k := clampf((y - center_y) / (BAND_HEIGHT * 0.5), -1.0, 1.0)
	return maxf(edge - NOSE_WIDTH * (1.0 - sqrt(1.0 - k * k)), 0.0)


## 포인트 칸을 얹는 리본. 왼쪽은 파여 들어가고 오른쪽은 뾰족하게 나온다.
func _draw_plaque(alpha: float) -> void:
	var cx := size.x * 0.5
	var top := PLAQUE_TOP
	var bottom := PLAQUE_TOP + PLAQUE_HEIGHT
	var mid := (top + bottom) * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - PLAQUE_HALF, top),
		Vector2(cx + PLAQUE_HALF - PLAQUE_NOTCH, top),
		Vector2(cx + PLAQUE_HALF, mid),
		Vector2(cx + PLAQUE_HALF - PLAQUE_NOTCH, bottom),
		Vector2(cx - PLAQUE_HALF, bottom),
		Vector2(cx - PLAQUE_HALF + PLAQUE_NOTCH, mid),
	]), Color(_plaque_color, alpha))


func _pip_center(index: int) -> Vector2:
	var offset := (float(index) - float(Combat.POINTS_TO_WIN - 1) * 0.5) * PIP_GAP
	return Vector2(size.x * 0.5 + offset, PIP_CENTER_Y)


## 칸 하나. 이번에 딴 칸은 `FILL_AT` 을 지나서야 금색이 된다 — 그 전까지는 비어 있고
## 그 위를 빛덩이가 덮고 있다.
func _draw_pip(index: int, t: float, alpha: float) -> void:
	var center := _pip_center(index)
	var earned := index < _new_pip or (index == _new_pip and t >= FILL_AT)
	var fill := PIP_FILLED if earned else _pip_color
	var rim := WHITE if earned else _pip_rim_color
	# 금색 칸의 숫자는 띠의 진한 줄과 같은 색이다 — 편 색이 숫자에도 남아야
	# 파랑 판과 빨강 판이 같은 그림으로 보이지 않는다.
	var number := _stripe_color if earned else _pip_color.darkened(0.42)
	draw_circle(center, PIP_RADIUS, Color(rim, alpha))
	draw_circle(center, PIP_RADIUS - 3.0, Color(fill, alpha))
	_draw_centered(str(index + 1), center + Vector2(0.0, PIP_NUMBER_SIZE * 0.36),
			PIP_NUMBER_SIZE, Color(number, alpha))


## 띠 위로 솟은 얼굴 동그라미. 나타날 때 조금 크게 왔다가 제 크기로 내려앉는다.
func _draw_avatar(t: float, alpha: float) -> void:
	var center := Vector2(size.x * 0.5, AVATAR_Y)
	var pop := clampf((t - CONTENT_AT) / (CONTENT_TIME * 1.4), 0.0, 1.0)
	var scale_now := lerpf(1.22, 1.0, 1.0 - pow(1.0 - pop, 3.0))
	# 채워진 뒤에는 얼굴 뒤에서 옅은 빛이 번진다. 숨 쉬듯 흔들려야 멈춘 그림이 아니다.
	if t >= FILL_AT:
		var breathe := 0.6 + 0.4 * sin((t - FILL_AT) * 6.0)
		Art.draw_glow(self, center, AVATAR_RADIUS * 2.4, WHITE,
				0.22 * alpha * breathe, 20)
	draw_set_transform(center, 0.0, Vector2.ONE * scale_now)
	# 그림자를 먼저 깐다 — 없으면 얼굴이 띠에 박힌 스티커로 보인다.
	# **얇게 깐다.** 넓게 퍼뜨리면 바로 아래에 있는 이름 글자까지 어두워져서
	# 흰 글자가 회색 뭉치로 읽힌다 (처음 잡은 1.18·0.30 이 그랬다).
	Art.draw_glow(self, Vector2(0.0, 5.0), AVATAR_RADIUS * 1.08,
			_stripe_color.darkened(0.35), 0.22 * alpha, 12)
	draw_circle(Vector2.ZERO, AVATAR_RADIUS, Color(WHITE, alpha))
	draw_circle(Vector2.ZERO, AVATAR_RADIUS - AVATAR_RIM,
			Color(WHITE.lerp(_band_color, 0.16), alpha))
	if _avatar != null and _avatar_region.size.x > 0.0 and _avatar_region.size.y > 0.0:
		var box := AVATAR_RADIUS * 2.0 * AVATAR_FILL
		var fit := minf(box / _avatar_region.size.x, box / _avatar_region.size.y)
		var draw_size := _avatar_region.size * fit
		draw_texture_rect_region(_avatar, Rect2(-draw_size * 0.5, draw_size),
				_avatar_region, Color(WHITE, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 딴 사람의 이름. 흰 글자에 띠의 진한 줄 색으로 테두리를 둘러 띠 위에서도 읽힌다.
##
## **테두리는 얇아야 한다.** 한글 획은 이 글자 크기에서 3px쯤이라, 테두리를 5px 주면
## 양쪽에서 획을 덮어 흰 속이 사라지고 글자가 통째로 진한 색이 된다.
func _draw_name(alpha: float) -> void:
	_draw_centered(_scorer_name, Vector2(size.x * 0.5, NAME_BASELINE), NAME_SIZE,
			Color(WHITE, alpha), 3, Color(_stripe_color.darkened(0.2), alpha))


## `+1 포인트!`. 빛이 터진 뒤에 튀어나온다 — 먼저 뜨면 무엇 때문에 뜬 글자인지 모른다.
func _draw_gain_text(t: float, alpha: float) -> void:
	if t < GAIN_AT:
		return
	var p := clampf((t - GAIN_AT) / GAIN_POP, 0.0, 1.0)
	# 제 크기를 넘어섰다가 돌아온다. 곧바로 1.0에 멈추면 그냥 켜진 것으로 보인다.
	var scale_now := lerpf(1.35, 1.0, 1.0 - pow(1.0 - p, 3.0))
	draw_set_transform(Vector2(size.x * GAIN_X_RATIO, GAIN_Y), 0.0,
			Vector2.ONE * scale_now)
	_draw_centered(GAIN_TEXT, Vector2(0.0, GAIN_SIZE * 0.36), GAIN_SIZE,
			Color(WHITE, alpha), GAIN_OUTLINE, Color(_stripe_color, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 글자 하나를 가운데 맞춰 적는다. `outline` 이 0보다 크면 테두리를 먼저 두른다.
## `center` 는 글자의 가로 중심과 **밑선**이다.
##
## `Font` 쪽 함수가 아니라 `CanvasItem` 쪽을 쓴다 — 얼굴과 글자는 `draw_set_transform()`
## 으로 크기를 바꿔 가며 그리는데, RID 를 받는 `Font.draw_string()` 은 그 변형을 타지 않는다.
func _draw_centered(text: String, center: Vector2, font_size: int, color: Color,
		outline := 0, outline_color := Color(0, 0, 0, 0)) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var at := Vector2(center.x - width * 0.5, center.y)
	if outline > 0:
		draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
				outline, outline_color)
	draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


# ─────────────────────────── 빛이 터지는 대목 ───────────────────────────
## 이번에 딴 칸 위에서 벌어지는 일 전부. 흰 빛덩이가 부풀었다가 칸 크기로 줄어들고,
## 그 사이에 고리와 조각이 바깥으로 퍼진다. 줄어든 자리에 금색 칸이 남는다.
func _draw_burst(t: float, alpha: float) -> void:
	if t < BURST_AT:
		return
	var center := _pip_center(_new_pip)
	var ball_max := PIP_RADIUS * (BALL_SCALE_FINAL if _is_final else BALL_SCALE)
	var ring_max := PIP_RADIUS * (RING_SCALE_FINAL if _is_final else RING_SCALE)
	var age := t - BURST_AT

	if _is_final:
		_draw_halo(age, alpha)
	_draw_ring(age, ring_max, alpha)

	var radius := _ball_radius(age, ball_max)
	if radius <= 0.0:
		return
	Art.draw_glow(self, center, radius * 1.5, WHITE, 0.55 * alpha, 18)
	draw_circle(center, radius, Color(WHITE, alpha))
	# 줄어드는 동안에만 빛살이 보인다. 부푸는 동안에는 덩어리가 하얗게 차 있어 안 보인다.
	#
	# **빛덩이보다 나중에 그린다.** 먼저 그리면 덩어리와 그 빛무리가 살을 덮어 버려서
	# 아무리 밝게 뻗어도 화면에 한 줄도 안 남는다.
	var shrink_from := BURST_GROW + BURST_HOLD
	if age > shrink_from:
		var s := clampf((age - shrink_from) / BURST_SHRINK, 0.0, 1.0)
		_draw_spokes(center, radius, s, alpha)


## 빛덩이의 반지름. 부풀고, 머물고, 칸 크기로 줄어든다.
func _ball_radius(age: float, ball_max: float) -> float:
	if age < BURST_GROW:
		var p := age / BURST_GROW
		return ball_max * (1.0 - pow(1.0 - p, 3.0))
	if age < BURST_GROW + BURST_HOLD:
		return ball_max
	var q := clampf((age - BURST_GROW - BURST_HOLD) / BURST_SHRINK, 0.0, 1.0)
	if q >= 1.0:
		return 0.0
	# 뒤로 갈수록 빨리 줄어든다 — 앞에서 천천히 버텨야 "빨려 들어간다"로 읽힌다.
	return lerpf(ball_max, PIP_RADIUS, q * q)


## 바깥으로 퍼지는 흰 고리와 함께 튀어 나가는 짧은 조각들.
func _draw_ring(age: float, ring_max: float, alpha: float) -> void:
	if age < BURST_GROW:
		return
	var p := clampf((age - BURST_GROW) / RING_TIME, 0.0, 1.0)
	if p >= 1.0:
		return
	var eased := 1.0 - pow(1.0 - p, 2.5)
	var radius := lerpf(PIP_RADIUS, ring_max, eased)
	var fade := (1.0 - p) * alpha
	var center := _pip_center(_new_pip)
	draw_arc(center, radius, 0.0, TAU, RING_SEGMENTS, Color(WHITE, fade),
			lerpf(9.0, 1.5, p), true)
	for i in SHARD_COUNT:
		var angle := TAU * float(i) / float(SHARD_COUNT) + 0.21
		var dir := Vector2.RIGHT.rotated(angle)
		var from := center + dir * radius * 1.04
		draw_line(from, from + dir * lerpf(16.0, 4.0, p), Color(WHITE, 0.85 * fade),
				lerpf(4.0, 1.5, p))


## 마지막 포인트에만 뜨는 옅고 굵은 고리. 띠를 넘어 화면을 훑고 지나간다 —
## 경기가 끝나는 포인트라는 것을 칸 하나가 아니라 화면 전체로 말한다.
func _draw_halo(age: float, alpha: float) -> void:
	var p := clampf(age / (RING_TIME * 1.6), 0.0, 1.0)
	if p >= 1.0:
		return
	var radius := PIP_RADIUS * HALO_SCALE_FINAL * (1.0 - pow(1.0 - p, 2.0))
	draw_arc(_pip_center(_new_pip), radius, 0.0, TAU, RING_SEGMENTS,
			Color(WHITE, 0.30 * (1.0 - p) * alpha), lerpf(46.0, 8.0, p), true)


## 빛덩이 안에서 사방으로 뻗는 빛살. 덩어리가 줄어들면서 살이 드러난다.
func _draw_spokes(center: Vector2, radius: float, progress: float, alpha: float) -> void:
	var length := radius * lerpf(1.9, 1.1, progress)
	var fade := (1.0 - progress) * alpha
	for i in SPOKE_COUNT:
		var angle := TAU * float(i) / float(SPOKE_COUNT)
		var dir := Vector2.RIGHT.rotated(angle)
		var perp := dir.orthogonal()
		var half := radius * 0.10
		# 밑동은 넓고 끝은 한 점에 모이는 삼각형 — 끝으로 갈수록 투명해진다.
		draw_polygon(
			PackedVector2Array([
				center - perp * half,
				center + perp * half,
				center + dir * length,
			]),
			PackedColorArray([
				Color(WHITE, 0.75 * fade),
				Color(WHITE, 0.75 * fade),
				Color(WHITE, 0.0),
			]))
