class_name Player
extends CharacterBody2D
## 젤리 플레이어. 이동도 전투도 **서버 권위**다.
##
## 클라이언트는 입력만 서버로 보내고 물리를 직접 계산하지 않는다.
## 서버가 apply_movement()로 위치를 정하고 결과를 양쪽에 복제하며,
## 클라이언트는 받은 위치로 보간해 표시한다.
##
## 체력·피격·상태이상·버프도 서버가 단독으로 판정하고 결과만 내려준다.
## 실제 공격 판정(누가 누구를 언제 때리는가)은 main.gd가 들고 있고,
## 여기 있는 server_* 함수들이 그 결과를 받는 창구다.
## 무기 수치는 scripts/weapons.gd, 공통 수치는 scripts/combat.gd에 있다.

## 서버에서만 발생한다. 인자는 죽은 플레이어의 peer id.
signal died(peer_id: int)
## 서버에서만 발생한다. 이 플레이어가 특수 공격(Shift)을 요청했다.
## long_press는 LONG_PRESS_TIME 이상 눌렀는지 (방패의 짧게/길게 구분용).
signal special_requested(peer_id: int, long_press: bool)
## 서버에서만 발생한다. 강제 낙하(양날 도끼)가 땅에 닿았다 — 인자는 떨어진 자리 (#167).
## 그 주변을 때리는 판정은 main.gd 가 한다.
signal landed_forced(peer_id: int, at: Vector2)
## 서버에서만 발생한다. 제자리 회전이 끝나 **지금 막 내지르기 시작했다** (전기톱, #260).
##
## 소리를 여기서 직접 내지 않는 것은 `landed_forced`와 같은 이유다 — 연출·소리는
## `Effects` 아래에 붙어야 하고 그 노드를 아는 것이 main.gd 다. 이 노드가 아는 것은
## "지금 넘어갔다"는 시점뿐이고, 그것으로 무엇을 할지는 저쪽이 정한다.
signal dash_launched(peer_id: int)
## 서버에서만 발생한다. 이 플레이어가 **실제로 데미지를 받았다** — 무적·사망으로
## 걸러진 것과 데미지 0인 것은 내지 않는다. 인자는 맞은 플레이어의 peer id 와,
## 그것이 지속 데미지(출혈·전기톱)의 한 틱인지.
##
## 무엇으로 맞았는지는 싣지 않는다. 무기·투사체마다 따로 알리는 대신 데미지가 지나가는
## 두 문(`server_apply_hit`·`server_apply_dot`)에서만 내보내므로, **모든 피해가 빠짐없이
## 한 자리로 모인다** — 소리를 "기본적으로" 울리려면 새 무기가 늘어도 여기가 안 변해야 한다.
##
## 소리를 여기서 직접 내지 않는 이유는 `sparked`·`burst` 와 같다: 연출은 `Effects` 아래에
## 붙어야 하고 그 노드를 아는 것이 main.gd 다.
signal damaged(peer_id: int, continuous: bool)

## 이 젤리가 **기절하며** 맞았다 (망치 특수가 얹은 기절, 삼지창 특수의 삼지창).
##
## 위의 `damaged` 와 같은 자리(`server_apply_hit`)에서 나가지만 신호를 따로 둔 것은
## 뜻이 다르기 때문이다 — 그쪽은 "피해를 입었다", 이쪽은 "굳었다"다. 데미지가 0이어도
## 기절이 얹혀 있으면 굳는 것이므로 조건도 서로 다르다.
##
## **무엇으로 굳었는지는 싣지 않는다.** 기절을 거는 무기가 둘(망치·삼지창)인데 소리는
## 하나다 — 걸리는 길이 다를 뿐 화면에서 일어나는 일은 같다.
signal stunned(peer_id: int)

## 이 젤리의 게이지가 **방금 75%를 넘어섰다** (너클, #225). 서버에서만 발생한다.
##
## **넘어서는 순간 한 번만 낸다** — 75% 위에서 또 맞아도 다시 나지 않는다.
## 게이지가 얼마나 찼는지가 아니라 "이제 강펀치가 달라진다"가 이 신호의 뜻이라,
## 오라가 켜지는 그 한 순간과 짝이 맞아야 한다(둘 다 `is_charged()`가 정한다).
##
## 데미지가 지나가는 두 문(`server_apply_hit`·`server_apply_dot`)에서 함께 나간다 —
## 출혈로 차서 넘는 것도 맞아서 넘는 것과 같은 일이기 때문이다.
signal gauge_charged(peer_id: int)

## 이 플레이어를 조작하는 클라이언트의 peer id. 스폰할 때 서버가 정한다.
@export var owner_peer_id := 0
@export var player_name: String = "1P"
## 대기실에서 고른 캐릭터 이름 (예: "분홍"). 그림은 Characters 표에서 꺼낸다.
@export var character_id: String = ""
## 대기실에서 서버가 확정한 무기 이름 (예: "광선검", "망치").
## 수치는 Weapons.get_weapon()으로 꺼내 쓴다 — 통합 가이드: docs/weapon-system.md
@export var weapon_id: String = ""

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const FAST_FALL_MULTIPLIER := 2.0
## 클라이언트가 서버 위치를 따라가는 속도. 클수록 즉각적이고 작을수록 부드럽다.
const INTERPOLATION_SPEED := 20.0

## 방패의 짧게/길게를 가르는 시간. 서버가 잰다.
const LONG_PRESS_TIME := 0.3
## 강제 이동(전기톱 돌진, 양날 도끼 상승·낙하) 속도 — 일반 점프의 두 배.
const FORCED_SPEED := absf(JUMP_VELOCITY) * 2.0
## 무기 도형의 기본 길이. 여기에 무기별 배율이 곱해진다.
const BASE_REACH := 24.0
## 캐릭터를 화면에 그릴 높이(px). 그림의 투명 여백은 빼고 실제로 보이는 부분의 높이다.
const BODY_HEIGHT := 72.0
## 발이 닿는 높이 — 충돌 상자(48x56)의 아래쪽 모서리.
const BODY_BOTTOM := 28.0
## 무기 그림을 그릴 높이(px). 캐릭터보다 조금 작아야 손에 든 것처럼 보인다.
const WEAPON_HEIGHT := 56.0
## 무기 그림의 최대 가로(px). 가로로 긴 원화(전기톱·대포 총)가 몸통(48px)을 덮지 않게 한다.
## 세로로 긴 무기는 여기에 걸리지 않아 WEAPON_HEIGHT 그대로다.
const WEAPON_MAX_WIDTH := 80.0
## 무기를 몸 중심에서 얼마나 옆으로 둘지. 바라보는 쪽에 놓인다.
const WEAPON_OFFSET_X := 26.0
## 무기 그림의 세로 중심. 몸 한가운데쯤이다.
const WEAPON_CENTER_Y := -8.0
## 사거리 버프로 그림이 늘어나는 속도(초당 배율). 장대는 1.0 → 1.6이므로 약 0.15초에 다 뻗는다.
## 특수를 쓴 것이 보일 만큼 빠르고, 뻗는 동작이 눈에 남을 만큼은 느리다.
const ART_STRETCH_SPEED := 4.0
## 길이가 늘어날 때 **굵기**가 함께 붇는 비율. 0이면 굵기 그대로, 1.0이면 길이와 같은 배율.
## 길이만 늘리면 늘어난 봉이 실처럼 가늘어 보이므로 굵기도 조금 따라가게 한다.
## 0.5면 길이 1.6배일 때 굵기 1.3배다 — 장대가 6px → 8px 굵어진다.
const ART_THICKEN_SHARE := 0.5

## 검 특수의 내려베기 (#247). 세워 든 자세가 0도이고, 음수가 뒤로 젖힌 자세,
## 양수가 앞으로 내려친 자세다 — 바라보는 쪽 부호는 `facing`이 곱해서 정한다.
##
## 젖히는 각도가 이보다 작으면 들어 올린 것이 안 보이고, 내려치는 각도가 수평(90도)에
## 못 미치면 벤 것이 아니라 세우다 만 것으로 보인다. 그래서 수평을 조금 넘긴다.
const SWING_RAISE_DEGREES := 52.0
const SWING_DOWN_DEGREES := 104.0
## 다 벤 자세에서 평소 자세로 돌아오는 데 걸리는 시간(초).
## 판정은 이미 끝난 뒤라 이 값은 그림에만 영향을 준다.
const SWING_RECOVER := 0.18
## 들어 올리는 동안 검이 통째로 위로 뜨는 높이(px). 각도만 젖히면 "들었다"보다
## "기울였다"로 읽혀서, 쥔 자리를 조금 올려 준다.
const SWING_LIFT := 14.0

## 전기톱 특수의 회전 속도(초당 바퀴 수, #260). 제자리 회전 0.45초 동안 약 2바퀴 반이다.
## 이보다 느리면 도는 것이 아니라 무기를 휘휘 젓는 것으로 보이고, 빠르면 원호가 원으로
## 이어져 도는 것이 안 보인다.
const SPIN_TURNS_PER_SECOND := 5.5

## 관통(광선검 특수) 중임을 알리는 빛. 광선검 날에 맞춘 민트빛이다.
const PIERCE_COLOR := Color(0.55, 0.95, 0.85)
## 관통 중 무기에 곱하는 색. 1을 넘겨서 날이 타오르게 만든다.
const PIERCE_TINT := Color(0.8, 1.5, 1.35)
## 빛무리 크기와 그 중심(몸 한가운데). 몸이 48x72라 이 정도면 몸을 감싼다.
const PIERCE_AURA_RADIUS := 58.0
const PIERCE_AURA_CENTER := Vector2(0.0, -8.0)

## 게이지가 `charged_ratio`(너클 75%)를 넘은 동안 몸을 감싸는 오라 (#225).
## 색은 사용자가 첨부한 참고 스크린샷의 자홍/보라 계열이고, 강펀치 연출
## (`heavy_punch.gd`의 충전 디자인)도 같은 색을 쓴다 — 오라가 돌던 젤리가 그 색으로
## 내지르는 것으로 읽혀야 한다.
const CHARGE_AURA_RADIUS := 46.0
const CHARGE_AURA_CENTER := Vector2(0.0, -8.0)
const CHARGE_AURA_COLOR := Color(0.95, 0.36, 0.88)
const CHARGE_AURA_EDGE := Color(0.55, 0.28, 0.92)
## 몸을 따라 오르는 조각의 색과 개수.
const CHARGE_SPARK_COLOR := Color(0.78, 0.58, 1.0)
const CHARGE_SPARK_COUNT := 6

## 평소와 다른 그림을 든 동안 무기에서 피어오르는 연기 색 (빨간 표창·빨간 도끼).
## 무기 표에 `smoke_puffs`가 있는 무기에만 뜬다. 두 빨간 그림의 붉은색에 맞췄다 —
## 손에 든 것과 연기가 다른 색이면 무엇에서 나는지 안 읽힌다.
const SPECIAL_SMOKE_COLOR := Color(0.82, 0.13, 0.11)

## 도화선에서 늘 피어오르는 연기 색 (폭탄). 무기 표에 `smoke_fuse`가 있는 무기에만 뜬다.
##
## **순검정이 아니라 짙은 회색이다** — 연기는 배경을 덮는 그림이라(`weapon_smoke.gd`)
## 완전한 검정으로 두면 어두운 지형 위에서 구멍처럼 보이고, 밝은 하늘 위에서는
## 연기가 아니라 검은 덩어리로 읽힌다.
const FUSE_SMOKE_COLOR := Color(0.16, 0.15, 0.15)

## 날이 지나간 자리에 남는 잔상 색 (#253). 무기 표에 `trail_ghosts`가 있는 무기에만
## 뜬다. **관통 빛과 같은 민트**다 — 광선검 날의 색이고, 날과 다른 색으로 남기면
## 무엇의 잔상인지 읽히지 않는다.
const TRAIL_COLOR := PIERCE_COLOR

