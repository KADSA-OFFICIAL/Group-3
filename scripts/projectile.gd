class_name Projectile
extends Area2D
## 허공을 나는 것 (화살·총알·표창·산탄·던진 단검·폭탄 등).
##
## 서버만 이동과 판정을 하고, 클라이언트는 동기화된 위치를 그린다.
## 상대 무기에 막히지 않는다 — 회피로만 피한다.
##
## 스폰·디스폰은 main.gd의 ProjectileSpawner(MultiplayerSpawner)가 맡는다.
## 서버에서 queue_free()하면 클라이언트에서도 함께 사라진다.

## 서버가 이 투사체를 없애야 할 때 알린다.
signal finished(projectile: Node)
## 바닥에 남은 것(단검)을 주인이 주웠다.
signal picked_up(peer_id: int, projectile: Node)
## 빨간 표창이 자리를 바꾼다. 두 값은 **바꾸기 전의** 위치다 — 연출을 두 자리에 띄우는
## 쪽(`main.gd`)이 쓴다. 여기서 직접 RPC를 부르지 않는 것은 연출이 `Effects` 아래에
## 붙어야 하고 그 노드를 아는 것이 main.gd이기 때문이다 (검 특수의 빛기둥과 같다).
##
## **바꾸기 전, 그리고 때리기 전에 낸다** — 받는 쪽이 공용 피격음을 삼키고 자기 소리로
## 그 자리를 대신하는데, 그 공용 피격음을 내는 것이 `server_apply_hit` 이다. 아래
## `impacted` 와 같은 순서이고 이유도 같다. 그래서 "바꿨다"가 아니라 "바꾼다"이다:
## 맞은 젤리가 쓰러지면 이 신호가 나간 뒤에도 실제 교환은 일어나지 않는다.
signal swapped(from_position: Vector2, to_position: Vector2)
## 번개를 부르는 탄(삼지창 특수)이 맞혔다. 값은 **맞은 젤리의 발밑**이다 —
## 번개가 거기로 내려온다. 연출을 띄우는 쪽이 `main.gd`인 이유는 위 `swapped`와 같다.
signal struck(at: Vector2)
## 알갱이를 튀기는 탄(단검)이 맞혔다. 값은 **날이 닿은 자리**다 — 발밑으로 내려오는
## 번개와 달리 맞은 그 점에서 튄다. 연출을 띄우는 쪽이 `main.gd`인 이유는 위와 같다.
signal sparked(at: Vector2)
## 푸른 충격을 터뜨리는 탄(대포 총)이 맞혔다. 값은 **탄이 닿은 자리**다 — 기준이
## 알갱이(`sparked`)와 같다. 연출을 띄우는 쪽이 `main.gd`인 이유도 같다.
signal burst(at: Vector2)
## 틱 소리를 내는 탄(소총 연사)이 맞혔다. **자리를 싣지 않는다** — 위의 셋은 맞은 자리에
## 그림을 띄우지만 이쪽은 소리뿐이라 좌표가 쓸 데가 없다.
signal ticked
## **자기만의 피격음**을 가진 탄(소총 기본)이 맞혔다. `ticked` 와 같이 자리를 싣지 않는다 —
## 소리뿐이라 좌표가 쓸 데가 없다.
##
## **`server_apply_hit` 보다 먼저 낸다** (아래 `_on_body_entered` 참고). 받는 쪽이 공용
## 피격음의 자리를 대신해야 하는데, 그 공용 피격음을 내는 것이 `server_apply_hit` 이다.
signal impacted
## 폭탄이 터졌다 (도화선이 다 타서든 닿아서든).
##
## **터진 자리와 반경을 싣는다** (#262). 전에는 소리뿐이라 좌표가 쓸 데가 없었지만,
## 폭발 연출(`bomb_blast.tscn`)이 붙으면서 어디서 얼마만큼 터졌는지가 필요해졌다 —
## 그 둘은 판정에 쓰는 값 그대로다(`_explode()` 참고). 연출을 `main.gd`가 띄우는 것은
## 위와 같은 이유다: 연출은 `Effects` 아래에 붙어야 하고 그 노드를 아는 것이 저쪽이다.
signal exploded(at: Vector2, blast_radius: float)

## 폭발 반경 표시 노드의 타입 (#140). `class_name` 대신 preload 로 받는다 —
## 전역 클래스 이름은 에디터가 만드는 `.godot` 캐시에 등록되어야 풀리므로,
## 캐시가 없는 상태(새로 받은 저장소·헤드리스 실행)에서 이 스크립트가 통째로 파싱되지 않는다.
const BlastRadiusNode := preload("res://scripts/blast_radius.gd")
## 떨어진 단검의 오라 노드 타입 (#250). 위와 같은 이유로 `class_name` 대신 preload 다.
const DropAuraNode := preload("res://scripts/drop_aura.gd")

## 허공을 나는 것은 공유 무적을 타지 않는다. 항상 "projectile" 이다.
const SOURCE := "projectile"
## 단검을 주울 수 있는 거리. **떨어진 단검을 감싸는 붉은 오라의 반지름이 곧 이 값이다**
## (`drop_aura.gd` — `_ready()`에서 넘긴다). 보이는 범위와 주워지는 범위가 같아야 한다.
##
## 48 → **36** (#256). 48은 젤리 몸통(48px)과 같은 값이라 지름 96px의 원이 젤리보다
## 두 배 넓게 깔려서, 화면에서 단검보다 오라가 먼저 보였다. 줄인 것은 원이 아니라
## **거리**다 — 원만 줄이면 테두리 밖에서도 주워져 표시가 거짓말이 된다.
## 주우려면 12px(몸통의 4분의 1, 걸음 속도로 0.04초) 더 다가가야 한다.
const PICKUP_RANGE := 36.0
## 중력을 받는 것(표창·폭탄·떨어진 단검)에 적용할 가속도.
const GRAVITY := 980.0

## 바닥에 닿은 뒤 굴러가기 시작하는 속도(px/s) — `on_solid = "roll"` (#131).
const ROLL_SPEED := 300.0
## 구르면서 받는 감속(px/s^2). 굴러가는 거리는 이 둘이 정한다:
## 거리 = ROLL_SPEED^2 / (2 * ROLL_FRICTION) = 60px. 젤리 몸통(48px) 하나 조금 넘는다.
const ROLL_FRICTION := 750.0
## 무기 그림으로 그릴 때 날 끝에서 손잡이 끝까지의 길이(px). 젤리 몸통(48px)보다 조금 짧다.
const ART_LENGTH := 40.0

