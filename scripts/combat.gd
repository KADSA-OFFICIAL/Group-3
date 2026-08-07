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
const MELEE_HIT_INTERVAL := 0.6

## 라운드 시작 후 이 시간 동안은 서로 피해를 주고받지 않는다.
const ROUND_START_GRACE := 2.0

## 3점 선취 승리 (계획서).
const POINTS_TO_WIN := 3

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

## 활 특수의 평행 3발 사이 간격. 젤리 몸통 높이(56)를 셋으로 나눈 값이라
## 서 있는 상대에게는 한두 발만 맞는다.
const PARALLEL_SPACING := 18.0

## 낙사 경계 — 화면(1152×648) 밖으로 이만큼 벗어나면 낙사.
## "일반 평맵" 은 좌우 벽이 있어서 낙사가 일어나지 않는다.
## 낙사 공중다리·위 속 같은 맵에서 쓴다.
const FALL_MARGIN_BOTTOM := 200.0
const FALL_MARGIN_SIDE := 150.0


static func knockback_velocity(level: int, direction: float) -> Vector2:
	var speed: float = KNOCKBACK_SPEED[level]
	return Vector2(direction * speed, -speed * KNOCKBACK_LIFT)


## 맵 밖으로 나갔는가.
static func is_out_of_bounds(position: Vector2, screen: Vector2) -> bool:
	return (position.y > screen.y + FALL_MARGIN_BOTTOM
		or position.x < -FALL_MARGIN_SIDE
		or position.x > screen.x + FALL_MARGIN_SIDE)