## 넉백 직후 좌우 입력이 속도를 덮어쓰지 못하는 시간.
##
## 서버가 매 프레임 velocity.x를 입력값으로 덮어쓰기 때문에, 이 잠금이 없으면
## 이동 속도(320)보다 약한 넉백(약 200·중 400의 감속 구간)이 다음 프레임에
## 그대로 지워져서 밀리는 것이 보이지 않는다.
const KNOCKBACK_CONTROL_LOCK := 0.2

## 전투 상태. 서버가 정하고 RPC로 양쪽에 복제된다.
var hp := Combat.MAX_HP
var alive := true
## 바라보는 방향 (1 오른쪽 / -1 왼쪽). 특수 공격은 이 방향으로 나간다.
var facing := 1
## 지금 어떤 포즈의 원화를 입고 있는가 (#176). 평소에는 `Characters.POSE_IDLE`이고,
## 죽는 순간 자신은 패배 포즈, 점수를 얻은 상대는 승리 포즈가 된다.
## 라운드가 다시 시작되면 평소로 돌아온다 — 안 되돌리면 다음 라운드로 새어 나간다.
var pose := Characters.POSE_IDLE
## 너클 게이지. 내가 맞을 때 충전된다.
var gauge := 0.0
## 특수 공격을 쓸 수 있는가. 서버가 쿨타임을 재고 이 값만 내려준다 (무기 도형 색에 쓴다).
var special_ready := true
## 강제 이동 상태. ""이면 평소, "spin"·"dash"(전기톱) / "rise"·"hover"·"fall"(양날 도끼).
var forced_mode := ""
## 다음에 던질 것이 **강화**인가 (#134). 폭탄(데미지·넉백 증가)과 표창(빨간 표창,
## 위치 교환)이 이 값을 쓴다 — 무엇으로 바뀌는지는 무기 표의 `empowered_*`가 정한다.
##
## 던지는 순간에 뽑으면 손에 들고 보여줄 수가 없어서, 서버가 미리 뽑아 복제한다.
## 첫 스폰값은 스폰 데이터로 들어오고(`main.gd._spawn_player`), 그 뒤로는
## `server_set_empowered()`가 갱신한다 — 라운드 시작과 던진 직후다.
var empowered_ready := false

## 무기 선택 중인가 (#205). 라운드는 무기 선택으로 열리는데, 그동안 두 젤리가
## 스폰 지점에 서 있기만 해야 한다 — 안 그러면 카드를 읽는 사람이 그 자리에서 맞는다.
##
## **`can_act()` 에 넣어서 잠근다.** 이동·기본 공격·특수가 전부 그 하나를 보고 있어서
## 여기 한 줄이면 셋이 같이 멈춘다 — 기절과 같은 방식이다(`is_stunned`).
## 중력은 그대로 받으므로 공중에서 시작해도 발이 땅에 닿는다.
var frozen := false

## 무적 시간은 기본 공격용과 특수 공격용을 따로 잰다.
## 합치면 기본 공격이 계속 무적을 새로 걸어서 특수 공격이 거의 안 들어간다.
var _invuln_until := {"basic": 0.0, "special": 0.0}
var _stun_until := 0.0
## 광선검 특수 — 상대 무기의 막기를 무시한다. 지형은 통과하지 못한다.
var _pierce_until := 0.0
## 망치 특수 — 이 시각까지 **내 기본 공격에 기절이 얹힌다**.
##
## **위의 `_stun_until` 과 반대 방향이다.** 그쪽은 "내가 굳어 있는" 시간이고 이쪽은
## "내가 굳히는" 능력이다 — 이름이 비슷해 헷갈리기 쉬우니 여기 적어 둔다.
var _stun_grant_until := 0.0
## 그때 얹히는 기절의 길이(초). 무기 표의 `stun_duration` 이 `_receive_buff` 로 실려 온다.
var _stun_grant := 0.0
## 지난 프레임에 관통 빛을 그렸는가. 꺼진 프레임에 한 번 더 다시 그려 지우려고 들고 있다.
var _aura_shown := false
var _reach_multiplier := 1.0
var _reach_until := 0.0
var _size_multiplier := 1.0
var _size_until := 0.0
var _forced_deadline := 0.0
var _knockback_until := 0.0

## 서버가 보관하는 최신 입력 (클라이언트에서 RPC로 갱신된다)
var _input_direction := 0.0
var _input_fast_fall := false
var _jump_queued := false
## 서버가 재는 Shift 누른 시각. 음수면 안 누르고 있다.
var _skill_held_since := -1.0

## 그림을 BODY_HEIGHT에 맞추는 배율. 찌그러짐은 여기에 곱해진다.
var _body_base_scale := Vector2.ONE
## 배율 1일 때의 여백 보정(원본 픽셀 단위). 실제 보정은 그때그때 배율을 곱해서 쓴다 —
## 찌그러짐으로 배율이 흔들려도 발밑과 좌우 중심이 그대로 있어야 하기 때문이다.
var _body_offset_unit := Vector2.ZERO
## 무기 그림의 여백 보정. 그림이 없는 무기면 쓰이지 않는다.
var _weapon_offset := Vector2.ZERO
## 무기 그림의 기본 배율과 그렇게 그렸을 때의 세로 길이(px). `_apply_weapon()`이 정한다.
## 장대 특수에서 그림을 늘일 때 여기서 다시 계산한다 — 누적을 막기 위한 기준값이다.
var _weapon_art_factor := 1.0
var _weapon_art_length := 0.0
## 배율을 곱하기 **전**의 여백 보정과 원화 길이. 눕혀 드는 무기(장대)가 쓴다 —
## 회전하는 그림은 보정을 `position`이 아니라 `Sprite2D.offset`으로 해야 하고,
## offset은 배율·회전이 나중에 걸리므로 곱하기 전 값이어야 한다.
var _weapon_content_offset := Vector2.ZERO
var _weapon_content_length := 0.0
## 배율을 곱하기 **전**의 원화 가로 길이. 도는 무기(전기톱, #260)가 원의 반지름을 잰다.
var _weapon_content_width := 0.0
## 원화를 눕혀 바라보는 쪽으로 뻗어 드는가 (장대). 기본은 세워 드는 것이다.
var _weapon_art_forward := false
## 지금 그림이 늘어난 정도(1.0이면 평소). 목표값으로 부드럽게 따라간다.
var _weapon_art_stretch := 1.0
## 지금 그림이 커진 정도(1.0이면 평소). 위의 늘어난 정도와 곱해서 쓴다 — 방패는 이쪽만,
## 장대는 저쪽만 1.0이 아니라서 둘이 겹치는 무기는 아직 없다.
var _weapon_art_growth := 1.0
## 이 무기에 그림이 있는가. 없으면 지금까지처럼 임시 막대로 그린다.
var _weapon_has_art := false
## 이 무기의 원화가 왼쪽을 보고 그려졌는가. 그렇다면 뒤집는 조건이 반대가 된다 (#109).
var _weapon_faces_left := false

## 내려베기를 시작한 시각 (#247). 음수면 휘두르는 중이 아니다.
## 서버가 시작을 정해 `_receive_swing`으로 복제하고, 두 화면이 각자 그린다 —
## **표시용이다.** 데미지가 언제 들어가는지는 main.gd 가 자기 시계로 따로 잰다.
var _swing_started_at := -1.0
var _swing_windup := 0.0
var _swing_swing := 0.0

## 톱을 돌리기 시작한 시각 (#260). 음수면 돌고 있지 않다.
##
## **제자리 회전에서 돌진으로 넘어갈 때 다시 잡지 않는다** — 강제 이동 상태는 바뀌지만
## 톱은 계속 같은 속도로 돌고 있으므로, 넘어가는 프레임에 각도가 0으로 튀면 톱이 한 번
## 되감긴 것으로 보인다. `_receive_forced()`가 그 규칙을 지킨다.
##
## 시각 하나만 들고 각도는 각 피어가 자기 시계로 계산한다 — 내려베기(`_swing_started_at`)와
## 같은 방식이라 매 프레임 각도를 보내지 않는다.
var _spin_started_at := -1.0

## 클라이언트가 서버로부터 받은 표시용 상태
var _target_position := Vector2.ZERO
var _remote_on_floor := false
## 클라이언트가 Shift 엣지를 잡기 위해 들고 있는 직전 상태
var _skill_was_pressed := false


func _ready() -> void:
	_apply_character()
	_apply_weapon()
	$NameLabel.text = player_name
	_target_position = global_position
	# 투사체가 사거리 안의 젤리를 찾을 때 쓴다.
	add_to_group("jellies")
	if multiplayer.is_server():
		# 스폰 직후 바로 맞지 않도록 잠깐 무적을 준다.
		var grace := _now() + Combat.ROUND_START_GRACE
		_invuln_until = {"basic": grace, "special": grace}
		# 전투 화면에 있는 피어에게만 보인다 (이슈 #182). 이 필터가 스폰 전달까지 정하므로
		# 경기 도중에 들어온 관전자는 viewer 가 되는 순간 이 젤리를 받는다.
		$Sync.add_visibility_filter(Lobby.can_view)
	_update_weapon_shape(0.0)


## 이 기기가 조작하는 플레이어인지.
func is_local_player() -> bool:
	return owner_peer_id == multiplayer.get_unique_id()


## 입력을 읽는 유일한 지점. 자기 플레이어가 아니면 빈 입력을 돌려준다.
func read_input() -> Dictionary:
	if not is_local_player():
		return {"direction": 0.0, "jump": false, "fast_fall": false, "skill": false}
	return {
		"direction": Input.get_axis("move_left", "move_right"),
		"jump": Input.is_action_just_pressed("jump"),
		"fast_fall": Input.is_action_pressed("fast_fall"),
		"skill": Input.is_action_pressed("skill"),
	}


## 이동 적용. Input을 직접 읽지 않고 인자만 받는다 — 서버에서만 호출된다.
func apply_movement(input: Dictionary, delta: float) -> void:
	# 강제 이동 중에는 조작이 전부 불가하다. 동작이 끝날 때까지 몸이 알아서 움직인다.
	if forced_mode != "":
		_apply_forced(input, delta)
		return

	# 기절·사망 중에도 조작 불가. 중력만 계속 받는다.
	if not can_act():
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return

	# 중력 (fast_fall 을 누르고 있으면 빠르게 낙하)
	if not is_on_floor():
		var gravity := get_gravity()
		if input["fast_fall"]:
			gravity *= FAST_FALL_MULTIPLIER
		velocity += gravity * delta

	if input["jump"] and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction: float = input["direction"]
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
	# 넉백으로 밀리는 동안에는 입력이 속도를 즉시 덮어쓰지 않게 한다.
	if _now() >= _knockback_until:
		velocity.x = direction * SPEED
	elif direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * SPEED, SPEED * delta)

	move_and_slide()