# ─────────────────────── 미사일 불꽃 꼬리 (대포 총 특수, #121) ───────────────────────
## 불꽃 꼬리의 전체 길이(px). `size_scale`이 곱해진다. 젤리 몸통(72px)의 두 배 가까이 되어야
## 날아가는 동안 "긴 꼬리"로 읽힌다 — 짧으면 그냥 밝은 점으로 보인다.
const FLAME_LENGTH := 132.0
## 불꽃이 가장 불룩한 곳의 반폭(px).
const FLAME_HALF_WIDTH := 20.0
## 불꽃이 가장 굵어지는 지점(0~1). 머리에서 조금 뒤에서 부풀었다가 꼬리로 뾰족해진다.
const FLAME_BELLY := 0.16
## 머리 쪽(t=0) 폭의 비율. 0이면 한 점에서 시작해 불꽃이 끊겨 보인다.
const FLAME_ROOT_RATIO := 0.30
## 꼬리 윤곽을 몇 조각으로 나눠 그릴지. 클수록 매끄럽다.
const FLAME_SEGMENTS := 16
## 미사일 머리의 빛무리 반지름(px).
const HEAD_RADIUS := 13.0
## 꼬리 안에서 흐르는 가는 불꽃 가닥 수.
const WISP_COUNT := 6
## 불꽃이 떠는 속도(라디안/초). 빠를수록 타오르는 느낌이 난다.
const FLAME_FLICKER_RATE := 24.0

## 가운데는 하얗고 바깥으로 갈수록 푸르다.
const FLAME_CORE := Color(1.0, 1.0, 1.0)
const FLAME_MID := Color(0.72, 0.94, 1.0)
const FLAME_EDGE := Color(0.25, 0.60, 1.0)

# ─────────────────────────── 결정질 화살 (활, #125) ───────────────────────────
## 화살 전체 길이(px). 길쭉해야 "결정 창"으로 읽힌다 — 짧으면 마름모 덩어리가 된다.
const ARROW_LENGTH := 60.0
## 가장 넓은 곳의 반폭(px). 길이의 1/8쯤이라 날렵하다.
const ARROW_HALF_WIDTH := 7.5
## 앞에서부터 이 비율 되는 곳이 가장 넓다(어깨). 여기서 뒤로는 한 점으로 좁아진다.
const ARROW_SHOULDER_RATIO := 0.34
## 어깨 뒤 이 비율 되는 곳에 곁가지 결정이 붙는다.
const ARROW_SHARD_RATIO := 0.62
## 뒤에 남는 짧은 빛 자락의 길이(px). 미사일 꼬리보다 훨씬 짧다 — 화살이지 로켓이 아니다.
const ARROW_TRAIL_LENGTH := 52.0

# ─────────────────────── 파란 에너지 구슬 (대포 총 기본) ───────────────────────
## 구슬의 알맹이 반지름(px). `size_scale`이 곱해진다 — 대포 총은 2.0 이라 지름 44px,
## 젤리 몸통(48px)에 조금 못 미치는 크기로 날아간다.
const ORB_RADIUS := 11.0
## 알맹이를 감싸는 빛무리의 반지름 배수. 1.0 이면 빛무리가 없어 그냥 원판이 된다.
const ORB_GLOW_RATIO := 2.1
## 구슬이 커졌다 작아지며 뛰는 폭(반지름 대비). 크기가 고정이면 굴러가는 공처럼 보인다.
const ORB_PULSE := 0.10
## 구슬이 뛰는 속도(라디안/초). 불꽃이 떠는 속도(24)보다 느려야 "타오르는 것"이 아니라
## "뭉쳐 있는 에너지"로 읽힌다.
const ORB_PULSE_RATE := 11.0
## 뒤에 남는 짧은 빛 자락의 길이(px). 화살 자락(52)보다도 짧다 — 구슬이지 로켓이 아니다.
const ORB_TRAIL_LENGTH := 30.0

## 구슬 색. 가운데가 희고 가장자리로 갈수록 파랗다 — 미사일 불꽃과 같은 결이다.
const ORB_CORE := Color(1.0, 1.0, 1.0)
const ORB_MID := Color(0.45, 0.78, 1.0)
const ORB_EDGE := Color(0.12, 0.38, 1.0)

## 결정 색. 가운데가 희고 가장자리가 짙푸르다.
const ARROW_CORE := Color(1.0, 1.0, 1.0)
const ARROW_MID := Color(0.55, 0.88, 1.0)
const ARROW_EDGE := Color(0.20, 0.45, 0.95)

## 쏜 플레이어의 peer id. 자기 자신은 맞지 않는다.
var shooter_peer := 0
var damage := 0.0
var knockback := Combat.Knockback.WEAK
var stun := 0.0
## 상대를 관통해서 계속 날아가는가 (활 특수).
var pierce_targets := false
var use_gravity := false
## 벽·바닥에 닿았을 때 — "vanish" 사라짐 / "stay" 남음 / "return" 즉시 회수.
var on_solid := "vanish"
## 거리에 따라 데미지가 줄어드는 무기(샷건)용. 0 이면 감소 없음.
var falloff_min_damage := 0.0
var falloff_distance := 0.0
## 이 peer의 젤리를 자동으로 따라간다 (단검). 0 이면 직선.
var homing_peer := 0
## 이 시간이 지나면 스스로 터진다 (폭탄). 0 이면 안 터진다.
var fuse := 0.0
## 터질 때 이 반경 안을 때린다 (폭탄). 0 이면 단발 명중.
## 이 값이 그대로 `BlastRadius`에 넘어가 화면에도 그려진다 (#140).
var explosion_radius := 0.0
## 바닥에 남았을 때 이 peer의 주인이 주울 수 있다 (단검).
var pickup_owner := 0
## 이 무기의 그림으로 그린다 (단검). 비어 있거나 그림이 없는 무기면 노란 막대로 그린다.
var art_weapon: String = ""
## 이 **파일**의 그림으로 그린다 (폭탄). `art_weapon`보다 우선한다 —
## 무기 하나에 그림이 둘일 때(일반/강화 폭탄) 이름만으로는 고를 수 없다 (#131).
var art_file: String = ""
## 그림을 진행 방향으로 돌리지 않는다 (폭탄). 돌리면 도화선이 앞을 향한다 (#131).
var art_upright := false
## 원화의 앞이 **위가 아니라 오른쪽**이다 (로켓 글러브, #161).
## 기본값(false)은 지금까지처럼 날 끝이 위를 향하는 원화다 — `_face()` 참고.
var art_points_right := false
## 그림을 **날아가는 내내 돌린다**(초당 라디안). 0이면 안 돈다 — 지금까지의 탄이 그렇다.
##
## 던진 방패를 원반처럼 보이게 하는 값이다. 진행 방향으로 한 번 돌려 두는
## `_face()`와 **함께 쓸 수 없다** — 돌리는 쪽이 이긴다.
## 도는 쪽은 날아가는 쪽을 따른다(오른쪽으로 던지면 시계 방향).
var art_spin := 0.0
## 맞으면 데미지 대신 쏜 쪽과 맞은 쪽의 위치를 맞바꾼다 (빨간 표창).
var swap_positions := false
## 맞은 자리에 번개가 내려친다 (삼지창 특수). 데미지·기절은 그대로고 연출만 붙는다.
var hit_lightning := false
## 맞은 자리에 빨간 알갱이가 튄다 (단검, #250). 위와 같이 연출만 붙는 값이다.
var hit_sparks := false
## 이만큼 날아가면 사라진다 (로켓 글러브). 0 이면 제한 없음 — 지금까지의 투사체가 그렇다.
var max_distance := 0.0
## 탄 크기 배율 (대포 총). 1.0 이면 씬에 잡아 둔 기본 크기다.
var size_scale := 1.0
## **그림만** 키우는 배율 (폭탄, #149). `size_scale`과 달리 충돌 상자를 건드리지 않는다 —
## 판정은 그대로 두고 눈에만 잘 띄게 하려는 값이다.
var art_scale := 1.0
## 푸른 불꽃 꼬리를 단 미사일로 그린다 (대포 총 특수, #121).
var missile := false
## 푸른 결정질 화살로 그린다 (활, #125).
var arrow := false
## 파란 에너지 구슬로 그린다 (대포 총 기본). `missile`이 켜져 있으면 그쪽이 이긴다 —
## 특수는 불꽃 꼬리 미사일이고 이 값은 기본 공격 탄에만 보인다.
var orb := false
## 맞은 자리에 푸른 충격이 터진다 (대포 총). `hit_sparks`와 같이 연출만 붙는 값이다.
var hit_burst := false
## 맞을 때마다 짧은 틱 소리를 낸다 (소총 연사). 위와 같이 판정에 닿지 않는 값이다.
var tick_sfx := false
## 맞은 순간 **이 무기만의 피격음**을 낸다 (소총 기본). 위와 같이 판정에 닿지 않는다.
##
## 위의 `tick_sfx` 와 다른 값인 것은 켜지는 자리가 다르기 때문이다 — 틱은 소총 **연사**에,
## 이쪽은 소총 **기본**에 붙는다. 하나로 묶으면 연사 한 발마다 두 소리가 겹친다.
var impact_sfx := false
## 0보다 크면 넉백 단계 대신 이 속도로 민다 (대포 총 미사일, #121).
var knockback_speed := 0.0

