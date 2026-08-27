extends Control
## 경기가 열릴 때 한 번 뜨는 표지 그림 (요청).
##
## **판마다가 아니라 경기마다 한 번이다** — 시작을 누르고 첫 무기 선택이 열리기 전,
## 딱 이 자리에서만 뜬다. 라운드마다 뜨면 2초가 여섯 번 붙어 경기가 그만큼 늘어진다.
##
## 화면에 띄우는 일만 한다. 언제 띄울지도, 그동안 무기 선택을 미루는 것도 서버가
## 정한다 (`main.gd`의 `_start_round` → `_play_match_intro`) — 무기 선택 카드
## (`weapon_pick.gd`)와 같은 짜임이다.

## 처음부터 끝까지 걸리는 시간(초). **서버의 `MATCH_INTRO_TIME`과 같아야 한다** —
## 서버는 이 시간만큼 무기 선택을 미루므로, 여기가 더 길면 그림이 덜 사라진 채로
## 카드가 뜨고 짧으면 빈 화면을 그만큼 본다.
const TOTAL := 2.0

## ── "둥" 하고 나오는 구간 ──
## 튀어나오는 데 걸리는 시간(초). 짧아야 친다 — 길면 부풀어 오르는 것이 된다.
const POP_TIME := 0.30
## 튀어나온 뒤 제 크기로 가라앉는 데 걸리는 시간(초).
const SETTLE_TIME := 0.14
## 시작 크기. 0에서 시작하면 점에서 자라 나오는 것이라 치는 맛이 없다.
const SCALE_FROM := 0.55
## 제 크기를 **넘어서** 갔다가 돌아온다. 이 되돌아옴이 "둥"의 정체다 —
## 곧바로 1.0에 멈추면 아무리 빨라도 그냥 켜진 것으로 보인다.
const SCALE_OVERSHOOT := 1.06

## ── 사라지는 구간 ──
## 사라지기 시작하는 시각(초).
const FADE_AT := 1.62
## 사라지면서 커지는 정도. 줄어들며 사라지면 빨려 들어가는 것이 되는데,
## 나올 때 이미 커지는 방향으로 쳤으므로 나갈 때도 같은 방향이라야 한 동작으로 읽힌다.
const SCALE_OUT := 1.12

## 뒤에 까는 어둠의 가장 짙을 때 값. 제 크기(scale 1.0)에서는 그림이 화면을 다 덮으므로
## (요청) 이것이 보이는 것은 **튀어나오는 동안과 사라지는 동안**이다 — 그때는 그림이
## 화면보다 작아서, 이 어둠이 없으면 전투 화면이 그림 옆으로 훤히 보인다.
const DIM_ALPHA := 0.72

@onready var _dim: ColorRect = $Dim
@onready var _art: TextureRect = $Art

## 시작한 뒤 흐른 시간(초). 음수면 돌고 있지 않다.
var _elapsed := -1.0


func _ready() -> void:
	visible = false


## 처음부터 다시 튼다. 소리는 `main.gd`가 따로 낸다 — 그림과 소리를 한 노드가
## 들고 있으면 소리만 바꾸고 싶을 때 이 파일을 건드려야 한다.
func play() -> void:
	_elapsed = 0.0
	visible = true
	# 크기를 **화면** 가운데 기준으로 바꾼다. `size`는 `_ready()` 시점에 아직 안 잡혀 있을
	# 수 있어 여기서 잡는다 — 띄우는 순간에는 배치가 끝나 있다.
	#
	# 그림 칸의 가운데가 아니라 화면의 가운데다 (요청). 그림이 화면에 꽉 차게 되면서
	# 3:2 원화가 16:9 화면보다 세로로 길어졌고, 위로 넘치는 만큼 칸이 화면 위로 나가
	# 있다 — 칸의 가운데를 축으로 잡으면 그림이 화면 가운데가 아닌 곳에서 튀어나온다.
	_art.pivot_offset = size * 0.5 - _art.position
	_apply(0.0)


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _elapsed >= TOTAL:
		_elapsed = -1.0
		visible = false
		return
	_apply(_elapsed)


## 한 프레임의 크기·옅기를 정한다. 시각 하나를 받아 모습 하나를 돌려주는 꼴이라
## 어느 순간이 어떻게 보이는지가 이 함수 하나에 다 있다.
func _apply(t: float) -> void:
	var scale_now := 1.0
	var alpha := 1.0
	if t < POP_TIME:
		# 뒤로 갈수록 느려진다(ease-out) — 앞이 빨라야 친 것으로 보인다.
		var p := t / POP_TIME
		var eased := 1.0 - pow(1.0 - p, 3.0)
		scale_now = lerpf(SCALE_FROM, SCALE_OVERSHOOT, eased)
		# 옅기는 크기보다 빨리 채운다. 반투명하게 커지면 부푸는 것으로 보인다.
		alpha = minf(p * 2.2, 1.0)
	elif t < POP_TIME + SETTLE_TIME:
		var q := (t - POP_TIME) / SETTLE_TIME
		scale_now = lerpf(SCALE_OVERSHOOT, 1.0, 1.0 - pow(1.0 - q, 2.0))
	elif t >= FADE_AT:
		var r := (t - FADE_AT) / (TOTAL - FADE_AT)
		scale_now = lerpf(1.0, SCALE_OUT, r)
		alpha = 1.0 - r
	_art.scale = Vector2.ONE * scale_now
	_art.modulate.a = alpha
	# 어둠은 그림보다 **먼저 차고 먼저 빠진다** — 같이 움직이면 그림이 사라지는 동안
	# 뒤가 훤히 드러나 전투 화면이 먼저 보인다.
	_dim.color.a = DIM_ALPHA * minf(alpha * 1.4, 1.0)