## 강제 이동. 서버에서만 호출된다.
##
## 무기 표에 `special_air_control`이 있으면 **공중에 뜬 동안 좌우 입력을 받는다**
## (양날 도끼, #167). 상승 0.25초 + 정점 0.2초 + 낙하로 1초 가까이 조작이 잠기는데
## 그동안 상대는 걸어서 낙하 지점을 벗어난다 — 쿨타임 9초로 가장 긴 기술이 "쓰면 거의
## 빗나가는" 것이 되어 있었다.
##
## **돌진("dash")은 일부러 제외한다** — 바라보는 쪽으로 내지르는 기술이라 도중에 꺾이면
## 다른 기술이 된다. 그래서 조종은 무기 표가 허락한 무기에만 붙는다.
func _apply_forced(input: Dictionary, delta: float) -> void:
	match forced_mode:
		"spin":
			# 제자리 회전 (#260). **가로 속도를 0으로 덮는다** — 누르기 직전에 달리던
			# 속도가 남아 있으면 도는 동안 스르르 미끄러져서 "제자리"로 안 보인다
			# (도끼의 `"hover"`가 같은 이유로 속도를 덮는다). 중력은 그대로 받으므로
			# 공중에서 눌러도 발이 땅에 닿는다.
			velocity.x = 0.0
			if not is_on_floor():
				velocity += get_gravity() * delta
			move_and_slide()
			# 다 돌면 지금까지와 똑같은 돌진으로 이어진다. 데미지는 돌진 구간에서만
			# 들어가므로(`_special_pending`의 `modes`) 여기까지는 아무도 안 맞는다.
			if _now() >= _forced_deadline:
				if multiplayer.is_server():
					dash_launched.emit(owner_peer_id)
				_receive_forced.rpc("dash", dash_time())
		"dash":
			velocity.x = facing * FORCED_SPEED
			if not is_on_floor():
				velocity += get_gravity() * delta
			move_and_slide()
			# 벽에 부딪히거나 안전장치 시간이 지나면 끝난다.
			if is_on_wall() or _now() >= _forced_deadline:
				server_end_forced()
		"rise":
			velocity.y = -FORCED_SPEED
			_steer(input)
			move_and_slide()
			# 올라가는 힘이 다하면 정점에 잠깐 머문 뒤 낙하로 넘어간다.
			# 머무는 시간은 무기 표가 정한다 — 0이면 지금까지처럼 곧바로 떨어진다.
			if _now() >= _forced_deadline:
				var hover: float = Weapons.get_weapon(weapon_id).get("hover_time", 0.0)
				if hover > 0.0:
					_receive_forced.rpc("hover", hover)
				else:
					_receive_forced.rpc("fall", 0.0)
		"hover":
			# 정점에서 멈춘다. **속도를 0으로 덮으므로 중력을 받지 않는다** —
			# 안 그러면 머무는 시간 동안 스르르 떨어져서 "멈췄다"로 안 보인다.
			# 좌우 조종은 그 뒤에 얹는다 — 정점에서 자리를 고칠 수 있어야 조종이 의미가 있다.
			velocity = Vector2.ZERO
			_steer(input)
			move_and_slide()
			if _now() >= _forced_deadline:
				_receive_forced.rpc("fall", 0.0)
		"fall":
			velocity.x = 0.0
			_steer(input)
			velocity.y = FORCED_SPEED
			move_and_slide()
			if is_on_floor():
				# 착지 판정은 여기서 하지 않는다 (#167) — "어디에 떨어졌다"만 알리고
				# 누구를 때리는지는 main.gd 가 정한다(전투 판정의 주인은 거기다).
				if multiplayer.is_server():
					landed_forced.emit(owner_peer_id, global_position)
				server_end_forced()


## 공중 조종 (#167). 무기 표가 허락한 무기만 좌우 입력으로 가로 속도를 잡는다.
## 허락하지 않으면 아무것도 건드리지 않아 지금까지의 궤도가 그대로다.
##
## 입력이 없으면 가로 속도를 0으로 둔다 — 뜨기 직전에 달리던 속도가 남아 있으면
## 조종하지 않았는데도 옆으로 흐른다.
func _steer(input: Dictionary) -> void:
	if not Weapons.get_weapon(weapon_id).get("special_air_control", false):
		return
	var direction: float = input["direction"]
	if direction == 0.0:
		velocity.x = 0.0
		return
	facing = 1 if direction > 0.0 else -1
	velocity.x = direction * SPEED


## 돌진이 벽 없는 맵에서 무한히 이어지지 않게 하는 안전장치 시간(초).
## 화면 폭을 돌진 속도로 지나가는 시간이면 충분하다.
##
## **여기 있는 것은 돌진을 거는 자리가 둘이기 때문이다** (#260) — 특수를 누른 순간
## (`main.gd._execute_special()`)과 제자리 회전이 끝나는 순간(`_apply_forced()`)이다.
## 두 곳이 각자 재면 언젠가 값이 갈라지고, 그때 회전을 거친 돌진만 사거리가 달라진다.
func dash_time() -> float:
	return get_viewport_rect().size.x / FORCED_SPEED


## 캐릭터 그림을 붙이고 크기·위치를 맞춘다.
##
## 원화는 정사각 캔버스에 투명 여백을 두고 그려져 있어서 파일 크기를 그대로 쓰면
## 발이 땅에서 뜬다. 그래서 여백을 뺀 실제 그림 영역을 재서 그 아래쪽을 발밑에 맞춘다.
##
## 포즈가 바뀔 때도 이 함수를 다시 부른다 (#176) — 승리·패배 원화는 평소 그림과
## 비율이 달라서(눕는 포즈는 가로가 길다) 배율과 여백 보정을 처음부터 다시 재야 한다.
func _apply_character() -> void:
	if not Characters.has(character_id):
		character_id = Characters.default_id()
	var sprite: Sprite2D = $Body
	var texture := Characters.pose_texture(character_id, pose)
	sprite.texture = texture
	if texture == null:
		return
	var texture_size := Vector2(texture.get_size())
	var content := Art.content_rect(texture)
	if content.size.y <= 0.0:
		return

	var factor := BODY_HEIGHT / content.size.y
	_body_base_scale = Vector2.ONE * factor
	sprite.scale = _body_base_scale
	# 스프라이트는 자기 위치를 중심으로 그려진다 — 여백만큼 밀어서 그림의 좌우 가운데가
	# 몸 중심에, 아래쪽이 충돌 상자 바닥에 오게 한다.
	# 배율을 곱하기 전 값으로 들고 있다가 _place_body()가 그때의 배율로 환산한다.
	_body_offset_unit = Vector2(
		texture_size.x * 0.5 - content.position.x - content.size.x * 0.5,
		texture_size.y * 0.5 - content.position.y - content.size.y)
	_place_body()


## 지금 배율에 맞춰 그림 위치를 잡는다. 발밑이 항상 충돌 상자 바닥에 오게 하는 곳이다.
##
## Sprite2D 는 자기 위치를 **중심으로** 확대·축소한다. 그래서 찌그러짐으로 세로 배율이
## 커지면 머리와 발이 같이 벌어져 발이 바닥을 뚫고, 작아지면 발이 뜬다 (이슈 #85).
## 배율이 바뀔 때마다 여백 보정을 다시 환산해서 기준점을 발밑으로 되돌린다.
func _place_body() -> void:
	var sprite: Sprite2D = $Body
	var offset := _body_offset_unit * sprite.scale
	# 뒤집으면 그림이 스프라이트 중심을 기준으로 반전되므로 좌우 보정도 반대로 간다.
	if sprite.flip_h:
		offset.x = -offset.x
	sprite.position = Vector2(offset.x, BODY_BOTTOM + offset.y)


## 젤리 찌그러짐 연출. 서버·클라이언트 모두 복제된 속도·접지값으로 계산한다.
## 그림마다 원본 크기가 달라 찌그러짐은 기본 배율에 곱해서 쓴다.
func _update_squash(grounded: bool, delta: float) -> void:
	var target_scale := Vector2.ONE
	if not grounded:
		target_scale = Vector2(0.9, 1.1)
	elif absf(velocity.x) > 1.0:
		target_scale = Vector2(1.1, 0.9)
	$Body.scale = $Body.scale.lerp(_body_base_scale * target_scale, 12.0 * delta)
	# 배율이 바뀌었으니 발밑이 바닥에 남아 있도록 위치를 다시 잡는다.
	_place_body()


## 평소와 다른 그림을 들어야 하는 상태면 그 **파일 이름**, 아니면 빈 문자열 (#134).
##
## 계기가 둘이고 무기마다 하나만 쓴다:
##   `empowered_file` — 서버가 미리 뽑아 둔 강화 (폭탄의 강화 폭탄, 표창의 빨간 표창)
##   `ready_file`     — 특수 쿨타임이 끝나 쓸 수 있는 상태 (양날 도끼의 빨간 도끼)
##
## 뽑기가 없는 무기는 `empowered_ready`가 항상 false이고, `ready_file`이 없는 무기는
## `special_ready`가 켜져 있어도 빈 문자열이 나온다 — 그래서 둘을 순서대로 봐도 섞이지 않는다.
##
## 그림 자체가 아니라 이름을 돌려주는 것은 연기(`_update_weapon_smoke`)도 같은 판단을
## 써야 하기 때문이다. 두 곳에서 조건을 각자 쓰면 그림과 연기가 어긋난다.
func _highlight_file() -> String:
	var data := Weapons.get_weapon(weapon_id)
	if empowered_ready:
		return data.get("empowered_file", "")
	if special_ready:
		return data.get("ready_file", "")
	return ""


## 손에 들 무기 그림. 특별한 상태의 그림이 있으면 그것을, 없으면 평소 것을 든다.
func _weapon_texture() -> Texture2D:
	var file := _highlight_file()
	if not file.is_empty():
		var highlight := Weapons.texture_file(file)
		if highlight != null:
			return highlight
	return Weapons.texture(weapon_id)


## 무기 그림을 붙이고 크기를 맞춘다. 그림이 없는 무기면 막대 쪽을 쓴다.
func _apply_weapon() -> void:
	var sprite: Sprite2D = $WeaponSprite
	var texture := _weapon_texture()
	sprite.texture = texture
	_weapon_has_art = texture != null
	_weapon_faces_left = Weapons.art_faces_left(weapon_id)
	# 머리 위 게이지 바는 게이지를 쓰는 무기에만 뜬다 (#225). 무기가 바뀌는 순간이
	# 이 함수 하나뿐이라 여기서 정한다 — 라운드마다 무기를 새로 고르므로(#205)
	# 다른 무기로 바뀌면 저절로 숨는다.
	$GaugeBar.visible = uses_gauge()
	if texture == null:
		return
	var texture_size := Vector2(texture.get_size())
	var content := Art.content_rect(texture)
	if content.size.y <= 0.0 or content.size.x <= 0.0:
		_weapon_has_art = false
		return
	# 세로를 WEAPON_HEIGHT에 맞추되 가로가 WEAPON_MAX_WIDTH를 넘지 않게 한다.
	# 세로만 맞추면 가로로 긴 원화(전기톱 2.69:1)가 몸통 3배 폭으로 터진다 (이슈 #105).
	var factor := minf(WEAPON_HEIGHT / content.size.y, WEAPON_MAX_WIDTH / content.size.x)
	# 뭉툭한 원화는 두 제한을 다 통과하고도 몸통만 해진다 (이슈 #158). 세로 규칙은
	# 검처럼 가늘고 긴 무기를 기준으로 잡은 것이고, 가로 제한은 세로로 긴 것을 못 잡듯
	# 정사각에 가까운 것도 못 잡는다. 그런 무기만 표에서 배율을 더 준다.
	factor *= Weapons.art_scale(weapon_id)
	# 배율과 그려지는 길이를 들고 있는다 — `_update_weapon_shape()`가 매 프레임 여기에
	# 늘어난 정도를 곱해 쓴다(장대 특수). 거기서 `sprite.scale`을 곱셈으로 누적하면
	# 프레임마다 커져서 화면을 덮으므로, 항상 이 기준값에서 다시 계산해야 한다.
	_weapon_art_factor = factor
	_weapon_art_length = content.size.y * factor
	_weapon_art_forward = Weapons.get_weapon(weapon_id).get("art_held_forward", false)
	sprite.scale = Vector2.ONE * factor
	# 캐릭터와 마찬가지로 여백을 뺀 실제 그림의 가운데를 기준으로 놓는다.
	_weapon_content_offset = Vector2(
		texture_size.x * 0.5 - content.position.x - content.size.x * 0.5,
		texture_size.y * 0.5 - content.position.y - content.size.y * 0.5,
	)
	_weapon_content_length = content.size.y
	# 가로도 들고 있는다 (#260) — 도는 톱이 그리는 원의 반지름이 **화면에 그려진 그림의
	# 반쪽 길이**다. 전기톱은 가로로 긴 원화(2.69:1)라 세로(`_weapon_content_length`)로
	# 재면 원이 그림보다 훨씬 작게 잡힌다.
	_weapon_content_width = content.size.x
	_weapon_offset = _weapon_content_offset * factor