var velocity := Vector2.ZERO

## 벽·바닥에 닿아 그 자리에 멈췄는가 (`on_solid` 이 "stay"·"roll" 인 것).
##
## **판정은 서버만 하지만 이 값은 복제된다** (씬의 `Sync` 설정) — 떨어진 단검 주변에
## 도는 오라(#250)를 두 화면이 각자 그려야 하고, 클라이언트는 속도를 받지 않아서
## 스스로는 멈춘 것을 알 수 없다. 스폰 상태에도 실려서, 경기 중에 들어온 관전자는
## 이미 떨어져 있던 단검의 오라를 바로 본다 (#182).
##
## 그래서 이름에 밑줄이 없다 — 서버만 보는 값이 아니라 `position` 처럼 양쪽이 보는 값이다.
var landed := false

## 이번 **물리** 프레임에 움직이기 직전의 자리 (#270). 겹침은 움직인 뒤에 알려지므로,
## 이 자리가 곧 **지형 밖인 것이 보장된 마지막 자리**다 — 옆·아래로 부딪힌 단검을
## 여기로 되돌려 놓고 떨어뜨린다.
##
## 뒤로 물러날 거리를 상수로 잡지 않는 이유: 한 프레임에 나아가는 거리는 속도에 따라
## 다르고(유도 단검은 1120px/s 라 한 프레임에 19px 다), 상수로 잡으면 빠른 탄은 덜
## 물러나 지형 안에 남고 느린 탄은 너무 멀리 튄다.
##
## **아래의 `_last_position` 과 다른 값이다.** 그쪽은 그림이 바라볼 방향을 잡으려고
## `_process`(렌더 프레임)에서 갱신하는 것이라 물리 한 걸음과 박자가 맞지 않는다.
var _step_start := Vector2.ZERO

var _spawn_time := 0.0
var _origin := Vector2.ZERO
var _hit_peers := {}
var _done := false
var _has_art := false
var _last_position := Vector2.ZERO
## 불꽃을 그릴 진행 방향(단위 벡터). 꼬리는 이 반대쪽으로 뻗는다.
var _draw_dir := Vector2.RIGHT
## 그림이 도는 쪽 (`art_spin`). 날아가는 쪽을 따라 +1/-1 이다.
var _spin_dir := 1.0
var _flame_time := 0.0
var _wisps: Array[Dictionary] = []

@onready var visual: ColorRect = $Visual
@onready var art_sprite: Sprite2D = $ArtSprite
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var blast_radius: BlastRadiusNode = $BlastRadius
@onready var drop_aura: DropAuraNode = $DropAura


