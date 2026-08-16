class_name Weapons
extends RefCounted
## 무기 표. "무기 리스트(정리본).docx" 의 설명 + docs/무기_수치_초안.md 에서 확정한 수치.
##
## 문서에 적힌 무기는 17종이며, 기존 코드에 있던 "의자"와 "우산"은 이 목록에 없다.
##
## 필드
##   basic_damage    기본 공격 데미지. 0 이면 기본 공격 없음 (문서에 "X" — 폭탄·샷건)
##   basic_interval  기본 공격 간격(초). 0 이면 접촉 판정(피격 무적 시간에만 걸림)
##   basic_kind      "melee" 근접 / "melee_dot" 근접 지속 / "ranged" 원거리
##   special_damage  특수 공격 데미지. 0 이면 데미지 없는 능력 부여형
##   special_cooldown 특수 공격 쿨타임(초)
##   knockback       넉백 단계 — Combat.Knockback
##   special_range   이 거리 안에 상대가 있을 때만 특수를 쓸 수 있다. 없으면 거리 제한 없음
##   art_faces_left  원화가 **왼쪽**을 보고 그려져 있다. 기본은 오른쪽 보기다 (art_faces_left 참고)
##   weapon_art_scale 손에 든 그림을 이 배율로 줄인다. 없으면 1.0(지금까지의 크기).
##                   세로 WEAPON_HEIGHT 규칙이 검처럼 가늘고 긴 무기 기준이라,
##                   글러브처럼 뭉툭한 원화만 여기서 더 줄인다 (art_scale 참고)
##   projectile_scale 이 무기가 쏘는 탄의 크기 배율. 없으면 1.0(기본 크기).
##                   그림과 판정이 함께 커진다 — main.gd의 _server_fire()가 읽는다
##   projectile_art_scale 이 무기가 쏘는 탄의 **그림만** 키우는 배율. 없으면 1.0.
##                   판정(충돌 상자·반경·데미지)은 하나도 안 변한다 — 눈에 잘 띄게
##                   하려는 것뿐일 때 쓴다. 범위를 키우려면 projectile_scale 쪽이다
##   special_missile  특수로 나가는 탄을 불꽃 꼬리 미사일로 그린다. 기본 공격 탄은 그대로다
##   special_knockback_speed 미사일에 맞았을 때의 넉백 속도(px/s).
##                   없으면 knockback 단계 표를 쓴다 — 기존 무기는 달라지지 않는다
##   basic_arc_angle  기본 공격을 바라보는 쪽 **위로** 이 각도(도)만큼 띄운다.
##                   중력이 함께 켜져 포물선이 된다. 없으면 지금까지처럼 수평
##   projectile_arrow 이 무기가 쏘는 탄을 결정질 화살로 그린다 (기본·특수 모두)

## 실제 무기가 아닌 특수값. 서버가 실제 무기 하나로 확정한다 (resolve 참고).
const RANDOM := "랜덤"

## 무기 그림 폴더. `file` 필드가 있는 무기만 전투 화면에 그림이 나오고,
## 없는 무기는 지금까지처럼 임시 막대로 그려진다.
const ART_DIR := "res://assets/weapons/"