## 관통 빛은 매 프레임 모양이 바뀌니 켜져 있는 동안 계속 다시 그린다.
## 꺼진 프레임에도 한 번 더 그려야 화면에서 지워진다 — 안 그러면 마지막 모양이 남는다.
func _update_pierce_aura() -> void:
	# 관통 빛과 게이지 오라(#225)를 한 자리에서 본다 — `_draw()` 가 둘 다 그리므로
	# 어느 쪽이든 켜져 있거나 방금 꺼졌으면 다시 그려야 한다.
	var lit := is_piercing() or is_charged()
	if lit or _aura_shown:
		_aura_shown = lit
		queue_redraw()


## 관통(광선검 특수) 중에 몸 뒤로 도는 빛.
##
## 자식 노드(`Body`)보다 **먼저** 그려져서 젤리 뒤에 깔린다 — 그래서 별도 노드가 필요 없다.
## 씬 루트에 걸린 가산 혼합은 이 그리기에만 적용되고 자식 스프라이트에는 영향이 없다.
##
## `_pierce_until`이 `_receive_buff`로 양쪽 피어에 복제되므로 두 화면에 똑같이 뜬다.
func _draw() -> void:
	# 게이지 오라가 먼저다 — 관통과 겹칠 수 있고(광선검은 게이지가 없으니 지금은 안 겹친다),
	# 겹칠 때 관통 빛이 위에 오는 편이 무엇이 켜졌는지 읽기 쉽다.
	if is_charged():
		_draw_charge_aura()
	if not is_piercing():
		return
	var pulse := 0.72 + 0.28 * sin(_now() * 9.0)
	# 맵 배경이 밝은 편(평지 잔디가 0.36·0.66·0.32)이라 가산 혼합이 쉽게 묻힌다.
	# 넓고 옅은 것 위에 좁고 진한 것을 겹쳐야 잔디 위에서도 빛으로 읽힌다.
	Art.draw_glow(self, PIERCE_AURA_CENTER, PIERCE_AURA_RADIUS * (1.25 + 0.12 * pulse),
		PIERCE_COLOR, 0.5 * pulse)
	Art.draw_glow(self, PIERCE_AURA_CENTER, PIERCE_AURA_RADIUS * (0.92 + 0.08 * pulse),
		PIERCE_COLOR, 0.9 * pulse)
	# 윤곽선을 덧그려 "지금 켜져 있다"가 확실히 보이게 한다.
	draw_arc(PIERCE_AURA_CENTER, PIERCE_AURA_RADIUS * 0.82, 0.0, TAU, 44,
		Color(PIERCE_COLOR, 0.95 * pulse), 3.5, true)


## 게이지가 `charged_ratio`를 넘은 동안 몸을 감싸는 오라 (#225).
##
## 관통 빛과 같은 자리에 그리지만 **모양이 다르다** — 서로 반대로 도는 고리 두 개 위에
## 몸을 따라 오르는 조각이 붙는다. 가만히 있는 빛은 "켜졌다"로만 읽히는데, 이쪽은
## "차올라 있다"로 읽혀야 해서 움직이는 것을 넣었다.
##
## `gauge`가 `_receive_hit`·`_receive_gauge`로 복제되므로 두 화면에 똑같이 뜬다.
func _draw_charge_aura() -> void:
	var t := _now()
	var pulse := 0.7 + 0.3 * sin(t * 6.0)
	Art.draw_glow(self, CHARGE_AURA_CENTER, CHARGE_AURA_RADIUS * (1.3 + 0.1 * pulse),
		CHARGE_AURA_EDGE, 0.42 * pulse)
	Art.draw_glow(self, CHARGE_AURA_CENTER, CHARGE_AURA_RADIUS * (0.95 + 0.07 * pulse),
		CHARGE_AURA_COLOR, 0.68 * pulse)
	# 고리 둘은 서로 반대로 돈다. 한 바퀴를 다 그리지 않고 끊어 두어야 도는 것이 보인다.
	for i in 2:
		var spin := t * 2.4 * (1.0 if i == 0 else -1.0)
		var radius := CHARGE_AURA_RADIUS * (0.72 + 0.12 * float(i))
		draw_arc(CHARGE_AURA_CENTER, radius, spin, spin + TAU * 0.62, 34,
			Color(CHARGE_AURA_COLOR, 0.8 * pulse), 3.0, true)
	# 몸을 따라 오르는 조각. 위로 갈수록 작아지고 옅어진다.
	for i in CHARGE_SPARK_COUNT:
		var phase := fposmod(t * 0.9 + float(i) / float(CHARGE_SPARK_COUNT), 1.0)
		var angle := TAU * float(i) / float(CHARGE_SPARK_COUNT) + t * 1.6
		var at := CHARGE_AURA_CENTER + Vector2(
			cos(angle) * CHARGE_AURA_RADIUS * 0.7,
			lerpf(26.0, -34.0, phase))
		Art.draw_glow(self, at, lerpf(7.0, 2.5, phase), CHARGE_SPARK_COLOR,
			(1.0 - phase) * 0.75)


## 무기에서 피어오르는 연기. 두 가지가 있다.
##
## 하나는 **평소와 다른 그림을 든 동안**의 붉은 경고다 (빨간 표창·빨간 도끼).
## **켜는 조건은 `_highlight_file()` 하나로 맞춘다** — 그림이 바뀌는 순간에 연기도 같이
## 나야 하고, 조건을 두 곳에 따로 쓰면 어긋난다.
##
## 다른 하나는 **늘 타고 있는 도화선**의 검은 연기다 (폭탄, 무기 표의 `smoke_fuse`).
## 이쪽은 상태를 알리는 것이 아니라 무기의 생김새라 그림과 무관하게 계속 난다.
##
## 덩어리 수는 두 경우 다 무기 표의 `smoke_puffs`다
## (표창 5, 양날 도끼 9 — 센 무기일수록 크게 경고한다. 폭탄 4는 도화선 굵기다).
##
## 계기가 되는 `empowered_ready`·`special_ready` 둘 다 RPC로 복제되므로 두 화면에 똑같이
## 뜬다 — 젤리 찌그러짐처럼 각 피어가 복제된 값으로 알아서 그린다.
##
## 연기는 무기 그림 자리에서 난다. 여백 보정(`_weapon_offset`)까지 맞추지는 않는다 —
## 그림이 없는 무기에도 붙을 수 있어야 하고, 몇 px 차이는 연기에서 보이지 않는다.
func _update_weapon_smoke() -> void:
	var smoke: WeaponSmoke = $Smoke
	var data := Weapons.get_weapon(weapon_id)
	var puffs: int = data.get("smoke_puffs", 0)
	# **도화선 연기는 상태를 알리는 연기가 아니다** (폭탄). 무기 표의 `smoke_fuse`가
	# 켜져 있으면 그림이 바뀌는 것과 무관하게 **늘** 난다 — 도화선은 계속 타고 있고,
	# 손에 든 것이 강화 폭탄인지는 그림(`empowered_file`)이 이미 말한다.
	# 색도 그래서 갈린다: 붉은 연기는 "평소와 다르다"는 경고고, 검은 연기는 폭탄 그 자체다.
	var fuse: bool = data.get("smoke_fuse", false)
	var wants := alive and puffs > 0 and (fuse or not _highlight_file().is_empty())
	smoke.visible = wants
	if not wants:
		return
	smoke.puff_count = puffs
	smoke.color = FUSE_SMOKE_COLOR if fuse else SPECIAL_SMOKE_COLOR
	smoke.position = Vector2(facing * WEAPON_OFFSET_X, WEAPON_CENTER_Y)


## 날이 지나간 자리에 남는 미세한 잔상 (광선검, #253).
##
## **켜는 조건은 무기 표의 `trail_ghosts` 하나다** — 연기(`smoke_puffs`)와 같은 짜임이라
## 다른 무기가 쓰고 싶으면 표에 줄만 더하면 된다. 그림이 없는 무기(임시 막대)는 남길 날이
## 없으므로 제외한다.
##
## 자리는 이미 복제되는 `position`·`facing`에서 나오므로 각 피어가 자기 화면 값으로
## 알아서 그린다 — RPC를 더하지 않는다(버전 악수 #228에 영향이 없다).
##
## 문턱값(움직여야 하는 거리)은 여기가 아니라 `WeaponTrail.sample()`이 본다. 두 곳에
## 나누면 "얼마나 움직여야 남는가"가 갈라진다.
func _update_weapon_trail() -> void:
	var trail: WeaponTrail = $Trail
	var ghosts: int = Weapons.get_weapon(weapon_id).get("trail_ghosts", 0)
	var wants := alive and ghosts > 0 and _weapon_has_art
	if not wants:
		# 비우고 나서 숨긴다 — 숨은 노드는 나이도 먹지 않아서, 안 비우면 다시 켜질 때
		# 지난번 자리의 잔상이 그대로 되살아난다.
		trail.clear()
		trail.visible = false
		return
	trail.visible = true
	trail.ghost_count = ghosts
	trail.color = TRAIL_COLOR
	var ends := _blade_ends()
	trail.sample(ends[0], ends[1])


## 능력을 켜는 특수가 켜져 있는 동안 몸을 감싸고 튀는 전격 (망치·광선검).
##
## **켜는 조건은 "능력이 걸려 있는가" 하나다** — 무기 이름을 보지 않는다. 그래서 능력을
## 거는 특수가 늘면(장대의 사거리 배율 같은 것) 그 버프를 이 줄에 더하면 되고, 무기 표에
## 새 필드를 만들 필요가 없다. 잔상(`trail_ghosts`)이 무기 표에서 켜지는 것과 다른 판단인
## 이유: 잔상은 **무기의 생김새**라 무기마다 다르지만, 전격은 **"스킬이 켜졌다"는 표시**라
## 어느 무기든 같은 뜻이다.
##
## 자리는 이미 복제되는 `position`·버프 시각에서 나오므로 각 피어가 자기 화면 값으로
## 알아서 그린다 — RPC를 더하지 않는다(잔상·연기와 같은 방식, 버전 악수 #228에 영향 없음).
func _update_skill_arcs() -> void:
	var arcs: SkillArcs = $Arcs
	# 죽은 젤리에는 켜지 않는다 — 버프가 남은 채로 죽으면 시체에서 번개가 튄다.
	arcs.active = alive and (is_piercing() or stun_bonus() > 0.0)


## 지금 화면에 그려진 무기 날의 양끝 (전역 좌표, [날 끝, 손잡이]).
##
## `_update_weapon_shape()`가 이미 정해 놓은 스프라이트의 `position`·`scale`·`rotation`·
## `offset`에서 **되짚어** 계산한다 — 자세를 잡는 곳이 한 곳이므로, 세워 든 것이든 눕혀 든
## 것이든(장대) 휘두르는 중이든(검 #247) 늘어난 중이든 잔상이 저절로 따라간다. 자세를
## 여기서 다시 계산하면 언젠가 두 곳이 갈라지고, 그때 잔상만 엉뚱한 자리에 남는다.
##
## `centered`가 켜져 있어 텍스처 가운데가 `offset` 자리에 그려지고, 여백을 뺀 실제 그림의
## 가운데는 거기서 `_weapon_content_offset`만큼 되돌린 자리다(그 값이 "텍스처 가운데 →
## 그림 가운데"의 반대 방향으로 잡혀 있다). `flip_h`는 그림을 offset 기준으로 되접으므로
## 좌우 보정의 부호도 뒤집는다 — `_place_swinging_weapon()`이 같은 이유로 같은 일을 한다.
func _blade_ends() -> Array[Vector2]:
	var sprite: Sprite2D = $WeaponSprite
	var corrected_x := _weapon_content_offset.x
	if sprite.flip_h:
		corrected_x = -corrected_x
	var center := sprite.offset - Vector2(corrected_x, _weapon_content_offset.y)
	# 날은 원화의 위쪽 끝이다 (README의 "날 끝이 위"). 화면 좌표는 y가 아래라 위가 음수다.
	var half := _weapon_content_length * 0.5
	return [
		_sprite_to_global(sprite, center + Vector2(0.0, -half)),
		_sprite_to_global(sprite, center + Vector2(0.0, half)),
	]


