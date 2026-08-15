class_name Combat
extends RefCounted
## 전투 공통 수치. docs/무기_수치_초안.md 에서 확정한 값.
##
## 무기별 수치는 weapons.gd 에 있다.

## 최대 체력. 데미지가 곧 퍼센트로 읽히도록 100 으로 잡았다.
const MAX_HP := 100.0

## 피격 후 무적 시간 (확정). 다발성 무기(활 3발·소총 연사)가 무적에 먹히지 않도록 짧게 잡았다.
const INVULNERABLE_TIME := 0.1

## 근접 기본 공격이 다시 들어가는 간격.
## 무적을 0.3 → 0.1 로 줄이면서 근접 무기 dps 가 3배가 되어버리므로,
## 근접 공격 간격만 따로 고정한다.
##
## 0.3 이었을 때는 "닿으면 일정 데미지" 무기가 표기 데미지의 3.3배/초로 들어가서
## 1초에 한 번인 지속 데미지 무기(광선검·전기톱)보다 3~4배 셌다.
## 0.6 으로 늘려 두 계열을 같은 대역에 맞춘다 — 근거는 무기_수치_초안.md 7절.
##
## **지속 데미지 무기(`basic_kind = "melee_dot"`)의 데미지 간격에는 걸리지 않는다** (이슈 #103).
## 그쪽은 초당 데미지를 표에서 직접 정하므로 바닥을 씌울 이유가 없고, 씌우면
## 0.2초마다 조금씩 들어가는 "지속"을 아예 만들 수 없다.
## 다만 **넉백 간격**으로는 지속 무기에도 계속 쓰인다 — 데미지가 촘촘해져도
## 미는 박자는 다른 근접 무기와 같아야 한다.
const MELEE_HIT_INTERVAL := 0.6

## 라운드 시작 후 이 시간 동안은 서로 피해를 주고받지 않는다.
const ROUND_START_GRACE := 2.0

## 상대를 쓰러뜨리면 1포인트, 이만큼을 먼저 얻으면 승리 (계획서).
## "몇 판을 이겼는가"가 아니라 "몇 포인트를 모았는가"로 센다.
const POINTS_TO_WIN := 3

## 포인트가 나가고 다음 판이 시작되기까지의 대기 시간.
## 죽은 순간 바로 재배치되면 무슨 일이 있었는지 보이지 않는다.
const ROUND_RESTART_DELAY := 2.0

## 3포인트에 도달해 승리가 표시된 뒤 대기실로 돌아가기까지의 시간.
const MATCH_END_DELAY := 4.0

enum Knockback { WEAK, MEDIUM, STRONG }

## 넉백 세기(px/s). 플레이어 이동 속도 320 기준.
const KNOCKBACK_SPEED := {
	Knockback.WEAK: 200.0,
	Knockback.MEDIUM: 400.0,
	Knockback.STRONG: 700.0,
}

## 넉백은 옆으로만 밀지 않고 살짝 띄운다. 안 그러면 바닥 마찰로 바로 멈춘다.
const KNOCKBACK_LIFT := 0.35

## 허공을 나는 것(화살·총알·표창 등)의 속도. 무기별 차이 없이 전부 같다 (확정).
## 강제 이동과 같은 값이다 — 화면 폭 1152 를 약 1초에 가로지른다.
const PROJECTILE_SPEED := 1120.0

## 평행 다발(활 특수) 화살 사이의 세로 간격.
##
## 18 → 26 (#128). 3발일 때는 총 폭이 36으로 젤리 몸통(72)의 절반도 못 덮어서
## 쿨타임 6초를 쓴 보람이 안 났다. 5발 × 26이면 총 폭 104로 몸통 1.4배를 덮는다.
## 더 벌리면 가운데가 성겨져 서 있는 상대가 화살 사이로 빠진다.
const PARALLEL_SPACING := 26.0

## 낙사 경계 — 화면(1152×648) 밖으로 이만큼 벗어나면 낙사.
## "일반 평맵" 은 좌우 벽이 있어서 낙사가 일어나지 않는다.
## 좌우 벽이 없는 맵(용암 등)에서 쓴다. 물·용암에 닿는 즉사는 맵의 Hazard가 따로 판정한다.
const FALL_MARGIN_BOTTOM := 200.0
const FALL_MARGIN_SIDE := 150.0


## `speed_override`가 0보다 크면 단계 대신 그 속도로 민다 (대포 총 미사일, #121).
##
## 단계를 하나 더 만들지 않고 값으로 받는 이유는, "미사일만 조금 더 민다"가
## 무기 하나에 붙는 성질이지 모든 무기가 골라 쓸 새 단계가 아니기 때문이다.
## 0이면 지금까지처럼 단계 표를 쓴다 — 기존 공격은 아무것도 달라지지 않는다.
static func knockback_velocity(level: int, direction: float, speed_override := 0.0) -> Vector2:
	var speed: float = speed_override
	if speed <= 0.0:
		speed = KNOCKBACK_SPEED[level]
	return Vector2(direction * speed, -speed * KNOCKBACK_LIFT)


## 맵 밖으로 나갔는가.
static func is_out_of_bounds(position: Vector2, screen: Vector2) -> bool:
	return (position.y > screen.y + FALL_MARGIN_BOTTOM
		or position.x < -FALL_MARGIN_SIDE
		or position.x > screen.x + FALL_MARGIN_SIDE)