## 모든 피어에서 스폰 데이터로 호출된다 (add_child 전).
func setup(data: Dictionary) -> void:
	shooter_peer = data["shooter_peer"]
	damage = data["damage"]
	knockback = data["knockback"]
	stun = data.get("stun", 0.0)
	pierce_targets = data.get("pierce_targets", false)
	use_gravity = data.get("use_gravity", false)
	on_solid = data.get("on_solid", "vanish")
	falloff_min_damage = data.get("falloff_min_damage", 0.0)
	falloff_distance = data.get("falloff_distance", 0.0)
	homing_peer = data.get("homing_peer", 0)
	fuse = data.get("fuse", 0.0)
	explosion_radius = data.get("explosion_radius", 0.0)
	pickup_owner = data.get("pickup_owner", 0)
	art_weapon = data.get("art", "")
	art_file = data.get("art_file", "")
	art_upright = data.get("art_upright", false)
	art_points_right = data.get("art_points_right", false)
	art_spin = data.get("art_spin", 0.0)
	swap_positions = data.get("swap_positions", false)
	hit_lightning = data.get("hit_lightning", false)
	hit_sparks = data.get("hit_sparks", false)
	hit_burst = data.get("hit_burst", false)
	tick_sfx = data.get("tick_sfx", false)
	impact_sfx = data.get("impact_sfx", false)
	max_distance = data.get("max_distance", 0.0)
	size_scale = data.get("size_scale", 1.0)
	art_scale = data.get("art_scale", 1.0)
	missile = data.get("missile", false)
	arrow = data.get("arrow", false)
	# **미사일이 구슬을 이긴다.** 대포 총은 무기 표에 `projectile_orb`(기본·특수 공통
	# 자리)와 `special_missile`을 둘 다 두어서, 특수 탄에는 두 값이 함께 실려 온다.
	# 여기서 갈라 두지 않으면 아래 `_draw()`가 두 모양을 겹쳐 그린다.
	# **`missile` 을 읽은 뒤에 와야 한다** — 순서를 바꾸면 이 조건이 늘 참이 된다.
	orb = data.get("orb", false) and not missile
	knockback_speed = data.get("knockback_speed", 0.0)
	velocity = data["velocity"]
	position = data["position"]
	_origin = position


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 전투 화면에 있는 피어에게만 보낸다 (이슈 #182). `public_visibility` 는 건드리지 않는다 —
	# 끄면 필터가 참이어도 아무에게도 안 보인다(이슈 #167에서 투사체가 통째로 사라졌다).
	if multiplayer.is_server():
		$Sync.add_visibility_filter(Lobby.can_view)
	_spawn_time = _now()
	_last_position = position
	_step_start = position
	_apply_art()
	_apply_size()
	# 터질 때 때리는 범위를 그려 둔다 (#140). 반경이 있는 것은 폭탄뿐이고
	# 나머지는 0이라 아무것도 그리지 않는다. **미사일·화살보다 먼저** 넘긴다 —
	# 그쪽은 바로 아래에서 함수를 빠져나간다.
	blast_radius.radius = explosion_radius
	# 떨어진 단검의 오라도 같은 방식으로 반경을 넘겨받는다 (#256). **오라가 자기 상수를
	# 두지 않는다** — 테두리가 곧 주워지는 경계라서 같은 숫자가 두 곳에 있으면 언젠가
	# 갈라지고, 그때 표시가 거짓말이 된다(양날 도끼 충격파가 `landing_radius`를
	# 넘겨받는 것과 같은 이유). 폭탄 반경처럼 이것도 함수를 빠져나가기 전에 넘긴다.
	drop_aura.radius = PICKUP_RANGE
	if _is_drawn():
		_setup_drawn()
		return
	# 도는 그림은 첫 프레임부터 날아가는 쪽으로 돌아야 한다 — 위치 변화가 아직 없어서
	# `_process()`의 갱신이 한 프레임 늦는다.
	if not is_zero_approx(art_spin) and not is_zero_approx(velocity.x):
		_spin_dir = signf(velocity.x)
	if _has_art:
		_face(velocity)
	elif velocity.x < 0.0:
		visual.position.x = -visual.size.x


## 무기 그림을 붙인다. 그림이 없으면 지금까지의 노란 막대를 그대로 쓴다.
##
## 원화는 정사각 캔버스에 투명 여백을 두고 그려져 있어 파일 크기를 그대로 쓰면 그림이
## 한쪽으로 쏠린다. 캐릭터·무기와 같이 `Art.content_rect()`로 여백을 뺀 영역을 기준으로 잡되,
## 여기서는 회전을 하므로 위치가 아니라 `Sprite2D.offset`(회전과 함께 도는 값)으로 보정한다.
func _apply_art() -> void:
	# 파일 지정이 무기 이름보다 우선한다 (일반/강화 폭탄).
	var texture: Texture2D = null
	if not art_file.is_empty():
		texture = Weapons.texture_file(art_file)
	elif not art_weapon.is_empty():
		texture = Weapons.texture(art_weapon)
	if texture == null:
		return
	var content := Art.content_rect(texture)
	if content.size.y <= 0.0:
		return
	var texture_size := Vector2(texture.get_size())
	art_sprite.texture = texture
	art_sprite.offset = texture_size * 0.5 - content.position - content.size * 0.5
	# `art_scale`은 여기서만 곱한다 (#149) — `_apply_size()`의 `size_scale`과 달리
	# 충돌 상자에는 닿지 않으므로 판정이 그대로다.
	art_sprite.scale = Vector2.ONE * (ART_LENGTH / content.size.y) * art_scale
	_has_art = true
	visual.hide()
	art_sprite.show()


## 탄 크기를 배율만큼 키운다 (대포 총, #118).
##
## **그림과 판정을 함께** 키워야 보이는 크기와 실제로 맞는 범위가 어긋나지 않는다.
##
## 충돌 상자(RectangleShape2D)는 씬의 sub_resource라 **모든 투사체가 같은 자원을 공유한다** —
## `shape.size`를 직접 고치면 대포 총 탄 하나 때문에 활·샷건 탄까지 같이 커지고,
## 그 무기로 갈아타도 크기가 돌아오지 않는다. 그래서 모양이 아니라 노드의 `scale`을 바꾼다.
func _apply_size() -> void:
	if is_equal_approx(size_scale, 1.0):
		return
	collision_shape.scale = Vector2.ONE * size_scale
	if _has_art:
		art_sprite.scale *= size_scale
		return
	# 노란 막대는 세로 가운데가 원점이라, 키운 뒤 다시 가운데로 맞춰야 한다.
	visual.size *= size_scale
	visual.position.y = -visual.size.y * 0.5


## 그림 방향 맞추기. 원화는 날 끝이 위를 향하므로 진행 방향으로 90도 더 돌린다.
##
## 앞이 **오른쪽**인 원화(로켓 글러브)는 그 90도를 더하면 안 된다 (#161) — 그냥 진행
## 방향 각도가 곧 회전값이다. 왼쪽으로 쏘면 180도가 되어 주먹이 왼쪽, 분사가 오른쪽에 온다.
func _face(direction: Vector2) -> void:
	if not is_zero_approx(art_spin):
		return   # 던진 방패 — 계속 도는 그림이라 방향으로 굳히면 안 된다
	if art_upright:
		return   # 폭탄 — 돌리면 도화선이 앞을 향한다 (#131)
	if direction.length_squared() < 0.01:
		return   # 멈춰 있으면 마지막 방향 그대로 (바닥에 꽂힌 단검)
	if art_points_right:
		art_sprite.rotation = direction.angle()
		return
	art_sprite.rotation = direction.angle() + PI * 0.5


## 그리기는 모든 피어가 한다. 클라이언트는 속도를 받지 않으므로 복제된 위치의
## 변화로 진행 방향을 잡는다 — 유도(단검)로 방향이 바뀌어도 그림이 따라 돈다.
func _process(delta: float) -> void:
	# 떨어져서 주울 수 있는 단검 주변의 오라 (#250). `landed` 가 복제되므로 두 화면에
	# 같이 뜬다. **아래 일찍 돌아가는 조건보다 앞에 둔다** — 그 조건은 그림이 있는
	# 탄만 통과시키는데, 오라는 그림과 상관없이 켜지고 꺼져야 한다.
	drop_aura.active = landed and pickup_owner != 0
	# **`arrow`를 빠뜨리지 말 것** (#257). 화살은 그림 파일 없이 `_draw()`로만 그려서
	# `_has_art`도 `missile`도 아니라, 여기서 돌아가면 아래의 `_draw_dir` 갱신과
	# `queue_redraw()`를 한 번도 지나지 않는다 — 발사 각도(위로 15도)로 굳은 채 날아가
	# 내려가는 구간에서 그림과 진행 방향이 어긋난다. `_draw()`도 아래 갱신 블록도
	# 미사일과 화살을 나란히 다루는데 이 줄에만 빠져 있었다.
	if not _has_art and not _is_drawn():
		return
	var moved := position - _last_position
	_last_position = position
	if _has_art and not is_zero_approx(art_spin):
		# 원반처럼 도는 그림 (던진 방패). **위치 변화로 도는 쪽을 잡는다** —
		# 클라이언트는 속도를 받지 않아서, 스폰 때 실려 온 방향만으로는 되돌아오거나
		# 휘는 탄에서 어긋난다 (`_face()`가 방향을 다시 잡는 것과 같은 이유).
		# 멈춰 있으면 마지막 방향 그대로 계속 돈다.
		if absf(moved.x) > 0.01:
			_spin_dir = signf(moved.x)
		art_sprite.rotation += art_spin * _spin_dir * delta
	elif _has_art:
		_face(moved)
	if _is_drawn():
		# 유도(단검)나 포물선(활)처럼 방향이 바뀌는 것에도 그림이 따라 돌도록
		# 위치 변화로 진행 방향을 잡는다. 화살촉이 궤도를 따라 기울어진다.
		if moved.length_squared() >= 0.01:
			_draw_dir = moved.normalized()
		_flame_time += delta
		queue_redraw()


## 그림 파일 없이 `_draw()`로 그리는 탄인가 (미사일·화살·구슬).
##
## **세 곳이 이 조건을 함께 쓴다** — `_ready()`의 준비, `_process()`의 방향 갱신,
## 그리고 `_draw()`. 조건을 늘어놓고 쓰다가 한 곳에 화살을 빠뜨려 발사 각도로 굳은 채
## 날아간 일이 있었다(#257). 새 모양을 붙일 때 고칠 곳이 하나여야 그 일이 안 되풀이된다.
func _is_drawn() -> bool:
	return missile or arrow or orb


## 직접 그리는 탄(미사일·화살) 준비. 노란 막대는 이들이 대신하므로 감춘다.
##
## 불꽃 가닥 모양은 노드 이름(`Projectile_<id>`)으로 씨앗을 잡은 난수라 **양쪽 화면에 같게**
## 뜬다. 이름은 스폰 데이터의 id에서 나오므로 모든 피어에서 같다.
func _setup_drawn() -> void:
	visual.hide()
	if velocity.length_squared() >= 0.01:
		_draw_dir = velocity.normalized()
	if not missile:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for i in WISP_COUNT:
		_wisps.append({
			# 본줄기 안에서 흐르게 각을 좁게 잡는다 — 넓으면 옆으로 삐친 선으로 보인다.
			"angle": rng.randf_range(-0.16, 0.16),
			"length": rng.randf_range(0.62, 1.05),
			"width": rng.randf_range(0.10, 0.24),
			"rate": rng.randf_range(11.0, 19.0),
			"phase": rng.randf_range(0.0, TAU),
		})


## 미사일과 푸른 불꽃 꼬리 (#121).
##
## 그림 파일 없이 `_draw()`로만 그린다 — 씬 루트에 걸린 가산 혼합 덕에 겹칠수록 하얗게
## 타오르고, 그 혼합은 **이 그리기에만** 적용되어 자식(`Visual`·`ArtSprite`)에는 영향이 없다.
##
## **노드를 회전시키지 않고** 방향 벡터로 직접 그린다. 루트를 돌리면 `CollisionShape2D`까지
## 같이 돌아 판정이 달라진다 — 연출 때문에 맞는 범위가 변하면 안 된다.
func _draw() -> void:
	if arrow:
		_draw_arrow()
		return
	if orb:
		_draw_orb()
		return
	if not missile:
		return
	var back := -_draw_dir
	var perp := back.orthogonal()
	var flicker := 0.85 + 0.15 * sin(_flame_time * FLAME_FLICKER_RATE)
	var length := FLAME_LENGTH * size_scale * flicker
	var half := FLAME_HALF_WIDTH * size_scale

	# 넓고 푸른 것부터 좁고 흰 것까지 겹쳐 가운데를 하얗게 태운다.
	_draw_plume(back, perp, length, half, FLAME_EDGE, 0.50)
	_draw_plume(back, perp, length * 0.78, half * 0.60, FLAME_MID, 0.60)
	_draw_plume(back, perp, length * 0.50, half * 0.32, FLAME_CORE, 0.90)

	# 꼬리 안에서 흐르는 가는 가닥. 본줄기 위에 얹어 결을 만든다.
	for wisp: Dictionary in _wisps:
		var rate: float = wisp["rate"]
		var phase: float = wisp["phase"]
		var angle: float = wisp["angle"]
		var wisp_length: float = wisp["length"]
		var wisp_width: float = wisp["width"]
		var dir := back.rotated(angle + sin(_flame_time * rate + phase) * 0.05)
		_draw_plume(dir, dir.orthogonal(), length * wisp_length, half * wisp_width,
			FLAME_CORE, 0.22)

	# 머리 — 불꽃이 뿜어져 나오는 밝은 덩어리.
	Art.draw_glow(self, Vector2.ZERO, HEAD_RADIUS * size_scale * 1.7, FLAME_EDGE, 0.50)
	Art.draw_glow(self, Vector2.ZERO, HEAD_RADIUS * size_scale, FLAME_MID, 0.70)
	Art.draw_glow(self, Vector2.ZERO, HEAD_RADIUS * size_scale * 0.45, FLAME_CORE, 1.0)


## 불꽃 덩어리 하나. 머리 뒤에서 불룩해졌다가 꼬리로 갈수록 뾰족해지며 투명해진다.
##
## 사다리꼴 하나로 그리면 옆선이 곧아서 "막대"로 보인다. 윤곽을 여러 조각으로 나눠
## 폭과 옅기를 따로 주면 덩어리진 불꽃이 된다.
func _draw_plume(back: Vector2, perp: Vector2, length: float, half: float,
		color: Color, alpha: float) -> void:
	if length <= 0.0 or half <= 0.0:
		return
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	# 한쪽 윤곽을 머리에서 꼬리로 훑고,
	for i in FLAME_SEGMENTS + 1:
		var t := float(i) / float(FLAME_SEGMENTS)
		points.append(back * (length * t) + perp * (half * _plume_width(t)))
		colors.append(Color(color, alpha * _plume_alpha(t)))
	# 반대쪽 윤곽을 꼬리에서 머리로 되짚어 하나의 폴리곤으로 닫는다.
	for i in range(FLAME_SEGMENTS, -1, -1):
		var t := float(i) / float(FLAME_SEGMENTS)
		points.append(back * (length * t) - perp * (half * _plume_width(t)))
		colors.append(Color(color, alpha * _plume_alpha(t)))
	draw_polygon(points, colors)


## 꼬리 위치별 폭(0~1). FLAME_BELLY에서 가장 굵고 꼬리 끝에서 0이 된다.
func _plume_width(t: float) -> float:
	var rise := clampf(t / FLAME_BELLY, 0.0, 1.0)
	var fall := clampf((1.0 - t) / (1.0 - FLAME_BELLY), 0.0, 1.0)
	var swell := FLAME_ROOT_RATIO + (1.0 - FLAME_ROOT_RATIO) * pow(rise, 0.6)
	return swell * pow(fall, 0.85)


## 꼬리 위치별 옅기(0~1). 머리 쪽이 진하고 꼬리로 갈수록 사라진다.
func _plume_alpha(t: float) -> float:
	return pow(1.0 - t, 1.35)


## 파란 에너지 구슬 (대포 총 기본 공격).
##
## 미사일·화살과 같은 규칙이다 — 그림 파일 없이 `_draw()`로만 그리고, **노드를 회전시키지
## 않는다**(루트를 돌리면 `CollisionShape2D`까지 돌아 판정이 달라진다). 구슬은 원이라
## 돌릴 것도 없지만, 뒤에 남는 자락은 진행 방향을 봐야 하므로 `_draw_dir`을 쓴다.
##
## **바깥에서 안으로 겹쳐 쌓는다.** 씬 루트의 가산 혼합에서는 겹친 만큼 밝아지므로,
## 파란 빛무리 위에 옅은 하늘색, 그 위에 흰 알맹이를 얹으면 테두리는 파랗고 가운데는
## 하얗게 타는 동그라미가 된다 — 파랑을 알맹이에 칠하면 가산 혼합에 씻겨 하얗게만 남는다.
func _draw_orb() -> void:
	var pulse := 1.0 + ORB_PULSE * sin(_flame_time * ORB_PULSE_RATE)
	var radius := ORB_RADIUS * size_scale * pulse

	# 진행 방향 뒤로 짧게 끌리는 자락. 구슬만 있으면 날아가는 것이 아니라 떠 있는 것으로
	# 보인다 — 미사일 꼬리(132px)와 달리 구슬 지름 남짓이라 "동그라미"를 흐리지 않는다.
	_draw_plume(-_draw_dir, _draw_dir.orthogonal(),
		ORB_TRAIL_LENGTH * size_scale, radius * 0.55, ORB_EDGE, 0.45)

	# 번져 나가는 파란 빛무리. 알맹이보다 두 배 넓어서 어두운 배경에서도 원으로 읽힌다.
	Art.draw_glow(self, Vector2.ZERO, radius * ORB_GLOW_RATIO, ORB_EDGE, 0.55)
	# 알맹이. 파랑 → 하늘 → 흰 순으로 좁혀 가며 가운데를 태운다.
	draw_circle(Vector2.ZERO, radius, Color(ORB_EDGE, 0.95))
	draw_circle(Vector2.ZERO, radius * 0.72, Color(ORB_MID, 0.85))
	draw_circle(Vector2.ZERO, radius * 0.40, Color(ORB_CORE, 0.95))


## 결정질 화살 (#125).
##
## 미사일과 같은 규칙이다 — 그림 파일 없이 `_draw()`로만 그리고, **노드를 회전시키지 않는다**
## (루트를 돌리면 `CollisionShape2D`까지 돌아 판정이 달라진다).
## 진행 방향은 위치 변화로 잡으므로 **포물선을 따라 화살촉이 기울어진다.**
##
## 같은 윤곽을 크기만 줄여 세 번 겹친다. 가산 혼합이라 겹칠수록 밝아져서
## 가장자리는 짙푸르고 가운데는 흰 결정처럼 보인다.
func _draw_arrow() -> void:
	var forward := _draw_dir
	var perp := forward.orthogonal()
	# 뒤로 남는 짧은 빛 자락. 화살이 지나온 길을 알려 주되 로켓처럼 길면 안 된다.
	_draw_plume(-forward, perp, ARROW_TRAIL_LENGTH * size_scale,
		ARROW_HALF_WIDTH * size_scale * 0.7, ARROW_EDGE, 0.30)
	Art.draw_glow(self, Vector2.ZERO, ARROW_LENGTH * size_scale * 0.38, ARROW_EDGE, 0.35)
	# 겹칠 때 **폭을 길이보다 많이** 줄인다. 그래야 흰 심이 길이를 따라 남아
	# 가운데가 하얗게 빛나는 결정이 된다 — 둘 다 줄이면 심이 작은 덩어리가 된다.
	_draw_arrow_body(forward, perp, size_scale, size_scale, ARROW_EDGE, 0.55)
	_draw_arrow_body(forward, perp, size_scale * 0.88, size_scale * 0.58, ARROW_MID, 0.75)
	_draw_arrow_body(forward, perp, size_scale * 0.72, size_scale * 0.28, ARROW_CORE, 0.95)


## 화살 윤곽 한 겹 — 앞이 뾰족하고 어깨에서 가장 넓다가 **뒤로도 한 점으로** 좁아지는
## 결정 창. 뒤를 뭉툭하게 두거나 날개를 달면 촉이 둘 달린 것처럼 보인다.
func _draw_arrow_body(forward: Vector2, perp: Vector2,
		length_scale: float, width_scale: float, color: Color, alpha: float) -> void:
	var half_length := ARROW_LENGTH * 0.5 * length_scale
	var half_width := ARROW_HALF_WIDTH * width_scale
	var tip := forward * half_length
	var tail := -forward * half_length
	var shoulder := forward * (half_length - ARROW_LENGTH * ARROW_SHOULDER_RATIO * length_scale)
	var tint := Color(color, alpha)

	# 본체 — 앞뒤로 뾰족한 연꼴
	draw_polygon(
		PackedVector2Array([
			tip,
			shoulder + perp * half_width,
			tail,
			shoulder - perp * half_width,
		]),
		PackedColorArray([tint, tint, tint, tint]))

	# 곁가지 결정 — 몸통 뒤쪽에서 바깥·뒤로 삐져나온 얇은 조각
	var shard := forward * (half_length - ARROW_LENGTH * ARROW_SHARD_RATIO * length_scale)
	var out := perp * half_width * 1.8
	var back := forward * half_width * 1.6
	draw_polygon(
		PackedVector2Array([shard, shard + out - back, shard - back * 0.7]),
		PackedColorArray([tint, tint, tint]))
	draw_polygon(
		PackedVector2Array([shard, shard - out - back, shard - back * 0.7]),
		PackedColorArray([tint, tint, tint]))


func _physics_process(delta: float) -> void:
	# 이동은 서버만 계산한다. 클라이언트는 동기화된 위치를 받는다.
	if not multiplayer.is_server() or _done:
		return

	# 도화선 (폭탄) — 바닥에 놓여 있어도 시간이 되면 터진다.
	if fuse > 0.0 and _now() - _spawn_time >= fuse:
		_explode()
		return

	# 바닥에 닿은 뒤 굴러가는 것 (폭탄) — 감속해서 스스로 멈춘다.
	if landed and on_solid == "roll" and not is_zero_approx(velocity.x):
		var speed := maxf(absf(velocity.x) - ROLL_FRICTION * delta, 0.0)
		velocity.x = signf(velocity.x) * speed
		position += velocity * delta

	# 바닥에 남은 것은 주인이 다가오면 회수된다 (단검).
	if landed:
		if pickup_owner != 0:
			var owner_jelly := _find_jelly(pickup_owner)
			if owner_jelly != null and position.distance_to(owner_jelly.global_position) <= PICKUP_RANGE:
				_done = true
				picked_up.emit(pickup_owner, self)
		return

	# 유도 (단검) — 상대를 향해 방향을 계속 고친다.
	if homing_peer != 0:
		var target := _find_jelly(homing_peer)
		if target != null:
			velocity = (target.global_position - position).normalized() * Combat.PROJECTILE_SPEED

	if use_gravity:
		velocity.y += GRAVITY * delta
	# 옮기기 **전에** 지금 자리를 적어 둔다 (#270) — 겹침은 옮긴 뒤에 알려지므로,
	# 그때 되돌아갈 곳은 이 자리다.
	_step_start = position
	position += velocity * delta

	# 정해진 거리를 다 날아가면 사라진다 (로켓 글러브, #161). 기획서가 "단거리 발사"라
	# 못박은 무기를 화면 끝까지 보내지 않기 위한 것이다.
	if max_distance > 0.0 and _origin.distance_to(position) >= max_distance:
		_finish()
		return

	# 맵에서 완전히 벗어나면 정리한다.
	var screen := get_viewport_rect().size
	if Combat.is_out_of_bounds(position, screen) or position.y < -Combat.FALL_MARGIN_SIDE:
		_finish()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _find_jelly(peer_id: int) -> Node:
	for jelly: Node in get_tree().get_nodes_in_group("jellies"):
		if jelly.owner_peer_id == peer_id:
			return jelly
	return null


## 빨간 표창 — 맞은 쪽과 던진 쪽의 자리를 맞바꾼다. **서버에서만 부른다.**
##
## 던진 쪽이 이미 죽었거나(낙사 등) 나가 버렸으면 아무 일도 일어나지 않는다.
## 살아 있지 않은 젤리를 옮기면 사망 연출이 엉뚱한 자리에서 끝난다.
##
## 두 위치를 **옮기기 전에 먼저 읽어 둔다** — 하나를 옮긴 뒤에 다른 쪽을 읽으면
## 둘 다 같은 자리로 겹친다.
##
## **`swapped` 를 여기서 내지 않는다.** 그 신호는 때리기보다 먼저 나가야 해서
## 부르는 쪽(`_on_body_entered`)이 낸다 — 아래 `_swap_shooter()` 와 짝인 주석 참고.
func _swap_with_shooter(shooter: Node, target: Node) -> void:
	var shooter_at: Vector2 = shooter.global_position
	var target_at: Vector2 = target.global_position
	shooter.server_teleport(target_at)
	target.server_teleport(shooter_at)


## 빨간 표창이 자리를 바꿀 상대(쏜 사람)를 찾는다. 없으면 `null` 이다 —
## 이미 죽었거나(낙사 등) 나가 버린 경우다. 살아 있지 않은 젤리를 옮기면
## 사망 연출이 엉뚱한 자리에서 끝난다.
func _swap_shooter() -> Node:
	var shooter := _find_jelly(shooter_peer)
	if shooter == null or not shooter.alive:
		return null
	return shooter


## 폭탄 — 반경 안의 상대를 때리고 사라진다.
func _explode() -> void:
	if _done:
		return
	# 소리와 연출은 **맞은 젤리가 있든 없든** 난다 — 빗나간 폭탄도 터지는 것은 마찬가지다.
	# 그래서 아래 반경 판정보다 앞에 둔다. `_done` 검사 뒤라 두 번 나지 않는다.
	#
	# 싣는 두 값은 **바로 아래 판정이 쓰는 그것과 같다** (#262) — 연출의 고리가 닿는
	# 자리가 곧 맞는 경계여야 하므로, 여기서 따로 계산하지 않고 같은 변수를 넘긴다.
	exploded.emit(position, explosion_radius)
	for jelly: Node in get_tree().get_nodes_in_group("jellies"):
		if jelly.owner_peer_id == shooter_peer or not jelly.alive:
			continue
		if position.distance_to(jelly.global_position) <= explosion_radius:
			jelly.server_apply_hit(damage, knockback, position.x, stun, SOURCE, knockback_speed)
	_finish()


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server() or _done:
		return

	if body is Player:
		var peer_id: int = body.owner_peer_id
		if peer_id == shooter_peer or _hit_peers.has(peer_id) or not body.alive:
			return
		# 폭탄은 닿으면 터진다 (문서: "피격하거나 일정 시간이 지나면").
		if explosion_radius > 0.0:
			_explode()
			return
		# 방패를 크게 들어 올린 상대는 앞에서 오는 탄을 막는다 (`Player.is_guarding`).
		# **폭탄보다 뒤에 둔다** — 반경으로 흩뿌리는 것은 막기를 거치지 않는 것이
		# 이 게임의 규칙이다(샷건 부채꼴·도끼 착지 충격파와 같은 취급).
		if _guarded_by(body):
			_blocked(body)
			return
		_hit_peers[peer_id] = true
		# 빨간 표창은 때린 **뒤에** 자리를 바꾼다. 예전에는 데미지가 0이라 때리기를
		# 통째로 건너뛰었는데, 지금은 일반 표창과 같은 데미지가 들어간다.
		#
		# **때리는 것이 먼저다** — 넉백 기준이 `_origin.x`(던진 자리)라, 자리를 먼저
		# 바꾸면 맞은 젤리가 이미 그 자리에 서 있어 밀리는 방향이 뒤집힌다.
		# (지금 넉백은 0이지만, 수치를 바꿔도 순서 때문에 어긋나지는 않게 둔다.)
		if swap_positions:
			# 바꿀 상대(쏜 사람)가 아직 있는지를 **때리기 전에** 본다. 없으면 이 표창은
			# 평범한 표창처럼 때리기만 하고 끝난다 — 소리도 연출도 없다.
			var shooter := _swap_shooter()
			if shooter != null:
				# **때리기보다 먼저 낸다** — 받는 쪽(`main.gd`)이 공용 피격음을 삼키고
				# 자기 소리(`shuriken_swap`)로 그 자리를 대신하는데, 그 공용 피격음을
				# 내는 것이 바로 아래 `server_apply_hit` 이기 때문이다. 소총 탄의
				# `impacted` 와 **완전히 같은 순서**이고, 이유도 같다.
				#
				# 싣는 두 위치는 **바꾸기 전의** 것이라 지금 재는 것이 맞다 —
				# 아래 `_swap_with_shooter()` 가 옮긴 뒤에는 둘 다 어긋난다.
				swapped.emit(shooter.global_position, body.global_position)
			body.server_apply_hit(_damage_at(position), knockback, _origin.x, stun, SOURCE, knockback_speed)
			# **쓰러졌으면 옮기지 않는다** — 그 표창이 끝낸 판에서 시체를 옮기는 꼴이 되고,
			# 라운드 정리와 순간이동이 같은 순간에 겹친다. 소리와 연출은 위에서 이미
			# 나갔으므로, 맞는 순간에 무슨 표창이었는지는 화면에 남는다.
			if shooter != null and body.alive:
				_swap_with_shooter(shooter, body)
			_finish()
			return
		# 이 무기만의 피격음 (소총 기본). **때리기보다 먼저 낸다** — 받는 쪽(`main.gd`)이
		# 이 순간의 공용 피격음을 막아 자리를 대신하는데, 그 공용 피격음을 내는 것이 바로
		# 아래 `server_apply_hit` 이기 때문이다. 근접 부딪힘 소리와 같은 순서다.
		#
		# 여기까지 왔으면 **맞는 것이 확정이다** — 쏜 사람·이미 맞힌 상대·쓰러진 젤리·
		# 방패는 위에서 다 걸러졌고, 탄은 공유 무적을 타지 않는다.
		if impact_sfx:
			impacted.emit()
		body.server_apply_hit(_damage_at(position), knockback, _origin.x, stun, SOURCE, knockback_speed)
		# 번개는 맞은 젤리의 **발밑**으로 떨어진다 (검 특수의 빛기둥과 같은 기준).
		if hit_lightning:
			struck.emit(body.global_position + Vector2(0.0, Player.BODY_BOTTOM))
		# 알갱이는 **날이 닿은 자리**에서 튄다 (#250) — 번개처럼 발밑으로 내려보내면
		# 어디에 맞았는지가 아니라 어디에 서 있었는지가 남는다.
		if hit_sparks:
			sparked.emit(position)
		# 푸른 충격도 **탄이 닿은 자리**에서 터진다 (대포 총) — 알갱이와 같은 기준이다.
		if hit_burst:
			burst.emit(position)
		# 소총 연사의 틱 소리. 자리가 필요 없어 인자가 없다.
		if tick_sfx:
			ticked.emit()
		# 주울 수 있는 것(단검)은 맞힌 뒤에도 사라지지 않고 바닥으로 떨어진다.
		# 안 그러면 한 번만 쓸 수 있는 무기가 된다.
		if pickup_owner != 0:
			homing_peer = 0
			velocity = Vector2.ZERO
			use_gravity = true
			return
		if not pierce_targets:
			_finish()
		return

	# 벽·바닥·기물
	match on_solid:
		"vanish", "return":
			_finish()
		"stay":
			# **위에서 내려앉은 것만 그 자리에 남는다** (#270). 전에는 어디에 닿았는지를
			# 가리지 않고 멈춰서, 옆면이나 밑면에 닿은 단검이 공중에 매달렸다 —
			# 회수 거리(36px) 안에 들어갈 방법이 없어 그 라운드 내내 기본 공격이 막혔다.
			# 바다의 가운데 기둥과 벽돌의 뜬 발판에서 실제로 걸렸다.
			if _landed_on_top(body):
				velocity = Vector2.ZERO
				landed = true
			else:
				_slip_off()
		"roll":
			# 세로 속도만 죽이고 가로로 조금 굴린다 (#131).
			# **가지고 있던 속도를 넘겨받지 않고 ROLL_SPEED 로 깎는다** — 안 그러면
			# 1120px/s 로 날아온 폭탄이 화면을 가로질러 굴러간다.
			# 발판을 벗어났다 다시 떨어진 경우에는 남은 속도가 더 작으므로 그쪽을 쓴다.
			var keep := minf(absf(velocity.x), ROLL_SPEED)
			velocity = Vector2(signf(velocity.x) * keep, 0.0)
			landed = true


## 이 지형의 **윗면에 내려앉았는가** (#270).
##
## 판단 기준은 속도가 아니라 **직전 자리**다. 아래로 내려오던 중이었는지만 보면 유도
## 단검이 자기보다 낮은 상대를 쫓다가 기둥 옆면을 들이받는 경우를 가려내지 못한다 —
## 그때도 세로 속도는 아래쪽이다. 겹치기 직전에 윗면보다 위에 있었다면 그것은 위에서
## 내려앉은 것이고, 아니면 옆이나 아래에서 닿은 것이다.
##
## 지형이 어떤 모양인지 못 읽으면 지금까지의 어림(내려오던 중이었는가)으로 돌아간다.
## 맵 네 개는 모두 `StaticBody2D` + `CollisionShape2D`(사각형)이지만, 나중에 다른 모양이
## 들어와도 이 함수 때문에 탄이 이상해지지는 않아야 한다.
func _landed_on_top(body: Node) -> bool:
	var shape := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		return velocity.y > 0.0
	var box := shape.shape as RectangleShape2D
	if box == null:
		return velocity.y > 0.0
	var top := shape.global_position.y - box.size.y * 0.5
	return _step_start.y <= top


## 지형에 옆·아래로 부딪혔다 — 붙이지 말고 떨어뜨린다 (#270).
##
## **겹치기 직전 자리로 되돌린다.** 겹친 채로 두면 다시 `body_entered` 가 오지 않아서
## 언제 바닥에 닿았는지 알 수 없고, 그대로 아래로 내려보내면 지형을 뚫고 지나간다.
##
## 유도도 여기서 끊는다 — 안 끊으면 다음 프레임에 상대 쪽으로 방향을 다시 잡아
## 같은 벽을 계속 들이받는다.
func _slip_off() -> void:
	homing_peer = 0
	position = _step_start
	# 가로 속도까지 지운다. 벽을 타고 미끄러져 내려가야 하는데 가로로 남아 있으면
	# 떨어지면서 다시 그 벽으로 파고든다.
	velocity = Vector2.ZERO
	use_gravity = true


## 이 젤리가 방패를 들어 **이 탄을 막고 있는가** (방패 특수).
##
## 자세만으로는 부족하고 **앞에서 와야 막힌다** — 근접 막기(`Main.is_blocked()`)가
## "등을 보이고 있으면 못 막는다"인 것과 같은 기준이다. 방패를 들었다고 등 뒤까지
## 가려지면 4초 동안 무적이 된다.
##
## 오는 방향은 진행 방향(`velocity.x`)의 반대다. 가로로 거의 안 움직이는 탄
## (곧게 떨어지는 것)은 앞뒤를 가릴 수 없으므로 막지 않는다.
func _guarded_by(jelly: Player) -> bool:
	if not jelly.is_guarding():
		return false
	if absf(velocity.x) < 1.0:
		return false
	return signf(float(jelly.facing)) == signf(-velocity.x)


## 방패에 막혔다. 데미지도 넉백도 없다.
##
## 주울 수 있는 탄(단검)은 없애지 않고 **발밑에 떨어뜨린다** — 맞혔을 때와 같은
## 처리다. 없애면 막히는 것만으로 상대의 단검이 영구히 사라져 한 번만 쓸 수 있는
## 무기가 된다.
func _blocked(jelly: Player) -> void:
	if pickup_owner != 0:
		homing_peer = 0
		velocity = Vector2.ZERO
		use_gravity = true
		_hit_peers[jelly.owner_peer_id] = true   # 떨어지는 동안 다시 닿아도 조용하다
		return
	_finish()


## 굴러서 발판 끝을 벗어났다 — 다시 떨어진다 (#131).
##
## 이게 없으면 폭탄이 발판 밖 허공을 그대로 굴러간다. 떨어지다 아래 바닥에 닿으면
## `_on_body_entered`가 다시 굴리는데, 그때는 남은 속도가 더 작아 조금만 구른다.
func _on_body_exited(body: Node) -> void:
	if not multiplayer.is_server() or _done or not landed:
		return
	if on_solid != "roll" or body is Player:
		return
	landed = false


## 샷건처럼 거리에 따라 데미지가 줄어드는 경우.
func _damage_at(where: Vector2) -> float:
	if falloff_distance <= 0.0:
		return damage
	var traveled: float = _origin.distance_to(where)
	var t: float = clampf(traveled / falloff_distance, 0.0, 1.0)
	return lerpf(damage, falloff_min_damage, t)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(self)