## 스프라이트 안의 점을 전역 좌표로. Sprite2D의 변환은 배율 → 회전 → 이동 순서다.
func _sprite_to_global(sprite: Sprite2D, point: Vector2) -> Vector2:
	return to_global(sprite.position + (point * sprite.scale).rotated(sprite.rotation))


## 원화를 눕혀 **바라보는 쪽으로 뻗어** 놓는다 (장대, `art_held_forward`).
##
## 사거리 판정은 가로 방향이고(`current_reach()`), 그림이 없던 동안 이 자리를 채웠던
## 임시 막대도 몸 가운데에서 앞으로 뻗는 가로 막대였다. 세워 들면 늘어나는 방향이
## 판정 방향과 어긋나서, 길어져도 "앞이 길어졌다"로 읽히지 않는다.
##
## **여백 보정을 `position`이 아니라 `Sprite2D.offset`으로 한다** — offset은 회전·배율이
## 나중에 걸리는 값이라 눕힌 뒤에도 보정이 그림과 같이 돈다. position으로 하면 90도
## 어긋난 방향으로 밀린다 (projectile.gd가 회전하는 탄에서 같은 이유로 offset을 쓴다).
##
## 뒤쪽 끝(주황 구슬)을 몸 가운데에 붙이고 앞으로만 뻗게 하려고 offset을 원화 길이의
## 절반만큼 더 올린다. 그러면 원점이 뒤쪽 끝이 되어 **늘어날 때 앞으로만 자란다** —
## 세워 드는 쪽에서 필요했던 위치 보정이 여기서는 필요 없다.
func _place_forward_weapon(sprite: Sprite2D) -> void:
	sprite.flip_h = false
	# 화면 좌표는 y가 아래라 +90도가 위(원화의 날 끝)를 오른쪽으로 보낸다.
	sprite.rotation = PI * 0.5 * facing
	sprite.offset = Vector2(
		_weapon_content_offset.x,
		_weapon_content_offset.y - _weapon_content_length * 0.5,
	)
	sprite.position = Vector2(0.0, WEAPON_CENTER_Y)


## 지금 톱이 돌고 있는가 (#260) — 제자리 회전이든 그대로 이어진 돌진이든.
##
## **무기 이름을 보지 않는다.** 강제 이동의 `"spin"`·`"dash"`는 전기톱만 쓰는 단계라
## 상태 하나로 갈린다(도끼는 `rise`·`hover`·`fall`이다) — 켜는 조건을 상태에서 읽는 것은
## 전격(`_update_skill_arcs()`)과 같은 판단이다. 그림이 없는 무기는 돌릴 것이 없으므로 뺀다.
func is_spinning() -> bool:
	return _weapon_has_art and (forced_mode == "spin" or forced_mode == "dash")


## 톱이 지금 돌아간 각(라디안). 바라보는 쪽으로 굴러가는 바퀴처럼 돈다 —
## 오른쪽을 보면 시계방향(화면 좌표는 y가 아래라 양수가 시계방향)이다.
##
## 시작 시각 하나에서 나오고 그 값이 복제되므로 두 화면이 같은 자세를 그린다.
func _spin_angle() -> float:
	if _spin_started_at < 0.0:
		return 0.0
	return (_now() - _spin_started_at) * TAU * SPIN_TURNS_PER_SECOND * facing


## 도는 톱을 **그림 한가운데를 축으로** 놓는다 (#260).
##
## 내려베기(`_place_swinging_weapon()`)가 쥔 자리를 축으로 삼는 것과 다르다 — 저쪽은
## 들어 올렸다 내려치는 동작이라 손이 축이어야 하고, 이쪽은 톱이 통째로 도는 동작이라
## 가운데가 축이어야 톱날 끝이 고른 원을 그린다.
##
## **여백 보정을 `position`이 아니라 `Sprite2D.offset`으로 한다** — offset은 회전·배율이
## 나중에 걸리는 값이라 돌아간 뒤에도 보정이 그림과 같이 돈다(`_place_forward_weapon`·
## `_place_swinging_weapon`과 같은 이유). 뒤집힌 그림은 좌우 보정의 부호가 반대다.
func _place_spinning_weapon(sprite: Sprite2D, flipped: bool) -> void:
	sprite.flip_h = flipped
	sprite.rotation = _spin_angle()
	var corrected_x := _weapon_content_offset.x
	if flipped:
		corrected_x = -corrected_x
	sprite.offset = Vector2(corrected_x, _weapon_content_offset.y)
	sprite.position = Vector2(facing * WEAPON_OFFSET_X, WEAPON_CENTER_Y)


## 도는 톱이 그리는 원과, 돌진하며 가르는 바람 (#260).
##
## 자리·반지름·각도는 이미 정해진 스프라이트 자세에서 **되짚어** 넘긴다 — 잔상
## (`_update_weapon_trail()`)이 `_blade_ends()`로 하는 것과 같은 이유다. 여기서 다시
## 계산하면 언젠가 두 곳이 갈라지고, 그때 원만 톱과 어긋난 자리에 남는다.
func _update_chainsaw_whirl() -> void:
	var whirl: ChainsawWhirl = $Whirl
	var spinning := alive and is_spinning()
	whirl.active = spinning
	if not spinning:
		return
	var sprite: Sprite2D = $WeaponSprite
	whirl.dashing = forced_mode == "dash"
	whirl.pivot = sprite.position
	# 톱날 끝까지의 거리 — 화면에 그려진 가로 길이의 절반이다.
	whirl.radius = _weapon_content_width * 0.5 * absf(sprite.scale.x)
	# 각도 0일 때 톱날은 **바라보는 쪽**을 향한다(`flip_h`가 그렇게 맞춰 놓는다).
	# 화면 좌표에서 왼쪽은 PI 방향이다.
	whirl.tip_angle = sprite.rotation + (0.0 if facing > 0 else PI)
	whirl.spin_sign = signf(facing)
	# 바람은 가는 쪽의 반대로 흐른다.
	whirl.wind_sign = -signf(facing)


## 지금 검을 들어 올렸다 내려베는 중인가 (#247).
##
## 다 벤 뒤 평소 자세로 돌아오는 `SWING_RECOVER`까지 포함한다 — 돌아오는 도중에
## false가 되면 검이 벤 자세에서 한 프레임 만에 제자리로 튄다.
func is_swinging() -> bool:
	if _swing_started_at < 0.0:
		return false
	return _now() - _swing_started_at < _swing_windup + _swing_swing + SWING_RECOVER


## 휘두르는 동작의 지금 자세 — `angle`(라디안)과 `lift`(들린 높이 px).
##
## 세 구간으로 나뉜다. **들어 올리기**는 끝으로 갈수록 느려져 머리 위에서 멈칫하고,
## **내려베기**는 반대로 갈수록 빨라져 데미지가 들어가는 순간에 가장 빠르다.
## 남은 **되돌리기**는 부드럽게 평소 자세로 온다.
##
## 시간은 `_swing_started_at` 하나에서 나오고 그 값이 복제되므로 두 화면이 같은
## 자세를 그린다. 판정 시각은 여기가 아니라 main.gd 가 재는 것이라, 몇 프레임
## 어긋나도 맞는 시점은 흔들리지 않는다.
func _swing_pose() -> Dictionary:
	var raised := -deg_to_rad(SWING_RAISE_DEGREES)
	var cut := deg_to_rad(SWING_DOWN_DEGREES)
	var t := _now() - _swing_started_at

	if t < _swing_windup:
		var up := t / maxf(_swing_windup, 0.001)
		up = 1.0 - (1.0 - up) * (1.0 - up)
		return {"angle": raised * up, "lift": SWING_LIFT * up}

	t -= _swing_windup
	if t < _swing_swing:
		var down := t / maxf(_swing_swing, 0.001)
		return {
			"angle": lerpf(raised, cut, down * down),
			"lift": SWING_LIFT * (1.0 - down * down),
		}

	t -= _swing_swing
	var back := clampf(t / maxf(SWING_RECOVER, 0.001), 0.0, 1.0)
	return {"angle": lerpf(cut, 0.0, smoothstep(0.0, 1.0, back)), "lift": 0.0}


## 휘두르는 동안 검을 **쥔 자리**를 축으로 돌린다 (#247).
##
## 평소에는 그림 한가운데를 몸 옆에 놓지만, 그 상태로 돌리면 검이 제 허리를 축으로
## 헬리콥터처럼 돈다. 아래쪽 끝(손잡이)이 축이어야 들어 올렸다 내려치는 것으로 읽힌다.
##
## **여백 보정을 `position`이 아니라 `Sprite2D.offset`으로 한다** — offset은 회전이
## 나중에 걸리는 값이라 돌아간 뒤에도 보정이 그림과 같이 돈다(`_place_forward_weapon`
## 과 같은 이유). 뒤집힌 그림은 좌우 보정도 각도도 반대다: `flip_h`는 그림을 offset을
## 기준으로 되접으므로, 통째로 거울에 비추려면 둘 다 부호를 뒤집어야 한다.
##
## 축을 놓는 자리는 **평소에 그리던 그림의 아래쪽 끝**이다 — 세워 든 자세(각도 0)가
## 지금까지의 모습과 정확히 겹쳐야 휘두르기 시작할 때 검이 튀지 않는다.
func _place_swinging_weapon(sprite: Sprite2D, flipped: bool, pose: Dictionary,
		tall: float) -> void:
	sprite.flip_h = flipped
	sprite.rotation = float(pose["angle"]) * facing
	var corrected_x := _weapon_content_offset.x
	if flipped:
		corrected_x = -corrected_x
	# 그림을 제 길이의 절반만큼 올려 아래쪽 끝이 원점에 오게 한다.
	sprite.offset = Vector2(
		corrected_x,
		_weapon_content_offset.y - _weapon_content_length * 0.5,
	)
	sprite.position = Vector2(
		facing * WEAPON_OFFSET_X,
		WEAPON_CENTER_Y + _weapon_art_length * tall * 0.5 - float(pose["lift"]),
	)


## 사거리 버프를 그림 길이로 옮긴다 (장대 특수).
##
## **무기 표가 허락한 무기만 늘어난다**(`art_grows_with_reach`). 사거리 버프는 다른 무기도
## 받을 수 있으므로 조건 없이 늘리면 검이 고무처럼 자란다.
##
## 목표값으로 툭 바뀌지 않고 부드럽게 따라간다 — 한 프레임에 1.6배가 되면 길어진 것이
## 아니라 다른 무기로 바뀐 것처럼 보인다. 목표는 복제된 `_reach_multiplier`에서 나오므로
## 두 화면이 같은 길이로 모인다(가는 도중 몇 프레임 차이는 판정과 무관하다).
##
## `reach_multiplier`(표에 적힌 무기 고유 사거리)가 아니라 **버프 배율**을 쓴다.
## 표의 값은 평소에도 걸려 있어서, 그걸 쓰면 특수를 쓰지 않았는데도 늘어난 채로 있다.
func _art_stretch(delta: float) -> float:
	var target := 1.0
	if Weapons.get_weapon(weapon_id).get("art_grows_with_reach", false):
		target = _reach_multiplier
	_weapon_art_stretch = move_toward(_weapon_art_stretch, target, ART_STRETCH_SPEED * delta)
	return _weapon_art_stretch