const LIST: Array[Dictionary] = [
	{
		"name": "검",
		"file": "sword.png",
		"basic": "닿으면 일정 데미지",
		"special": "일정 체력 비례 데미지 + 이펙트",
		"basic_damage": 10.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 0.0, "special_cooldown": 6.0, "knockback": 1,
		# 상대의 "현재 체력" 에 비례한다 (확정).
		"special_hp_ratio": 0.15,
		# 이 거리 안에 상대가 있을 때만 쓸 수 있다 — 밖이면 발동도 쿨타임도 없다.
		"special_range": 150.0,
	},
	{
		"name": "단검",
		"file": "dagger.png",
		"basic": "드랍된 단검을 주우면 자동으로 상대 피격",
		"special": "자동 재수집 (피격 가능)",
		"basic_damage": 15.0, "basic_interval": 0.0, "basic_kind": "ranged",
		"special_damage": 0.0, "special_cooldown": 5.0, "knockback": 0,
		# 주우면 자동으로 상대를 향해 날아간다 — 조준 불필요 (확정).
		"homing": true,
	},
	{
		"name": "광선검",
		"file": "laser_sword.png",
		"basic": "닿으면 일정 지속 데미지",
		"special": "일정 시간 관통 능력 부여",
		# 특수가 능력 부여라 기본 지속 데미지만으로 싸운다 — 12 → 20 (#55).
		# 초당 20은 그대로 두고 0.2초마다 4씩 촘촘하게 넣는다 (#103).
		"basic_damage": 4.0, "basic_interval": 0.2, "basic_kind": "melee_dot",
		"special_damage": 0.0, "special_cooldown": 8.0, "knockback": 0,
		"special_duration": 3.0,
	},
	{
		"name": "전기톱",
		"file": "chainsaw.png",
		# 원화가 톱날 왼쪽·손잡이 오른쪽으로 그려져 있다 — 그대로 붙이면 등 뒤를 벤다 (#109).
		"art_faces_left": true,
		"basic": "닿으면 일정 지속 데미지",
		"special": "관통 돌진 후 일정 시간 출혈",
		# 초당 15는 그대로 두고 0.2초마다 3씩 촘촘하게 넣는다 (#105, 광선검과 같은 방식).
		"basic_damage": 3.0, "basic_interval": 0.2, "basic_kind": "melee_dot",
		"special_damage": 20.0, "special_cooldown": 7.0, "knockback": 1,
		"bleed_damage": 4.0, "bleed_duration": 3.0,
	},
	{
		"name": "망치",
		"file": "hammer.png",
		"basic": "닿으면 일정 데미지",
		"special": "닿으면 일정 시간 피격 시 기절 효과 부여",
		"basic_damage": 14.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 16.0, "special_cooldown": 8.0, "knockback": 2,
		"stun_duration": 1.2,
	},
	{
		"name": "대포 총",
		"file": "cannon.png",
		"basic": "일정 시간 일정 데미지",
		"special": "추가 데미지 + 넉백 미사일 발사",
		# 6 → 7 (#55). 원거리 계열 중 가장 낮아서 조금 올렸다.
		"basic_damage": 7.0, "basic_interval": 0.5, "basic_kind": "ranged",
		"special_damage": 25.0, "special_cooldown": 6.0, "knockback": 2,
		# 전용 투사체 그림이 없어 공용 노란 막대(18×6)로 나가는데, "대포" 치고 탄이
		# 빈약해 보이고 눈에 안 띄었다 — 1.5배로 키운다 (#118).
		"projectile_scale": 1.5,
		# 특수는 "넉백 미사일"이라 기본 공격 탄과 구분되어야 한다 — 불꽃 꼬리를 달고,
		# 최고 단계(STRONG 700)보다 조금 더 민다 (#121).
		"special_missile": true,
		"special_knockback_speed": 850.0,
	},
	{
		"name": "폭탄",
		"file": "bomb.png",
		"basic": "",  # 문서에 "X" — 기본 공격 없음
		"special": "피격하거나 일정 시간이 지나면 터지는 폭탄 투하 (일정 확률로 데미지·넉백 증가 폭탄 등장)",
		"basic_damage": 0.0, "basic_interval": 0.0, "basic_kind": "",
		# 기본 공격이 없어 특수 하나로 싸운다 — 22 → 32, 쿨타임 5 → 3.5 (#55).
		"special_damage": 32.0, "special_cooldown": 3.5, "knockback": 1,
		"empowered_chance": 0.20, "empowered_damage": 48.0, "empowered_knockback": 2,
		# 강화 폭탄은 그림이 따로 있다 — 데미지가 32 → 48인데 겉모습이 같으면
		# 피할지 말지를 정할 근거가 화면에 없다 (#131).
		"empowered_file": "bomb_charged.png",
		# 그림만 40px → 60px. 옆에 지름 400px짜리 반경 원이 붙으면서 기본 크기로는
		# 무엇이 날아오는지 눈에 안 들어왔다 (#149). 판정은 하나도 안 바뀐다.
		"projectile_art_scale": 1.5,
	},
	{
		"name": "활",
		"file": "bow.png",
		# 원화가 활대 왼쪽·시위 오른쪽으로 그려져 있다. 화살은 시위 반대쪽으로 나가므로
		# 이건 왼쪽을 보는 그림이다 — 그대로 붙이면 활대가 자기 쪽을 향한다 (#137).
		# 전기톱과 같은 경우인데 #109 때 활은 빠졌다.
		"art_faces_left": true,
		"basic": "일정 시간 일정 데미지",
		"special": "동시 다중 관통 화살 발사",
		"basic_damage": 10.0, "basic_interval": 0.7, "basic_kind": "ranged",
		"special_damage": 12.0, "special_cooldown": 6.0, "knockback": 0,
		# 3 → 5 (#128). main.gd 가 이 값을 읽어 평행 다발을 만든다 —
		# 전에는 여기 3이 적혀 있어도 발사 쪽이 3발을 하드코딩하고 있어서
		# 이 값을 고쳐도 아무 일도 일어나지 않았다.
		"special_projectiles": 5,
		# 활인데 총알처럼 일직선으로 날아가서 원거리 3종이 같은 감각이었다 —
		# 기본 공격만 15도 위로 띄워 포물선을 준다 (#125).
		# 정점이 발사 높이보다 약 43px 위(젤리 몸통 72px의 반쯤)다.
		# 특수(관통 3발)는 쿨타임 6초짜리라 맞히기 어려워지지 않게 직선으로 둔다.
		"basic_arc_angle": 15.0,
		"projectile_arrow": true,
	},
	{
		"name": "삼지창",
		"file": "trident.png",
		"basic": "닿으면 일정 데미지",
		"special": "던지고 피격 시 일정 데미지 + 기절 효과 부여, 자동 회수",
		"basic_damage": 12.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 18.0, "special_cooldown": 7.0, "knockback": 1,
		"stun_duration": 0.8,
		# 던진 삼지창 그림만 40px → 80px (#155). 원화가 1:3.96으로 가늘고 길어서
		# 기본 크기에서는 자루가 선 한 줄이 되고 갈래 셋이 뭉갠다. 젤리 몸통(72px)과
		# 비슷한 길이가 되어 무엇이 날아오는지 읽힌다. 판정은 하나도 안 바뀐다.
		"projectile_art_scale": 2.0,
	},
	{
		"name": "글러브",
		"file": "glove.png",
		# 뭉툭한 원화(1.18:1)라 세로 56px 규칙 그대로면 몸통만 해진다 (#158).
		# 0.6이면 40 x 34px — 젤리 몸통(72px)의 절반쯤이라 손에 낀 것으로 보인다.
		"weapon_art_scale": 0.6,
		"basic": "닿으면 일정 데미지",
		"special": "단거리 주먹 발사 + 넉백 효과 부여",
		"basic_damage": 9.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 14.0, "special_cooldown": 4.0, "knockback": 2,
	},
	{
		"name": "표창",
		"basic": "닿으면 일정 데미지",
		"special": "표창 던지기 (중력 영향) (일정 확률로 파란 표창 등장, 피격 시 1P·2P 위치 변경)",
		"basic_damage": 8.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 14.0, "special_cooldown": 3.0, "knockback": 0,
		"blue_chance": 0.15,  # 파란 표창: 데미지 없이 1P·2P 위치 교환
	},
	{
		"name": "너클",
		"basic": "닿으면 일정 데미지",
		"special": "게이지 비례 강펀치 데미지 + 넉백 (피격 시 게이지 충전)",
		"basic_damage": 9.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 0.0, "special_cooldown": 5.0, "knockback": 2,
		"gauge_min_damage": 10.0, "gauge_max_damage": 40.0,
		"gauge_per_hit": 10.0, "gauge_max": 100.0,
	},
	{
		"name": "양날 도끼",
		"basic": "닿으면 일정 데미지",
		"special": "고속 상승 후 고속 낙하 데미지",
		"basic_damage": 13.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 28.0, "special_cooldown": 9.0, "knockback": 2,
	},
	{
		"name": "샷건",
		"basic": "",  # 문서에 "X" — 기본 공격 없음
		"special": "샷건 발사 (+장전 쿨타임)",
		"basic_damage": 0.0, "basic_interval": 0.0, "basic_kind": "",
		# 기본 공격이 없어 특수 하나로 싸운다 — 30 → 34, 쿨타임 4 → 3 (#55).
		"special_damage": 34.0, "special_cooldown": 3.0, "knockback": 1,
		"falloff_min_damage": 14.0,  # 거리에 따라 34 → 14 로 감소
	},
	{
		"name": "장대",
		"basic": "닿으면 일정 데미지",
		"special": "봉 길이 증가",
		# 특수가 사거리 증가뿐이라 기본 데미지로만 싸운다 — 8 → 10 (#55).
		"basic_damage": 10.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 0.0, "special_cooldown": 10.0, "knockback": 0,
		"reach_multiplier": 1.6, "special_duration": 5.0,
	},
	{
		"name": "소총",
		"basic": "일정 시간 일정 데미지",
		"special": "스킬 누르고 있으면 연사",
		"basic_damage": 5.0, "basic_interval": 0.4, "basic_kind": "ranged",
		"special_damage": 1.5, "special_cooldown": 8.0, "knockback": 0,
		# 발당 3 → 1.5 로 낮춤 (확정).
		# 연사 지속시간도 3초 → 2초 로 줄였다 (확정) — 개별 무적이 되면서 다 맞으면 너무 셌다.
		"burst_interval": 0.1, "burst_duration": 2.0,
	},
	{
		"name": "방패",
		"basic": "닿으면 일정 데미지",
		"special": "방패 크기 증가 or 방패 던지기",
		"basic_damage": 7.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 16.0, "special_cooldown": 5.0, "knockback": 1,
		# 짧게 누르면 던지기(16), 길게 누르고 있으면 크기 증가 (확정).
		# TODO: 짧게/길게를 가르는 시간이 아직 안 정해졌다.
		"size_multiplier": 2.0, "special_duration": 4.0,
	},
]


