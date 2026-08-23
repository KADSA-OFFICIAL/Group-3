class_name WeaponSmoke
extends Node2D
## 손에 든 것이 평소와 다르다고 알리는 작은 연기 (빨간 표창·빨간 도끼, #134).
##
## **왜 Player의 `_draw()`가 아니라 별도 노드인가**: 씬 루트(`player.tscn`)에는 관통
## 빛무리용 가산 혼합이 걸려 있어서 거기서 그리면 연기가 아니라 빛이 된다. 연기는 배경을
## **덮어야** 연기로 보이므로 혼합이 걸리지 않은 자식에서 그린다 — 자식은 부모의
## `material`을 물려받지 않는다(`use_parent_material`이 기본 false다).
##
## 노드 순서상 `WeaponSprite` **뒤**에 있어서 무기 그림 위로 피어오른다.
##
## 켜고 끄는 것·위치·덩어리 수는 부모(`Player._update_weapon_smoke()`)가 정한다.
## 여기는 그리기만 한다.

## 흔들림 위상을 미리 뽑아 두는 수. `puff_count`의 상한이다.
##
## 무기마다 덩어리 수가 다른데(`smoke_puffs`) 바뀔 때마다 다시 뽑으면 씨앗이 흔들려
## 양쪽 화면의 모양이 갈린다. 넉넉히 뽑아 두고 앞에서부터 필요한 만큼만 쓴다.
const PHASE_POOL := 24
## 덩어리 하나가 올라가는 높이(px). 젤리(72px)의 3분의 1쯤 — "작은 연기"다.
const RISE := 26.0
## 덩어리 하나가 나서 사라지는 데 걸리는 시간(초).
const PERIOD := 1.3
## 갓 난 덩어리와 다 올라간 덩어리의 반지름(px). 올라가며 퍼진다.
const RADIUS_START := 2.5
const RADIUS_END := 8.0
## 올라가며 옆으로 흔들리는 폭(px).
const DRIFT := 6.0
## 가장 진할 때의 옅기. 1.0으로 두면 연기가 아니라 빨간 공이 된다.
const ALPHA := 0.5

## 부모가 넣어 준다. 기본값은 눈에 띄되 배경을 태우지 않는 붉은색이다.
var color := Color(0.82, 0.13, 0.11)
## 한 번에 떠 있는 연기 덩어리 수. 늘리면 연기가 짙어진다 (무기 표의 `smoke_puffs`).
## `PHASE_POOL`을 넘길 수 없다.
var puff_count := 5

var _time := 0.0
## 덩어리마다의 흔들림 위상. 노드 이름으로 씨앗을 잡아 **양쪽 화면에 같은 모양**이 뜬다
## (projectile.gd의 불꽃 가닥과 같은 방식). 올라가는 시각까지 맞출 필요는 없다 —
## 판정과 무관한 연출이고, 시각은 각 컴퓨터의 시계에서 나온다.
var _phases: Array[float] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_parent().name)
	for i in PHASE_POOL:
		_phases.append(rng.randf_range(0.0, TAU))


## 숨어 있으면 시간도 멈춘다 — 다시 켜질 때 덩어리들이 그 자리에서 이어 올라간다.
## 숨은 노드는 `_draw()`가 아예 불리지 않으므로 지우려고 한 번 더 그릴 필요가 없다
## (관통 빛무리는 같은 노드에 그려서 그 처리가 필요했다).
func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	var count := clampi(puff_count, 0, PHASE_POOL)
	for i in count:
		var phase: float = _phases[i]
		# 덩어리마다 시작 시각을 고르게 어긋내서 연기가 끊이지 않는다.
		var t := fposmod(_time / PERIOD + float(i) / float(count), 1.0)
		var radius := lerpf(RADIUS_START, RADIUS_END, t)
		var at := Vector2(sin(t * 3.0 + phase) * DRIFT * t, -RISE * t)
		# 갓 났을 때 툭 나타나지 않도록 앞부분에서 빠르게 짙어지고, 올라가며 사라진다.
		var alpha := ALPHA * (1.0 - t) * minf(t * 8.0, 1.0)
		# 옅고 넓은 것 위에 진한 심을 겹쳐 덩어리져 보이게 한다.
		draw_circle(at, radius * 1.6, Color(color, alpha * 0.35))
		draw_circle(at, radius, Color(color, alpha))