## 크기 버프를 그림 크기로 옮긴다 (방패 특수).
##
## `_art_stretch()`와 짜임이 같고 다른 점만 둘이다. 첫째로 **가로세로를 함께** 키운다 —
## 특수가 "크기 증가"라서 한쪽만 늘리면 방패가 찌그러진 것으로 보인다. 둘째로 보는 값이
## `_size_multiplier`다.
##
## **무기 표가 허락한 무기만 커진다**(`art_grows_with_size`). 크기 버프는 이론상 다른
## 무기도 받을 수 있어서, 조건 없이 키우면 방패 아닌 무기가 같이 부푼다.
##
## 그림이 없는 무기는 임시 막대의 **두께**가 이 버프를 보여 주고 있었다
## (`_update_weapon_shape()` 아래쪽). 그림을 붙이면 막대가 사라지므로, 이것이 없으면
## 4초 동안 사거리만 조용히 2배가 되고 화면에는 아무 표시도 남지 않는다 — 장대가
## 겪은 것과 같은 일이고 `art_grows_with_reach`가 그림 쪽에서 되살린 것도 같다.
##
## 목표가 복제된 `_size_multiplier`에서 나오므로 두 화면이 같은 크기로 모인다.
func _art_growth(delta: float) -> float:
	var target := 1.0
	if Weapons.get_weapon(weapon_id).get("art_grows_with_size", false):
		target = _size_multiplier
	_weapon_art_growth = move_toward(_weapon_art_growth, target, ART_STRETCH_SPEED * delta)
	return _weapon_art_growth


## 무기 표시. 그림이 있으면 그림을, 없으면 지금까지의 임시 막대를 쓴다.
## 어느 쪽이든 특수 공격 쿨타임 상태를 밝기·색으로 보여준다 (별도 UI 없음).
func _update_weapon_shape(delta: float) -> void:
	var shape: ColorRect = $WeaponShape
	var sprite: Sprite2D = $WeaponSprite
	if Weapons.get_weapon(weapon_id).is_empty():
		shape.hide()
		sprite.hide()
		return

	if _weapon_has_art:
		shape.hide()
		sprite.show()
		# 사거리가 늘어난 만큼 그림을 늘인다 (장대 특수). **길이와 굵기를 같은 배율로
		# 늘리지 않는다** — 봉이 길어지는 것이 요점이므로 굵기는 `ART_THICKEN_SHARE`만큼만
		# 따라간다. 길이만 늘리면 늘어난 봉이 실처럼 가늘어 보이고, 같이 늘리면
		# 길어진 것이 아니라 무기가 통째로 커진 것으로 보인다.
		var stretch := _art_stretch(delta)
		var thicken := 1.0 + (stretch - 1.0) * ART_THICKEN_SHARE
		# 크기 버프는 반대로 **가로세로를 같은 배율로** 키운다 (방패 특수) — 특수가
		# "크기 증가"라서 한쪽만 늘리면 커진 것이 아니라 찌그러진 것으로 보인다.
		# 늘어난 정도와 곱해서 쓰므로 둘 중 하나만 걸린 무기는 지금까지와 똑같다.
		var growth := _art_growth(delta)
		sprite.scale = Vector2(
			_weapon_art_factor * thicken * growth,
			_weapon_art_factor * stretch * growth,
		)
		# 원화는 오른쪽 보기가 기본이라 왼쪽을 볼 때 뒤집는다. 다만 왼쪽을 보고 그려진
		# 원화(전기톱)는 조건이 정반대다 — 안 그러면 톱날이 등 뒤로 간다 (#109).
		# 뒤집으면 그림이 스프라이트 중심을 기준으로 반전되므로 여백 보정도 반대로 간다.
		var flipped := (facing < 0) != _weapon_faces_left
		# **세로로 걸린 배율 전체**(늘어난 정도 × 커진 정도). 세워 드는 쪽도 휘두르는
		# 쪽도 이 값으로 그림의 아래쪽 끝을 제자리에 둔다 — 커진 쪽만 빼고 재면
		# 방패가 커지는 동안 아래쪽 절반이 땅에 파묻힌다.
		var tall := stretch * growth
		if _weapon_art_forward:
			_place_forward_weapon(sprite)
		elif is_spinning():
			# 전기톱 특수 — 제자리 회전부터 돌진이 끝날 때까지 톱이 계속 돈다 (#260).
			# 내려베기보다 먼저 본다: 둘이 겹칠 일은 없지만, 겹친다면 강제 이동 쪽이
			# 조작을 잠근 상태라 그쪽이 지금 무엇을 하고 있는지에 더 가깝다.
			_place_spinning_weapon(sprite, flipped)
		elif is_swinging():
			# 검 특수 — 쥔 자리를 축으로 들어 올렸다 내려벤다 (#247).
			# 각도가 0인 순간의 모습이 아래 세워 든 자세와 겹치므로 이어져 보인다.
			_place_swinging_weapon(sprite, flipped, _swing_pose(), tall)
		else:
			sprite.flip_h = flipped
			sprite.rotation = 0.0
			sprite.offset = Vector2.ZERO
			# 여백 보정도 굵어진·커진 배율을 따라간다 — 안 그러면 굵어질 때 그림이 옆으로 밀린다.
			var corrected := _weapon_offset.x * thicken * growth
			var offset_x := -corrected if flipped else corrected
			# 늘어난 길이의 절반만큼 위로 올려 손에 쥔 아래쪽 끝을 제자리에 둔다.
			# Sprite2D는 자기 위치를 가운데로 두고 커지므로, 안 올리면 아래로도 자란다.
			sprite.position = Vector2(
				facing * WEAPON_OFFSET_X + offset_x,
				WEAPON_CENTER_Y + _weapon_offset.y * tall
					- _weapon_art_length * (tall - 1.0) * 0.5,
			)
		if is_piercing():
			sprite.modulate = PIERCE_TINT              # 관통 중 — 날이 타오른다
		elif is_spinning():
			# 도는 동안은 **밝게 둔다** (#260). 아래 회색은 "지금 못 움직인다"는 표시인데,
			# 전기톱 특수는 못 움직이는 것이 기절이 아니라 제 기술이라 회색이면
			# 톱을 돌리는 중인지 굳어 있는지가 뒤집혀 읽힌다.
			sprite.modulate = Color.WHITE
		elif not can_act():
			sprite.modulate = Color(0.45, 0.45, 0.5)   # 기절·사망·강제 이동
		elif special_ready:
			sprite.modulate = Color.WHITE              # 특수 공격 가능
		else:
			sprite.modulate = Color(0.7, 0.7, 0.75)    # 쿨타임 중
		return

	# 그림이 없는 무기 — 길이는 사거리, 두께는 크기 증가를 나타낸다.
	sprite.hide()
	shape.show()
	var length := current_reach()
	var thickness := 10.0 * _size_multiplier
	shape.size = Vector2(length, thickness)
	shape.position = Vector2(0.0 if facing > 0 else -length, -thickness * 0.5)

	if is_piercing():
		shape.color = PIERCE_COLOR             # 관통 중 (그림이 아직 없는 무기용)
	elif not can_act():
		shape.color = Color(0.45, 0.45, 0.5)   # 기절·사망·강제 이동
	elif special_ready:
		shape.color = Color(0.95, 0.95, 1.0)   # 특수 공격 가능
	else:
		shape.color = Color(0.55, 0.55, 0.62)  # 쿨타임 중


## 현재 사거리. 장대의 특수 공격이나 방패 크기 증가로 늘어난다.
func current_reach() -> float:
	var data := Weapons.get_weapon(weapon_id)
	if data.is_empty():
		return 0.0
	var base: float = BASE_REACH * data.get("reach_multiplier", 1.0)
	return base * _reach_multiplier * _size_multiplier


func _physics_process(delta: float) -> void:
	if is_local_player():
		_send_input()

	if multiplayer.is_server():
		_check_long_press()
		apply_movement(_take_input(), delta)
		_send_state()
		_update_squash(is_on_floor(), delta)
	else:
		# 클라이언트는 물리를 계산하지 않고 서버가 보낸 위치로 따라간다
		global_position = global_position.lerp(_target_position, minf(INTERPOLATION_SPEED * delta, 1.0))
		_update_squash(_remote_on_floor, delta)

	_expire_buffs()
	_update_pierce_aura()
	_update_weapon_shape(delta)
	_update_weapon_smoke()
	# 잔상은 무기 자세가 정해진 **뒤에** 남긴다 — 앞에 두면 한 프레임 전 자리를 남긴다.
	_update_weapon_trail()
	# 도는 톱의 원도 무기 자세가 정해진 **뒤에** 잰다 — 잔상과 같은 이유다.
	_update_chainsaw_whirl()
	_update_skill_arcs()
	# 바라보는 방향으로 그림을 뒤집는다. facing은 서버가 정해 양쪽에 복제된다.
	# 여백 보정의 부호는 _place_body()가 flip_h를 보고 맞춘다.
	$Body.flip_h = facing < 0
	_place_body()


## 위치·속도를 **전투 화면에 있는 피어에게만** 보낸다 (서버 전용, 매 프레임).
##
## 브로드캐스트(`rpc()`)로 보내면 대기실에 앉아 있는 피어에게도 날아간다 — 그쪽에는 이 노드가
## 없으니 받을 수 없고 "Node not found" 오류만 초당 60번 쌓인다. 관전이 생기면서
## 전투 화면 밖에 있는 피어가 정상 상태가 되었으므로(이슈 #167) 대상을 골라 보낸다.
func _send_state() -> void:
	for peer in Lobby.viewers:
		_receive_state.rpc_id(peer, global_position, velocity, is_on_floor(), facing)


## 자기 입력을 서버로 보낸다.
## 점프와 Shift는 한 프레임짜리 엣지라 별도 reliable RPC로 보낸다.
func _send_input() -> void:
	var input := read_input()
	_receive_move_input.rpc_id(1, input["direction"], input["fast_fall"])
	if input["jump"]:
		_receive_jump.rpc_id(1)
	var skill: bool = input["skill"]
	if skill != _skill_was_pressed:
		_skill_was_pressed = skill
		_receive_skill.rpc_id(1, skill)


## 서버가 보관 중인 입력을 꺼낸다. 점프는 한 번만 소비된다.
func _take_input() -> Dictionary:
	var input := {
		"direction": _input_direction,
		"jump": _jump_queued,
		"fast_fall": _input_fast_fall,
	}
	_jump_queued = false
	return input


## 길게 누른 것이 확정되는 순간 바로 발동한다 (뗄 때까지 기다리지 않는다).
## 서버 전용 — 누른 시간을 서버가 재야 클라이언트가 길게/짧게를 속일 수 없다.
func _check_long_press() -> void:
	if _skill_held_since < 0.0:
		return
	if _now() - _skill_held_since >= LONG_PRESS_TIME:
		_skill_held_since = -1.0
		special_requested.emit(owner_peer_id, true)


# ─────────────────────────── 입력 수신 (서버 전용) ───────────────────────────

## 이동 입력 수신. 매 프레임 덮어써지므로 유실을 허용한다.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_move_input(direction: float, fast_fall: bool) -> void:
	if not _is_owner_input():
		return
	_input_direction = clampf(direction, -1.0, 1.0)
	_input_fast_fall = fast_fall


## 점프 입력 수신. 유실되면 점프가 씹히므로 reliable로 받는다.
@rpc("any_peer", "call_remote", "reliable")
func _receive_jump() -> void:
	if not _is_owner_input():
		return
	_jump_queued = true


## Shift 누름·뗌 수신. 엣지라 유실되면 안 되므로 reliable로 받는다.
@rpc("any_peer", "call_remote", "reliable")
func _receive_skill(pressed: bool) -> void:
	if not _is_owner_input():
		return
	if pressed:
		_skill_held_since = _now()
	elif _skill_held_since >= 0.0:
		_skill_held_since = -1.0
		special_requested.emit(owner_peer_id, false)