static func names() -> Array[String]:
	var out: Array[String] = []
	for weapon: Dictionary in LIST:
		out.append(weapon["name"])
	return out


static func get_weapon(weapon_name: String) -> Dictionary:
	for weapon: Dictionary in LIST:
		if weapon["name"] == weapon_name:
			return weapon
	return {}


## 기본 공격이 없는 무기 (문서에 "X" 로 표기된 폭탄·샷건).
static func has_basic_attack(weapon_name: String) -> bool:
	var weapon := get_weapon(weapon_name)
	return not weapon.is_empty() and weapon["basic_damage"] > 0.0


## "랜덤" 을 실제 무기 이름으로 바꾼다.
## **서버에서만 호출한다** — 클라이언트가 각자 뽑으면 양쪽이 다른 무기를 갖는다.
## 무기 그림. 그림이 없는 무기이거나 파일이 아직 없으면 null을 돌려준다 —
## 부르는 쪽이 임시 막대로 대신 그린다.
static func texture(weapon_name: String) -> Texture2D:
	return texture_file(get_weapon(weapon_name).get("file", ""))


## 파일 이름으로 무기 그림을 찾는다. 무기 하나에 그림이 둘일 때 쓴다 —
## 폭탄은 일반(`bomb.png`)과 강화(`bomb_charged.png`)가 따로 있어서
## 무기 이름만으로는 어느 쪽인지 고를 수 없다 (#131).
static func texture_file(file: String) -> Texture2D:
	if file.is_empty():
		return null
	var path := ART_DIR + file
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## 원화가 왼쪽을 보고 그려졌는가. 그리는 쪽은 오른쪽 보기를 기본으로 가정하므로
## 이 무기는 좌우를 한 번 더 뒤집어야 바라보는 쪽에 날이 온다 (#109).
static func art_faces_left(weapon_name: String) -> bool:
	return bool(get_weapon(weapon_name).get("art_faces_left", false))


## 손에 든 그림을 줄이는 배율 (#158). 없으면 1.0 — 지금까지의 크기 그대로다.
##
## 기본 규칙(세로 `WEAPON_HEIGHT`)은 검처럼 **가늘고 긴** 무기에 맞춰져 있다.
## 글러브처럼 뭉툭한 원화는 세로만 맞추면 몸통만 한 덩어리가 되어 젤리를 덮는다 —
## 가로 제한(`WEAPON_MAX_WIDTH`)도 세로로 긴 것을 못 잡듯이 이쪽도 못 잡는다.
static func art_scale(weapon_name: String) -> float:
	return float(get_weapon(weapon_name).get("weapon_art_scale", 1.0))


static func resolve(weapon_name: String) -> String:
	if weapon_name == RANDOM:
		return names().pick_random()
	return weapon_name


## 라운드마다 제시할 후보를 겹치지 않게 뽑는다 (계획서: 모든 무기 중 랜덤 3개).
static func random_choices(count: int) -> Array[String]:
	var pool := names()
	pool.shuffle()
	return pool.slice(0, count)