## 서버가 받은 입력 RPC가 이 플레이어의 주인이 보낸 것인지.
## 없으면 남의 플레이어를 조작할 수 있다.
func _is_owner_input() -> bool:
	if not multiplayer.is_server():
		return false
	return multiplayer.get_remote_sender_id() == owner_peer_id


## 서버가 정한 상태 수신 (클라이언트 전용).
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state(server_position: Vector2, server_velocity: Vector2, on_floor: bool, server_facing: int) -> void:
	_target_position = server_position
	velocity = server_velocity
	_remote_on_floor = on_floor
	facing = server_facing


# ─────────────────────────── 상태 조회 ───────────────────────────

func is_invulnerable(source := "basic") -> bool:
	return _now() < _invuln_until.get(source, 0.0)


func is_stunned() -> bool:
	return _now() < _stun_until


## 관통 상태에서는 상대 무기가 공격을 막지 못한다.
func is_piercing() -> bool:
	return _now() < _pierce_until


## 지금 내 기본 공격에 얹히는 기절 길이(초). 망치 특수가 켜져 있지 않으면 0 이다.
##
## **켜졌는지 묻는 함수와 값을 주는 함수를 나누지 않았다** — 0 이 곧 "안 켜졌다"이고,
## `server_apply_hit` 에 그대로 넘길 수 있어서 부르는 쪽에 조건문이 필요 없다.
func stun_bonus() -> float:
	return _stun_grant if _now() < _stun_grant_until else 0.0


## 방패를 크게 들어 올린 동안인가 (방패 특수, 무기 표의 `size_buff_guards`).
##
## 그동안 **날아오는 탄이 막히고**(`Projectile._on_body_entered`) 그 대신 **기본 근접
## 공격이 안 나간다**(`Main._try_melee_basic`). 크게 든 방패로 몸을 가리는 자세라
## 그 자세로 때릴 수는 없다는 것이다.
##
## 근접 막기는 여기서 따로 하지 않는다 — 크기 버프가 `current_reach()`를 2배로 늘려서
## `Main.is_blocked()`의 "상대 사거리 > 내 사거리"가 이미 참이 된다.
##
## `_size_multiplier`는 `_receive_buff`로 두 피어에 복제되므로 양쪽이 같은 판단을 한다.
## 무기 표를 함께 보는 이유는 크기 버프를 다른 무기가 받게 되어도 그쪽이 막는 자세가
## 되지는 않아야 하기 때문이다.
func is_guarding() -> bool:
	return _size_multiplier > 1.0 and Weapons.size_buff_guards(weapon_id)


## 이 무기가 게이지를 쓰는가 (#225). 머리 위 게이지 바가 뜰지 정하는 조건이고,
## 지금 이 값을 가진 것은 너클뿐이다.
func uses_gauge() -> bool:
	return Weapons.get_weapon(weapon_id).get("gauge_max", 0.0) > 0.0


## 게이지가 얼마나 찼는가 (0~1). 게이지를 쓰지 않는 무기는 0이다.
func gauge_ratio() -> float:
	var top: float = Weapons.get_weapon(weapon_id).get("gauge_max", 0.0)
	if top <= 0.0:
		return 0.0
	return clampf(gauge / top, 0.0, 1.0)


## 오라가 돌 만큼 게이지가 찼는가 (너클 75% 이상, #225).
##
## 이 하나가 **오라·게이지 바 색·강펀치 연출 디자인**을 함께 정한다 — 세 곳이 각자
## 기준을 두면 셋이 어긋난 순간이 생긴다.
func is_charged() -> bool:
	var need: float = Weapons.get_weapon(weapon_id).get("charged_ratio", 0.0)
	return need > 0.0 and gauge_ratio() >= need


func is_forced() -> bool:
	return forced_mode != ""


func can_act() -> bool:
	return alive and not frozen and not is_stunned() and forced_mode == ""


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _expire_buffs() -> void:
	var now := _now()
	if _reach_multiplier != 1.0 and now >= _reach_until:
		_reach_multiplier = 1.0
	if _size_multiplier != 1.0 and now >= _size_until:
		_size_multiplier = 1.0


# ─────────────────────────── 피격·상태 (서버 판정) ───────────────────────────
# server_* 함수는 서버에서만 호출한다. 결과를 authority RPC로 양쪽에 복제한다.

## 데미지를 적용하고 결과를 전원에게 내려준다.
##
## source 는 "basic" / "special" / "projectile".
## 기본과 특수는 무적 타이머가 따로 돌아가고,
## 허공을 나는 것("projectile")은 공유 무적을 아예 타지 않는다 —
## 활 특수 3발처럼 같은 순간에 도착하는 것도 전부 들어간다.
## `knockback_speed`가 0보다 크면 단계 대신 그 속도로 민다 (대포 총 미사일, #121).
func server_apply_hit(damage: float, knockback_level: int, from_x: float,
		stun := 0.0, source := "basic", knockback_speed := 0.0) -> void:
	if not multiplayer.is_server() or not alive:
		return
	if source != "projectile" and is_invulnerable(source):
		return
	var new_hp: float = maxf(hp - damage, 0.0)
	var direction := signf(global_position.x - from_x)
	if direction == 0.0:
		direction = 1.0
	# 너클은 내가 맞을 때 게이지가 찬다. **받은 데미지에 비례한다** (#225).
	var was_charged := is_charged()
	var new_gauge := _gauge_after(damage)
	_receive_hit.rpc(new_hp, knockback_level, direction, stun, source, new_gauge, knockback_speed)
	# 이 한 방으로 75%를 넘었는지 본다 (#225). `_receive_hit`이 `call_local`이라
	# 여기서는 이미 새 게이지가 들어가 있다.
	_emit_gauge_charged(was_charged)
	# **무적·사망 검사를 다 지난 뒤에 낸다** — 위에서 걸러진 것은 맞은 것이 아니다.
	# 데미지 0(넉백만 주는 것)도 뺀다: "피해를 입었다"가 이 신호의 뜻이다.
	if damage > 0.0:
		damaged.emit(owner_peer_id, false)
	# **데미지와 조건이 다르다** — 기절이 얹혀 있으면 데미지가 0이어도 굳는다.
	# 무적·사망 검사를 다 지난 뒤인 것은 위와 같다.
	if stun > 0.0:
		stunned.emit(owner_peer_id)


## 출혈 같은 지속 데미지. 무적 시간을 무시하고 들어가고, 넉백도 없다.
func server_apply_dot(damage: float) -> void:
	if not multiplayer.is_server() or not alive:
		return
	_receive_dot.rpc(maxf(hp - damage, 0.0))
	# 지속 데미지도 피해다 — 다만 촘촘히 들어오므로 `continuous` 를 참으로 실어,
	# 소리를 울릴 박자를 받는 쪽(main.gd)이 따로 잡게 한다.
	if damage > 0.0:
		damaged.emit(owner_peer_id, true)
	# 출혈도 "받은 데미지"다 (#225) — 너클 게이지는 여기서도 찬다.
	# `_receive_dot` 의 인자를 늘리지 않고 따로 보내는 것은, 게이지를 쓰지 않는 무기에는
	# 보낼 것이 없어서다(아래 비교에서 걸러진다).
	var was_charged := is_charged()
	var filled := _gauge_after(damage)
	if not is_equal_approx(filled, gauge):
		server_set_gauge(filled)
		_emit_gauge_charged(was_charged)


## 이만큼 데미지를 받은 뒤의 게이지 (#225).
##
## **받은 데미지에 비례해 찬다** — 무기 표의 `gauge_fill_damage`(너클 40)만큼 받으면
## `gauge_max`(100)가 된다. 그 위로는 넘지 않는다.
## 게이지를 쓰지 않는 무기(그 필드가 없는 무기)는 지금 값을 그대로 돌려준다.
func _gauge_after(damage: float) -> float:
	var data := Weapons.get_weapon(weapon_id)
	var fill: float = data.get("gauge_fill_damage", 0.0)
	if fill <= 0.0 or damage <= 0.0:
		return gauge
	var top: float = data["gauge_max"]
	return minf(gauge + damage * top / fill, top)


## 게이지가 이번 피해로 **75%를 넘어섰으면** 한 번 알린다 (#225).
##
## `was_charged`는 게이지가 차기 **전에** 잰 `is_charged()`다. 이미 차 있었으면 아무 일도
## 없다 — 문턱을 넘는 그 한 번만이 소리를 낼 자리다.
##
## 게이지를 쓰지 않는 무기는 `is_charged()`가 늘 거짓이라 여기서 저절로 걸러진다.
## 쓰러진 젤리도 뺀다: 마지막 한 방에 죽으면서 게이지가 찬 것은 들려줄 것이 아니다.
func _emit_gauge_charged(was_charged: bool) -> void:
	if was_charged or not alive or not is_charged():
		return
	gauge_charged.emit(owner_peer_id)


## 데미지 없는 사망 (낙사 등).
func server_kill() -> void:
	if not multiplayer.is_server() or not alive:
		return
	_receive_dot.rpc(0.0)


## 다음 라운드를 위해 되살린다. 위치·방향은 맵의 스폰 지점을 서버가 정해서 넘긴다.
func server_reset(spawn_position: Vector2, spawn_facing: int) -> void:
	if not multiplayer.is_server():
		return
	_receive_reset.rpc(spawn_position, spawn_facing)


## 순간이동 (빨간 표창의 1P·2P 위치 교환).
##
## **`_receive_state`(unreliable)로는 안 된다.** 그쪽은 클라이언트가 `_target_position`을
## 향해 부드럽게 따라가는 값이라, 화면 반대편으로 던져 넣으면 젤리가 맵을 가로질러
## **미끄러져 간다.** 라운드 초기화(`_receive_reset`)와 같이 위치와 목표를 함께 박아야
## 그 자리에서 사라졌다 나타난다.
##
## 속도는 건드리지 않는다 — 뛰던 사람은 뛰던 기세 그대로 상대 자리에 선다.
func server_teleport(to: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_receive_teleport.rpc(to)


@rpc("authority", "call_local", "reliable")
func _receive_teleport(to: Vector2) -> void:
	global_position = to
	_target_position = to
	# 옛 자리의 잔상을 버린다 (#253) — 안 버리면 두 자리를 잇는 줄이 한 번 그려진다.
	# `WeaponTrail`의 거리 문턱도 같은 것을 막지만, 자리가 바뀌는 것을 아는 곳이 여기다.
	$Trail.clear()
	# 돌진하며 남긴 바람도 같이 버린다 (#260) — 빨간 표창이 돌진 중인 상대를 옮기면
	# 옛 자리의 줄무늬가 새 자리에서 한 번 더 그려진다.
	$Whirl.clear()


## 사거리·크기·관통 버프.
func server_apply_buff(kind: String, value: float, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_receive_buff.rpc(kind, value, duration)


## 다음 폭탄이 강화인지를 서버가 정해 양쪽에 알린다 (#134).
##
## **뽑기는 main.gd가 한다** — 전투 판정의 주인이 거기이고, 라운드 시작과 던진 직후라는
## 시점도 거기가 안다. 여기는 결과를 복제하고 그림을 갈아 끼우는 일만 한다.
func server_set_empowered(value: bool) -> void:
	if not multiplayer.is_server():
		return
	_receive_empowered.rpc(value)


## 이번 라운드에 들 무기를 갈아 끼운다 (#205). 서버가 선택 결과를 확정한 뒤 부른다.
##
## 무기는 스폰할 때 한 번 박히는 값이었는데(대기실에서 고른 것), 라운드마다 새로
## 고르게 되면서 경기 중에 바뀌는 값이 되었다. 판정에 쓰는 수치도 그림도 전부
## `weapon_id` 하나에서 나오므로(`Weapons.get_weapon`) 이 값만 바꾸면 둘 다 따라온다.
func server_set_weapon(new_weapon: String) -> void:
	if not multiplayer.is_server():
		return
	_receive_weapon.rpc(new_weapon)


## 무기 선택 중 조작 잠금 (#205).
func server_set_frozen(value: bool) -> void:
	if not multiplayer.is_server() or frozen == value:
		return
	_receive_frozen.rpc(value)


## 승리·패배 포즈 (#176). 판정은 main.gd가 한다 — 누가 점수를 얻었는지 아는 곳이 거기다.
##
## **패배 포즈는 여기를 거치지 않는다** — `_check_death()`가 이미 모든 피어에서 돌아가므로
## 죽음과 함께 저절로 복제된다. 라운드 대기 중에 남은 쪽이 또 떨어져도(그때
## `_on_player_died()`는 일찍 돌아온다) 패배 포즈가 빠지지 않는 이유다.
func server_set_pose(value: String) -> void:
	if not multiplayer.is_server() or pose == value:
		return
	_receive_pose.rpc(value)


## 너클 게이지는 특수 공격을 쓰면 전부 소모된다.
func server_set_gauge(value: float) -> void:
	if not multiplayer.is_server():
		return
	_receive_gauge.rpc(value)


## 특수 공격 쿨타임 상태. 무기 도형 색에 쓰고, `ready_file`이 있는 무기(양날 도끼)는
## 이 값으로 손에 든 **그림 자체**가 바뀐다 — `_receive_special_ready()` 참고.
func server_set_special_ready(value: bool) -> void:
	if not multiplayer.is_server() or special_ready == value:
		return
	_receive_special_ready.rpc(value)


## 검을 들어 올렸다 내려베는 동작을 시작한다 (#247).
##
## **그림만 움직인다.** 데미지는 main.gd 가 같은 시간을 재서 다 내려온 순간에 넣는다 —
## 판정을 여기로 가져오면 무기 표를 읽고 상대를 고르는 일이 두 곳으로 갈라진다.
## 강제 이동(`server_start_forced`)과 달리 조작을 막지 않는다: 벤 뒤 제자리로
## 돌아오는 동안까지 멈춰 세우면 0.5초 넘게 굳어 버린다.
func server_start_swing(windup: float, swing: float) -> void:
	if not multiplayer.is_server():
		return
	_receive_swing.rpc(windup, swing)


## 강제 이동 시작.
func server_start_forced(mode: String, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_receive_forced.rpc(mode, duration)


func server_end_forced() -> void:
	if not multiplayer.is_server():
		return
	_receive_forced.rpc("", 0.0)


# ─────────────────────────── 결과 수신 (서버 → 전원) ───────────────────────────

@rpc("authority", "call_local", "reliable")
func _receive_hit(new_hp: float, knockback_level: int, direction: float,
		stun: float, source: String, new_gauge: float, knockback_speed := 0.0) -> void:
	hp = new_hp
	gauge = new_gauge
	if source != "projectile":
		_invuln_until[source] = _now() + Combat.INVULNERABLE_TIME
	if stun > 0.0:
		_stun_until = _now() + stun
	# 넉백은 물리를 계산하는 서버에서만 적용한다.
	if multiplayer.is_server() and direction != 0.0:
		velocity = Combat.knockback_velocity(knockback_level, direction, knockback_speed)
		_knockback_until = _now() + KNOCKBACK_CONTROL_LOCK
	_check_death()


## 손에 든 폭탄이 바뀐다 (#134). 그림만 갈아 끼우므로 판정과는 무관하다.
@rpc("authority", "call_local", "reliable")
func _receive_empowered(value: bool) -> void:
	if empowered_ready == value:
		return
	empowered_ready = value
	_apply_weapon()


## 무기가 바뀐다 (#205). 그림을 갈아 끼우고 무기 도형도 새 사거리로 다시 잰다.
##
## 지난 무기가 남긴 상태(강화 뽑기·쿨타임)는 여기서 안 지운다 — 라운드 시작이
## `server_reset()` 과 `server_set_empowered()` 로 이미 정리하고 있어서다.
@rpc("authority", "call_local", "reliable")
func _receive_weapon(new_weapon: String) -> void:
	if weapon_id == new_weapon:
		return
	weapon_id = new_weapon
	# 휘두르던 중에 무기가 바뀌면 그 동작은 버린다 (#247) — 새 무기가 남은 각도를
	# 이어받아 혼자 내려치는 일이 없게 한다.
	_swing_started_at = -1.0
	# 돌던 톱도 같은 이유로 버린다 (#260).
	_spin_started_at = -1.0
	$Whirl.clear()
	_apply_weapon()
	_update_weapon_shape(0.0)


## 조작 잠금 (#205). 판정은 `can_act()` 를 보는 쪽들이 알아서 하고 여기는 값만 복제한다.
## 잠그는 순간 서 있던 자리에서 멈춘다 — 밀리던 기세가 남으면 카드를 읽는 동안 미끄러진다.
@rpc("authority", "call_local", "reliable")
func _receive_frozen(value: bool) -> void:
	frozen = value
	if not frozen:
		return
	velocity.x = 0.0
	# 들고 있던 입력도 버린다 — 얼기 직전에 누르고 있던 키가 풀리는 순간 되살아나지 않도록.
	_input_direction = 0.0
	_input_fast_fall = false
	_jump_queued = false
	_skill_held_since = -1.0
	_skill_was_pressed = false


## 포즈만 바꾼다 (#176). 판정과는 무관하고 그림을 갈아 끼우는 일만 한다.
@rpc("authority", "call_local", "reliable")
func _receive_pose(value: String) -> void:
	if pose == value:
		return
	pose = value
	_apply_character()


@rpc("authority", "call_local", "reliable")
func _receive_dot(new_hp: float) -> void:
	hp = new_hp
	_check_death()


## 이 함수는 모든 피어에서 돌아간다 (_receive_hit·_receive_dot이 복제되므로).
## 그래서 패배 포즈는 여기서 걸어도 따로 RPC를 보내지 않아도 양쪽에 같이 뜬다.
func _check_death() -> void:
	if hp > 0.0 or not alive:
		return
	alive = false
	velocity = Vector2.ZERO
	forced_mode = ""
	# 돌진하다 죽으면 톱도 멈춘다 (#260) — `is_spinning()`이 강제 이동 상태를 보므로
	# 위 한 줄로 이미 꺼지지만, 각도를 지워야 다음 라운드가 0도에서 시작한다.
	_spin_started_at = -1.0
	# 반투명으로 죽음을 알리던 것을 포즈가 대신한다 (#176). 흐리게 두면 눕는 원화의
	# 땀방울·효과선이 어두운 맵(용암) 배경에 묻혀 보이지 않는다.
	modulate.a = 1.0
	pose = Characters.POSE_LOSE
	_apply_character()
	if multiplayer.is_server():
		died.emit(owner_peer_id)


## 라운드 초기화. 전투 중에 붙는 상태를 **하나도 남기지 않고** 되돌린다 —
## 여기서 빠뜨린 값은 다음 라운드로 새어 나간다(기절인 채로 시작, 버프 유지 등).
@rpc("authority", "call_local", "reliable")
func _receive_reset(spawn_position: Vector2, spawn_facing: int) -> void:
	hp = Combat.MAX_HP
	alive = true
	facing = spawn_facing
	gauge = 0.0
	special_ready = true
	forced_mode = ""
	modulate.a = 1.0
	# 지난 라운드의 승리·패배 포즈를 벗긴다 (#176) — 안 되돌리면 눕거나 팔을 든 채 싸운다.
	pose = Characters.POSE_IDLE
	_apply_character()

	global_position = spawn_position
	_target_position = spawn_position
	velocity = Vector2.ZERO
	_remote_on_floor = false

	var grace := _now() + Combat.ROUND_START_GRACE
	_invuln_until = {"basic": grace, "special": grace}
	_stun_until = 0.0
	_pierce_until = 0.0
	# 망치가 걸어 둔 "기절을 얹는" 능력도 라운드를 넘기지 않는다 — 관통과 같다.
	_stun_grant_until = 0.0
	_stun_grant = 0.0
	_reach_multiplier = 1.0
	_reach_until = 0.0
	_size_multiplier = 1.0
	_size_until = 0.0
	# 늘어난 그림도 바로 되돌린다. 안 되돌리면 다음 라운드 시작 순간에 장대가
	# 늘어난 채로 나타나서 0.15초 동안 줄어드는 것이 보인다. 커진 그림(방패)도 같다.
	_weapon_art_stretch = 1.0
	_weapon_art_growth = 1.0
	# 휘두르던 검도 세워 든 자세로 돌려놓는다 (#247) — 안 되돌리면 다음 라운드가
	# 벤 자세로 시작해서 0.18초 동안 검이 혼자 일어선다.
	_swing_started_at = -1.0
	# 지난 라운드에 남긴 잔상도 버린다 (#253) — 스폰 지점으로 돌아가는 것이 곧 순간이동이라,
	# 안 버리면 새 라운드 첫 프레임에 죽은 자리에서 스폰 지점까지 줄이 그려진다.
	$Trail.clear()
	# 돌던 톱도 멈춰 세우고 남은 바람을 버린다 (#260) — 강제 이동은 아래 `forced_mode`
	# 초기화가 풀지만, 각도를 안 지우면 다음에 돌릴 때 지난 라운드에 돌던 만큼
	# 앞선 자세에서 시작한다.
	_spin_started_at = -1.0
	$Whirl.clear()
	_forced_deadline = 0.0
	_knockback_until = 0.0

	# 들고 있던 입력도 지운다 — 죽는 순간 누르고 있던 키가 이어지지 않도록.
	_input_direction = 0.0
	_input_fast_fall = false
	_jump_queued = false
	_skill_held_since = -1.0
	_skill_was_pressed = false


@rpc("authority", "call_local", "reliable")
func _receive_special_ready(value: bool) -> void:
	if special_ready == value:
		return
	special_ready = value
	# 쿨타임이 계기인 그림(양날 도끼의 빨간 도끼)은 여기서 갈아 끼워야 한다 (`ready_file`).
	# `_update_weapon_shape()`가 매 프레임 손보는 것은 밝기·색뿐이고 텍스처는 아니다.
	_apply_weapon()


@rpc("authority", "call_local", "reliable")
func _receive_gauge(value: float) -> void:
	gauge = value


@rpc("authority", "call_local", "reliable")
func _receive_forced(mode: String, duration: float) -> void:
	forced_mode = mode
	_forced_deadline = _now() + duration
	# 톱이 도는 시각 (#260). 회전에서 **시작**하고, 돌진으로 넘어갈 때는 건드리지 않는다 —
	# 거기서 다시 잡으면 각도가 0으로 튀어 톱이 한 번 되감긴 것으로 보인다.
	# 나머지 단계(도끼의 rise·hover·fall, 끝남)에서는 지운다.
	if mode == "spin":
		_spin_started_at = _now()
	elif mode != "dash":
		_spin_started_at = -1.0
	if mode == "":
		velocity = Vector2.ZERO
	else:
		_skill_held_since = -1.0


## 내려베기 시작 (#247). 시각을 받아 두면 두 화면이 각자 같은 자세를 그린다 —
## 매 프레임 각도를 보내지 않는 것은 0.5초짜리 동작이라 시작 하나면 충분해서다.
@rpc("authority", "call_local", "reliable")
func _receive_swing(windup: float, swing: float) -> void:
	_swing_started_at = _now()
	_swing_windup = windup
	_swing_swing = swing


@rpc("authority", "call_local", "reliable")
func _receive_buff(kind: String, value: float, duration: float) -> void:
	match kind:
		"reach":
			_reach_multiplier = value
			_reach_until = _now() + duration
		"size":
			_size_multiplier = value
			_size_until = _now() + duration
		"pierce":
			_pierce_until = _now() + duration
		"stun":
			# `value` 는 얹을 기절의 길이(초), `duration` 은 그 능력이 유지되는 시간이다.
			# 다른 버프와 인자 뜻이 같다 — value 가 세기, duration 이 길이다.
			_stun_grant = value
			_stun_grant_until = _now() + duration
