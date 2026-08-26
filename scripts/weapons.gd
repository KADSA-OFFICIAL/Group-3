class_name Weapons
extends RefCounted
## 무기 표. "무기 리스트(정리본).docx" 의 설명 + docs/무기_수치_초안.md 에서 확정한 수치.
##
## 문서에 적힌 무기는 17종이며, 기존 코드에 있던 "의자"와 "우산"은 이 목록에 없다.
##
## 필드
##   desc            **라운드 무기 선택 카드**에 적히는 설명 (#205). 출처는 "무기 증강 설명 리스트"
##                   문서이고 문구를 그대로 옮겼다 — 아래 basic·special 은 개발용 요약이라
##                   플레이어에게 보여줄 글이 아니다. 줄바꿈은 카드에서 그대로 나온다
##   basic_damage    기본 공격 데미지. 0 이면 기본 공격 없음 (문서에 "X" — 폭탄·샷건)
##   basic_interval  기본 공격 간격(초). 0 이면 접촉 판정(피격 무적 시간에만 걸림)
##   basic_kind      "melee" 근접 / "melee_dot" 근접 지속 / "ranged" 원거리
##   special_damage  특수 공격 데미지. 0 이면 데미지 없는 능력 부여형
##   special_cooldown 특수 공격 쿨타임(초)
##   knockback       넉백 단계 — Combat.Knockback
##   special_range   이 거리 안에 상대가 있을 때만 특수를 쓸 수 있다. 없으면 거리 제한 없음
##   special_windup  특수를 누르고 나서 **판정이 들어가기까지** 무기를 들어 올리는 시간(초).
##                   이 값이 있는 무기는 누른 프레임에 때리지 않는다 (검, #247)
##   special_swing   들어 올린 무기를 내려베는 시간(초). 이 구간이 **끝나는 순간**에
##                   데미지가 들어간다. 위의 special_windup 과 짝으로만 쓴다.
##                   그림이 도는 것은 Player.server_start_swing() 이 맡는다
##   art_faces_left  원화가 **왼쪽**을 보고 그려져 있다. 기본은 오른쪽 보기다 (art_faces_left 참고)
##   reach_multiplier 이 무기를 들면 **상시로** 붙는 사거리 배율. 없으면 1.0.
##                   **막기 판정(is_blocked)이 사거리 비교라, 1.0을 넘기면 그 무기만
##                   상대 근접 공격을 전부 막는다.** 지금 쓰는 무기가 없는 것은 그래서다 —
##                   사거리 우위는 아래 special_reach_multiplier로 특수 동안만 준다
##   special_reach_multiplier 특수를 쓴 동안 걸리는 사거리 배율 (장대). 지속은 special_duration.
##                   상시가 아니므로 막기 우위도 그 시간에만 생긴다
##   empowered_file  서버가 **미리 뽑아 둔** 강화를 들고 있을 때의 그림 (폭탄·표창).
##                   계기는 뽑기(`empowered_chance`)다 — main.gd의 `_roll_empowered()`
##   ready_file      특수 **쿨타임이 끝나** 쓸 수 있을 때의 그림 (양날 도끼).
##                   계기는 `special_ready`다. 위의 empowered_file 과 하나만 쓴다
##   smoke_puffs     위 두 그림 중 하나가 떠 있는 동안 무기에서 피어오르는 연기 덩어리 수.
##                   없거나 0이면 연기가 없다 (Player._update_weapon_smoke 참고)
##   art_held_forward 원화를 눕혀 **바라보는 쪽으로 뻗어** 든다 (장대). 기본은 세워
##                   드는 것이다. 사거리 판정이 가로 방향인 무기에만 쓴다 —
##                   여백 보정이 position 대신 offset으로 간다 (_place_forward_weapon 참고)
##   art_grows_with_reach 사거리 버프가 걸린 동안 손에 든 그림의 **길이**를 그 배율만큼
##                   늘인다 (장대 특수). 굵기와 판정은 안 변한다 — 판정은 이미
##                   current_reach()가 같은 배율로 늘리고 있다 (Player._art_stretch 참고)
##   art_grows_with_size 크기 버프가 걸린 동안 손에 든 그림을 **가로세로 함께** 그 배율만큼
##                   키운다 (방패 특수). 위의 art_grows_with_reach 와 달리 한쪽만 늘리지
##                   않는다 — 특수가 "크기 증가"라서 통째로 커지는 것이 맞는 그림이다.
##                   그림이 없는 무기는 임시 막대의 두께가 이 버프를 보여 주고 있었으므로,
##                   그림을 붙이면서 이 줄을 안 적으면 특수가 화면에서 사라진다
##                   (Player._art_growth 참고)
##   size_buff_guards 크기 버프가 걸린 동안 **날아오는 탄을 막고, 그 대신 기본 근접
##                   공격이 안 나간다** (방패를 들어 올린 자세). 근접 막기는 따로
##                   적을 필요가 없다 — 크기 버프가 current_reach()를 같이 늘려서
##                   is_blocked()의 사거리 비교가 이미 참이 된다
##                   (Player.is_guarding 참고)
##   weapon_art_scale 손에 든 그림을 이 배율로 줄인다. 없으면 1.0(지금까지의 크기).
##                   세로 WEAPON_HEIGHT 규칙이 검처럼 가늘고 긴 무기 기준이라,
##                   글러브처럼 뭉툭한 원화만 여기서 더 줄인다 (art_scale 참고)
##   projectile_scale 이 무기가 쏘는 탄의 크기 배율. 없으면 1.0(기본 크기).
##                   그림과 판정이 함께 커진다 — main.gd의 _server_fire()가 읽는다
##   projectile_art_scale 이 무기가 쏘는 탄의 **그림만** 키우는 배율. 없으면 1.0.
##                   판정(충돌 상자·반경·데미지)은 하나도 안 변한다 — 눈에 잘 띄게
##                   하려는 것뿐일 때 쓴다. 범위를 키우려면 projectile_scale 쪽이다
##   projectile_file  이 무기가 쏘는 탄의 그림 파일. 없으면 지금까지의 노란 막대다.
##                   _server_fire()가 무기 표에서 읽으므로 **기본·연사 어디서 쏘든**
##                   같은 탄이 나간다 (소총의 총알). 한 무기가 탄 그림을 둘 쓰는 경우
##                   (일반/강화 폭탄·빨간 표창)에는 쏘는 쪽이 art_file 로 직접 넘기고,
##                   그때는 그쪽이 이긴다 — 여기서 덮으면 고른 것이 지워진다
##   special_missile  특수로 나가는 탄을 불꽃 꼬리 미사일로 그린다. 기본 공격 탄은 그대로다
##   special_knockback_speed 미사일에 맞았을 때의 넉백 속도(px/s).
##                   없으면 knockback 단계 표를 쓴다 — 기존 무기는 달라지지 않는다
##   basic_arc_angle  기본 공격을 바라보는 쪽 **위로** 이 각도(도)만큼 띄운다.
##                   중력이 함께 켜져 포물선이 된다. 없으면 지금까지처럼 수평
##   projectile_arrow 이 무기가 쏘는 탄을 결정질 화살로 그린다 (기본·특수 모두)
##   preview_file    **대기실 선택창**에만 쓰는 그림. 없으면 `file` 을 양쪽에 쓴다.
##                   손에 든 모습과 무기 자체의 모습이 다른 무기에만 적는다 —
##                   너클은 선택창에 금속 너클, 손에는 뻗은 주먹이 나온다 (preview_texture 참고)

## 무기 그림 폴더. `file` 필드가 있는 무기만 전투 화면에 그림이 나오고,
## 없는 무기는 지금까지처럼 임시 막대로 그려진다.
const ART_DIR := "res://assets/weapons/"

const LIST: Array[Dictionary] = [
	{
		"name": "검",
		"desc": "크고 강력한 검입니다.\n스킬 사용 시, ‘데마시아’를 시전합니다.",
		"file": "sword.png",
		"basic": "닿으면 일정 데미지",
		"special": "일정 체력 비례 데미지 + 이펙트",
		"basic_damage": 10.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 0.0, "special_cooldown": 6.0, "knockback": 1,
		# 상대의 "현재 체력" 에 비례한다 (확정).
		"special_hp_ratio": 0.15,
		# 이 거리 안에 상대가 있을 때만 쓸 수 있다 — 밖이면 발동도 쿨타임도 없다.
		"special_range": 150.0,
		# 검을 머리 위로 들어 올렸다 내려벤다 (#247). 누른 프레임에 때리지 않고
		# **다 내려온 순간**에 데미지가 들어간다 — 그때까지가 이 둘의 합(0.38초)이다.
		# 들어 올리는 쪽을 길게, 내려베는 쪽을 짧게 둔 것은 "멈칫하고 내려친다"가
		# 보여야 해서다. 둘을 합쳐 0.5초를 넘기면 누른 것이 씹힌 것처럼 읽힌다.
		"special_windup": 0.26, "special_swing": 0.12,
	},
	{
		"name": "단검",
		"desc": "바닥에 드랍된 단검을 주으면 적에게 날라가 공격합니다.\n스킬 사용 시, 드랍된 단검을 다시 줍고 던집니다.",
		"file": "dagger.png",
		"basic": "드랍된 단검을 주우면 자동으로 상대 피격",
		"special": "자동 재수집 (피격 가능)",
		"basic_damage": 15.0, "basic_interval": 0.0, "basic_kind": "ranged",
		"special_damage": 0.0, "special_cooldown": 5.0, "knockback": 0,
		# 주우면 자동으로 상대를 향해 날아간다 — 조준 불필요 (확정).
		"homing": true,
		# 맞으면 그 자리에 빨간 알갱이가 튄다 (#250). 작은 그림이 지나가고 체력만
		# 줄던 무기라, 맞은 자리가 화면에 남게 한다.
		"hit_sparks": true,
	},
	{
		"name": "광선검",
		"desc": "적에게 지속 데미지를 입힙니다.\n스킬 사용 시, 일정 시간동안 적의 무기를 관통합니다.",
		"file": "laser_sword.png",
		"basic": "닿으면 일정 지속 데미지",
		"special": "일정 시간 관통 능력 부여",
		# 특수가 능력 부여라 기본 지속 데미지만으로 싸운다 — 12 → 20 (#55).
		# 0.2초마다 한 틱씩 촘촘하게 넣는다 (#103) — 초당은 이 값의 5배다.
		# 4 → 4.5 (#103 후속) → **5.0** (#222). 초당 20 → 22.5 → **25**.
		# 특수(`special_damage` 0)가 관통 부여뿐이라 이 무기는 기본 하나로만 싸우고,
		# 지속 데미지 무기 중 유일하게 넉백도 없어서(전기톱은 특수에 20 + 출혈이 붙는다)
		# 붙어 있는 값을 받는다.
		#
		# **이 값으로 기본 공격 dps 단독 1위가 된다** (25, 다음이 양날 도끼 21.7).
		# 특수가 데미지 0인 무기라 그 자리를 받는 것이지만 대역 차이가 커졌으니
		# 지켜볼 값이다 — 되돌릴 때도 0.5씩 움직인다.
		"basic_damage": 5.0, "basic_interval": 0.2, "basic_kind": "melee_dot",
		"special_damage": 0.0, "special_cooldown": 8.0, "knockback": 0,
		"special_duration": 3.0,
		# 날이 지나간 자리에 남는 잔상 수 (#253). 붙어서 비벼야 하는 무기인데 손에 든
		# 그림은 서 있는 것과 뛰어드는 것이 똑같이 보여서, 움직임을 날 쪽에 표시한다.
		# 5개면 달릴 때 40px쯤 되는 꼬리다 — 날(56px)보다 짧아야 잔상으로 읽힌다.
		"trail_ghosts": 5,
	},
	{
		"name": "전기톱",
		"desc": "적에게 지속 데미지를 입힙니다.\n스킬 사용 시, 돌진하고 적에게 ‘출혈’ 효과를 부여합니다.",
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
		"desc": "약해보이지만 강력한 망치입니다.\n스킬 사용 시, 공격마다 적에게 ‘기절’ 효과를 부여합니다.",
		"file": "hammer.png",
		"basic": "닿으면 일정 데미지",
		"special": "닿으면 일정 시간 피격 시 기절 효과 부여",
		# **"닿으면" 근접 무기 중 유일하게 자기 간격을 적는다.** 나머지 여덟 종은 0.0 으로
		# 두어 `Combat.MELEE_HIT_INTERVAL`(0.6초) 바닥을 쓰는데, 망치는 타당 데미지가 가장
		# 높은(14) 무기라 같은 박자를 쓰면 초당 23.3 으로 근접 1위가 된다 —
		# 큰 것이 느리게 들어와야 하는 무기에서 세기와 빠르기를 둘 다 가진 셈이었다.
		# 0.9초면 초당 15.6 이다. 타당 14는 그대로 두었다: 줄여야 할 것은 세기가
		# 아니라 그 세기가 들어오는 빠르기다.
		#
		# 넉백은 지금까지와 똑같이 매 타 들어간다 — 넉백 문틈은 0.6초 고정이고
		# 0.9초 간격이면 데미지가 들어갈 때 그쪽은 늘 열려 있다 (_try_melee_basic 참고).
		"basic_damage": 14.0, "basic_interval": 0.9, "basic_kind": "melee",
		"special_damage": 16.0, "special_cooldown": 8.0, "knockback": 2,
		"stun_duration": 1.2,
	},
	{
		"name": "대포 총",
		"desc": "포탄을 발사합니다.\n스킬 사용 시, 거대 미사일을 날립니다.",
		"file": "cannon.png",
		"basic": "일정 시간 일정 데미지",
		"special": "추가 데미지 + 넉백 미사일 발사",
		# 6 → 7 (#55). 원거리 계열 중 가장 낮아서 조금 올렸다.
		#
		# 발사 간격은 0.5 → 0.6초 (#55) → **1.4초** (#217)로 늘렸다. 타당 7은 두 번 다
		# 그대로여서 초당이 14 → 11.7 → **5.0** 이 되었다.
		#
		# 이번(#217)은 초당을 낮추려는 것이 아니라 **발사 속도 자체를 낮추려는** 것이다.
		# 기본 공격은 조작 없이 자동으로 나가고(`_check_basic_attacks`) 원거리는 화면
		# 반대편에서도 닿으므로, 0.6초 간격이면 상대가 붙는 동안 탄이 끊기지 않는다 —
		# 표의 초당이 원거리 최하위였는데도 체감이 가장 답답한 무기였다.
		# "대포"는 무겁고 느리게 한 발씩 나가야 한다.
		#
		# **타당 7은 이번에도 그대로 둔다.** 줄여야 할 것은 한 발의 무게가 아니라
		# 쏟아지는 양이다. 특수가 미사일 25 + 최고 단계보다 센 넉백(850)이라
		# 기본이 앞줄에 있을 무기도 아니다.
		"basic_damage": 7.0, "basic_interval": 1.4, "basic_kind": "ranged",
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
		"desc": "스킬 사용 시, 폭탄을 던집니다.\n일정 확률로 강화 폭탄이 등장합니다.",
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
		"desc": "화살을 날립니다.\n스킬 사용시, 적을 화살로 폭격합니다.",
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
		"desc": "강력한 유물 삼지창입니다.\n스킬 사용시, 적에게 삼지창을 던져 번개를 내리칩니다.",
		"file": "trident.png",
		"basic": "닿으면 일정 데미지",
		"special": "던지고 피격 시 일정 데미지 + 기절 효과 부여, 자동 회수",
		"basic_damage": 12.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 18.0, "special_cooldown": 7.0, "knockback": 1,
		"stun_duration": 0.8,
		# 맞으면 위에서 자홍색 번개가 내려친다 (`scenes/lightning_strike.tscn`).
		# 데미지 18에 기절 0.8초인데 화면에는 삼지창이 사라지는 것뿐이어서,
		# 무엇에 맞아 굳었는지 알려 줄 것이 없었다. 판정과는 무관하다.
		"hit_lightning": true,
		# 던진 삼지창 그림만 40px → 80px (#155). 원화가 1:3.96으로 가늘고 길어서
		# 기본 크기에서는 자루가 선 한 줄이 되고 갈래 셋이 뭉갠다. 젤리 몸통(72px)과
		# 비슷한 길이가 되어 무엇이 날아오는지 읽힌다. 판정은 하나도 안 바뀐다.
		"projectile_art_scale": 2.0,
	},
	{
		"name": "글러브",
		"desc": "UFC 글러브입니다.\n스킬 사용 시, 단거리 난타를 시전합니다.",
		"file": "glove.png",
		# 뭉툭한 원화(1.18:1)라 세로 56px 규칙 그대로면 몸통만 해진다 (#158).
		# 0.6이면 40 x 34px — 젤리 몸통(72px)의 절반쯤이라 손에 낀 것으로 보인다.
		"weapon_art_scale": 0.6,
		"basic": "닿으면 일정 데미지",
		"special": "단거리 주먹 발사 + 넉백 효과 부여",
		"basic_damage": 9.0, "basic_interval": 0.0, "basic_kind": "melee",
		# 특수는 6연발이라 발당을 낮게 잡는다 — 14 → 5 (#164). 투사체는 개별 무적이라
		# 발마다 다 들어가서, 14를 두면 특수 하나가 84가 된다(소총이 발당 1.5인 것과 같은 이유).
		# 첫 발이 강하게 밀어내므로 실제로는 2~4발만 맞는 경우가 많다(10~20).
		"special_damage": 5.0, "special_cooldown": 4.0, "knockback": 2,
		# 0.15초 간격 6발. `knockback`(강)은 **첫 발에만** 들어가고 나머지는 약이다 —
		# 매 발 세게 밀면 0.75초 동안 상대 조작이 잠긴다(#103에서 고친 것과 같은 문제).
		"burst_interval": 0.15, "burst_shots": 6,
		# 1120 → 700px/s (#164). 사거리 300px를 0.27초가 아니라 0.43초에 지난다 —
		# 로켓 펀치인데 눈으로 따라갈 틈이 없었다.
		"projectile_speed": 700.0,
		# 특수는 "단거리 주먹 발사" — 글러브가 손에서 날아간다 (#161).
		# 날아가는 것은 뒤에 분사가 붙은 그림이고, 앞이 오른쪽이라 회전 기준이 다르다.
		"projectile_file": "glove_rocket.png",
		"projectile_points_right": true,
		# 기획서가 "단거리"라고 못박았고 쿨타임 4초(강한 넉백 중 가장 짧음)의 근거가
		# "사거리 짧은 대신"이다. 화면 끝까지 보내면 그 근거가 무너지므로 여기서 끊는다.
		# 젤리 몸통(72px)의 네 배쯤이고, 옛 근접 판정(108px)보다는 확실히 길다.
		"special_distance": 300.0,
	},
	{
		"name": "표창",
		"desc": "스킬 사용 시, 표창을 던집니다.\n일정 확률로 강화 표창이 등장합니다.",
		"file": "shuriken.png",
		# 사방으로 뻗은 별 모양이라 원화가 1:1이다. 세로 56px 규칙 그대로면
		# 몸통만 해져 젤리를 덮는다 (#158과 같은 문제) — 글러브와 같은 0.6을 쓴다.
		"weapon_art_scale": 0.6,
		"basic": "닿으면 일정 데미지",
		"special": "표창 던지기 (중력 영향) (일정 확률로 빨간 표창 등장, 피격 시 1P·2P 위치 변경)",
		"basic_damage": 8.0, "basic_interval": 0.0, "basic_kind": "melee",
		# 쿨타임 3 → **2.5** (#222). 던지기 간격이 짧아지는 만큼 아래 빨간 표창(35%)이
		# 나오는 빈도도 함께 올라간다 — 뽑기는 던진 직후에 다시 돌기 때문이다.
		"special_damage": 14.0, "special_cooldown": 2.5, "knockback": 0,
		# 빨간 표창은 폭탄의 강화와 **같은 틀**을 쓴다 (#134) — 서버가 미리 뽑아
		# 손에 들려 보여 주고, 던진 직후 다시 뽑는다. 그래서 필드 이름도 `empowered_*`다.
		# 다만 폭탄이 데미지를 올리는 것과 달리 이쪽은 데미지를 **0으로 내리고**
		# 1P·2P 위치를 바꾼다 — 강한 것이 아니라 판을 뒤집는 것이다.
		# 기획서의 15% → 35%로 올렸다(요청). 쿨타임 3초에 15%면 라운드 내내 한 번도
		# 안 나오기 쉬워서, 있는지 없는지 모르는 기능이 된다. 35%면 던지기 3번에
		# 한 번쯤이다. **아직 플레이로 확인한 값은 아니다** — 세게 느껴지면 이 숫자만 줄인다.
		"empowered_chance": 0.35, "empowered_damage": 0.0, "empowered_knockback": 0,
		# 그림이 따로다 — 맞아도 데미지가 없고 위치가 바뀌는 것이라
		# 겉모습이 같으면 피할지 말지를 정할 근거가 화면에 없다 (강화 폭탄과 같은 이유, #131).
		"empowered_file": "shuriken_red.png",
		# 맞은 쪽과 던진 쪽의 위치를 맞바꾼다. 이 무기에만 있다.
		"empowered_swap": true,
		# 손에 들고 있는 동안 피어오르는 연기 덩어리 수. 손에 든 표창은 34px밖에 안 되므로
		# 색만 바뀌는 것보다 움직이는 것이 하나 붙는 편이 눈에 들어온다.
		# 색은 `Player.SPECIAL_SMOKE_COLOR`다 — 관통 빛(PIERCE_COLOR)과 같은 자리다.
		"smoke_puffs": 5,
	},
	{
		"name": "너클",
		"desc": "데미지를 받으면 게이지가 찹니다. (40 데미지 = 100%)\n스킬 사용 시, 게이지를 모두 써서 부채꼴 ‘강펀치’를 날립니다.",
		# 손에 든 모습(앞으로 뻗은 주먹)과 무기 자체의 모습(금속 너클)이 다르다 (#173).
		# 주먹 그림을 선택창에 쓰면 무엇을 고르는 것인지 알 수 없고, 너클 그림을
		# 젤리 손에 붙이면 쥔 것처럼 보이지 않는다 — 그림이 갈라지는 첫 무기다.
		"file": "knuckle_worn.png",
		"preview_file": "knuckle.png",
		# 착용 원화가 뭉툭하다(내용 영역 약 1.06:1). 세로 56px 규칙 그대로면
		# 60 x 56px 로 몸통(72px)만 해진다 — 글러브(#158)와 같은 경우다.
		# 0.6 이면 36 x 34px 로 글러브(40 x 34px)와 같은 눈높이가 된다.
		"weapon_art_scale": 0.6,
		"basic": "닿으면 일정 데미지",
		"special": "게이지 비례 부채꼴 강펀치 + 넉백 (받은 데미지로 충전, 75%부터 오라)",
		"basic_damage": 9.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 0.0, "special_cooldown": 5.0, "knockback": 2,
		# 게이지는 **받은 데미지에 비례해** 찬다 (#225). 전에는 맞은 **횟수**였다
		# (`gauge_per_hit` 10 — 열 대면 꽉 참). 그러면 약한 공격 열 대와 센 공격 열 대가
		# 같아서, 무기 설명("데미지를 받으면 충전")과도 어긋났다.
		#
		#   `gauge_fill_damage` 만큼 받으면 `gauge_max` 가 된다 → 40 데미지에 100%.
		#
		# 출혈처럼 무적을 무시하는 지속 데미지도 같이 센다 (`Player._gauge_after`).
		"gauge_max": 100.0, "gauge_fill_damage": 40.0,
		# 강펀치 **한가운데** 데미지. 게이지 0%에서 10, 100%에서 40이다 (요청: 최대 40).
		"gauge_min_damage": 10.0, "gauge_max_damage": 40.0,
		# 강펀치는 한 점이 아니라 **부채꼴**이다 (#225). 근접(약 86px)보다 넓고
		# 샷건(220px)보다 짧게 잡아 "단거리 강펀치"를 지킨다.
		#
		# 150 → **180px** (#244). 예고가 0.5초가 되면서(#238) 그 사이에 걸을 수 있는
		# 거리(320px/s × 0.5 = 160px)가 사거리를 넘어섰다 — 부채 어디에 있어도 그냥 걸어서
		# 빠져나갈 수 있었다. 180px이면 160px을 품으므로 **걷는 것만으로는 못 빠져나간다**
		# (점프하거나 부채 각도 밖으로 빠져야 한다). 근접의 두 배가 넘고 샷건보다는 짧다.
		"punch_cone_range": 180.0,
		# 부채꼴 **전체** 각도(도). 절반씩 위아래로 벌어진다.
		"punch_cone_angle": 80.0,
		# 부채 **가장자리**는 가운데의 이만큼만 들어간다. 샷건이 거리로 줄어드는 것과 달리
		# 이쪽은 **각도**로 줄어든다 — 코앞에서 내지르는 것이라 거리보다 조준이 값이다.
		"punch_edge_ratio": 0.45,
		# 이 비율을 넘으면 젤리에 오라가 돌고 강펀치 연출이 다른 디자인으로 나간다.
		"charged_ratio": 0.75,
		# **강펀치는 즉발이 아니다** (#231). 누르면 먼저 맞을 범위를 보여주고, 이만큼 뒤에
		# 주먹이 들어간다.
		#
		# 0.2 (#231) → 0.3 (#235) → **0.5초** (#238).
		#
		# **0.5초 × 320px/s = 160px** 을 걸을 수 있다. 사거리를 150 → 180px 로 올려(#244)
		# 그 160px을 품게 했지만, 0.5초는 여전히 길어서 이 무기의 특수는 "조준해서 맞히는
		# 기술"보다 **못 움직이는 상대에게 넣는 기술**에 가깝다:
		# 기절(망치), 넉백으로 밀리는 중, 벽에 몰린 상대, 강제 이동 중, 예고를 못 본 상대.
		#
		# 사용자가 세 번에 걸쳐 늘려 정한 값이다(0.2는 반응 시간과 겹쳐 "보이지만 못 피하는"
		# 예고였고, 0.3도 짧다고 보았다). 되돌릴 곳은 여기 하나이고 0.35~0.4가 중간 후보다 —
		# 데미지는 건드리지 않는다. 예고 연출도 이 값을 그대로 받아 같이 늘어난다.
		"punch_windup": 0.5,
	},
	{
		"name": "양날 도끼",
		"desc": "칠흑의 양날 도끼입니다.\n스킬 사용 시, ‘처형’합니다.",
		# 원화가 0.74:1(가로:세로)이라 세로 56px 규칙에 그대로 맡긴다 — 42 x 56px다.
		# 글러브·표창처럼 뭉툭하지 않으므로 `weapon_art_scale`은 없다.
		# 큰 날이 오른쪽이라 오른쪽 보기 기준이 맞다 (`art_faces_left` 없음).
		"file": "double_axe.png",
		"basic": "닿으면 일정 데미지",
		"special": "고속 상승 후 고속 낙하 데미지",
		"basic_damage": 13.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 28.0, "special_cooldown": 9.0, "knockback": 2,
		# 정점에 머무는 시간(초). 상승 0.25초와 낙하 사이에 이만큼 멈춘다 —
		# 0이면 정점이 한 프레임이라 어디서 떨어지는지 눈으로 잡을 틈이 없다.
		# 이 동안 데미지는 안 들어간다(`_special_pending`의 `modes`가 "fall"뿐이다).
		"hover_time": 0.2,
		# 쿨타임 9초로 게임에서 가장 길다. "지금 쓸 수 있나"가 곧 위협이라
		# 준비되면 손에 든 그림이 빨간 도끼로 바뀐다 — 표창의 빨간 표창과 달리
		# 뽑기가 아니라 **쿨타임**이 계기다 (`ready_file` 참고).
		"ready_file": "double_axe_red.png",
		# 연기 덩어리 수. 표창(5)보다 많이 낸다 — 데미지 28에 넉백 강이라
		# 표창보다 더 크게 경고해야 한다.
		"smoke_puffs": 9,
		# 공중에 뜬 동안 좌우 조작을 받는다 (#167). 상승 0.25초 + 정점 0.2초 + 낙하로
		# 1초 가까이 조작이 잠기는데 그동안 상대는 걸어서 낙하 지점을 벗어난다 —
		# 쿨타임 9초로 가장 긴 기술이 "쓰면 거의 빗나가는" 것이 되어 있었다.
		# **전기톱 돌진("dash")에는 주지 않는다** — 바라보는 쪽으로 내지르는 기술이라
		# 도중에 꺾이면 다른 기술이 된다.
		"special_air_control": true,
		# 착지 순간 **좌우로 땅이 갈라져 나가며** 그 앞선에 닿는 상대를 때린다.
		# 낙하 중 직격(28)을 놓쳤을 때만 들어가므로 두 번 맞는 일은 없다 —
		# 직격이 성공하면 기회가 사라진다.
		#
		# 데미지는 직격의 절반이다. 머리 위에 정확히 떨어뜨린 것과 근처에 떨어뜨린 것이
		# 같은 값이면 조준할 이유가 없다. 거리는 폭탄 반경(200)보다 좁고 근접 사거리(72)보다
		# 넓으며, 착지 자리에서 **좌우 각각** 이만큼 뻗는다.
		"landing_damage": 14.0, "landing_radius": 160.0,
		# 갈라짐이 뻗어 나가는 속도(px/s). 160px을 0.18초에 지난다 — "빠르게 갈라진다"가
		# 요점이라 앞선이 눈에 보이기는 하지만 걸어서 피할 수는 없는 빠르기다.
		#
		# **연출과 판정이 이 값 하나를 같이 쓴다** — `main.gd`가 `_play_shockwave`에
		# 그대로 넘겨서 화면에 보이는 앞선이 곧 맞는 경계다. 둘이 따로 놀면 이 연출이
		# 거짓말이 된다 (폭탄 반경을 그린 이유와 같다, #140).
		"landing_rupture_speed": 900.0,
	},
	{
		"name": "샷건",
		"desc": "스킬 사용 시, 근거리의 적에게 강력한 데미지를 입힙니다.",
		# 원화가 3.23:1로 가로로 길어서 가로 80px 제한에 먼저 걸린다 — 80 x 25px다
		# (전기톱과 같은 경로). 세로 56px 규칙에는 닿지 않는다.
		"file": "shotgun.png",
		# 원화가 총구 왼쪽·개머리판 오른쪽으로 그려져 있다 — 그대로 붙이면 등 뒤를 쏜다
		# (전기톱과 같은 이유, #109).
		"art_faces_left": true,
		"basic": "",  # 문서에 "X" — 기본 공격 없음
		"special": "부채꼴 산탄 발사 (원거리 아님, +장전 쿨타임)",
		"basic_damage": 0.0, "basic_interval": 0.0, "basic_kind": "",
		# 기본 공격이 없어 특수 하나로 싸운다 — 30 → 34, 쿨타임 4 → 3 (#55) → **2.5** (#222).
		# 데미지는 그대로이므로 초당 환산이 11.3 → 13.6 이 된다.
		"special_damage": 34.0, "special_cooldown": 2.5, "knockback": 1,
		"falloff_min_damage": 14.0,  # 거리에 따라 34 → 14 로 감소
		# **탄을 쏘지 않는다.** 앞으로 퍼지는 부채꼴 안을 한 번 때린다 —
		# 화면을 가로지르는 탄이 아니라 코앞에서 쏟아붓는 산탄이다.
		# 그리는 부채꼴도 이 두 값을 그대로 쓴다 (`scenes/shotgun_blast.tscn`).
		# 사거리는 근접(약 86px)의 2.5배쯤이고, 옛 탄의 감소 기준 400px보다 짧다.
		"special_cone_range": 220.0,
		# 부채꼴 **전체** 각도(도). 절반씩 위아래로 벌어진다.
		"special_cone_angle": 70.0,
	},
	{
		"name": "장대",
		"desc": "기다란 장대입니다.\n스킬 사용 시, 장대가 더 길어지며 근접전에서 우위를 가집니다.",
		# 원화가 0.113:1(가로:세로)로 지금까지 중 가장 가늘고 길다 — 56 x 6px이 된다.
		# 세워 들면 선 한 줄이지만 눕혀 들면 앞으로 뻗은 봉으로 읽힌다 (아래 참고).
		"file": "pole.png",
		# **유일하게 눕혀 드는 무기다.** 사거리 판정이 가로 방향이고, 그림이 없던 동안
		# 이 자리를 채웠던 임시 막대도 몸에서 앞으로 뻗는 가로 막대였다. 세워 들면
		# 늘어나는 방향이 판정 방향과 어긋나서 길어져도 유리해진 것으로 안 보인다.
		"art_held_forward": true,
		# 특수가 "봉 길이 증가"뿐이라 **그림도 함께 길어져야** 무엇이 일어났는지 보인다.
		# 그림이 붙으면서 임시 막대가 사라져 특수가 화면에서 아무 표시도 없어졌던 것을
		# 되살린 것이다. 길이가 1.6배면 굵기는 1.3배만 붇는다 (`ART_THICKEN_SHARE`) —
		# 길이만 늘리면 늘어난 봉이 실처럼 가늘어 보이고, 굵기까지 1.6배로 늘리면
		# 길어진 것이 아니라 무기가 통째로 커진 것으로 보인다.
		"art_grows_with_reach": true,
		"basic": "닿으면 일정 데미지",
		"special": "봉 길이 증가",
		# 특수가 사거리 증가뿐이라 기본 데미지로만 싸운다 — 8 → 10 (#55).
		"basic_damage": 10.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 0.0, "special_cooldown": 10.0, "knockback": 0,
		# **기본 사거리를 남들과 같게 되돌렸다.** 전에는 `reach_multiplier` 1.6이 상시로
		# 걸려 있었는데, 막기 판정이 `is_blocked()`의 "상대 사거리 > 내 사거리"라서
		# 장대만 사거리를 가진 유일한 무기인 이상 **특수를 쓰지 않아도 근접 공격을
		# 전부 막았다** — 마주 서면 상대가 데미지를 하나도 못 넣었다.
		#
		# 조금만 줄이는 것으로는 안 된다: 비교가 부등호 하나라 1.0을 넘는 값은
		# 무엇이든 다른 무기(전부 1.0) 전체를 막는다. 그래서 상시 배율은 없애고
		# 사거리 우위는 **특수를 쓴 5초 동안만** 생기게 했다.
		"special_reach_multiplier": 1.6, "special_duration": 5.0,
	},
	{
		"name": "소총",
		"desc": "우리 동네는 밤마다 울려 총성\n스킬 사용 시, ‘연발’ 사격합니다.",
		# 원화가 1.79:1로 가로로 길어서 가로 80px 제한에 먼저 걸린다 — 80 x 45px다
		# (샷건·전기톱·대포 총과 같은 경로). 세로 56px 규칙에는 닿지 않는다.
		"file": "rifle.png",
		# 원화가 총구 왼쪽·개머리판 오른쪽으로 그려져 있다 — 그대로 붙이면 등 뒤를 쏜다
		# (샷건·전기톱과 같은 이유, #109).
		"art_faces_left": true,
		# 쏘는 탄은 놋쇠 탄피 + 구리 탄두다. **기본·연사 양쪽에 같은 탄이 나간다** —
		# `_server_fire()`가 이 줄을 무기 표에서 읽으므로 쏘는 곳마다 적지 않는다.
		# 총알에만 그림이 붙는 것은 소총이 탄을 쏘는 유일한 총이기 때문이다:
		# 샷건은 부채꼴이고, 대포 총은 미사일, 활은 결정질 화살로 따로 그린다.
		"projectile_file": "bullet.png",
		# 그림 세로를 40px에 맞추는 기본값이면 15 x 40px으로, 젤리(72px) 절반이 넘는 탄이 된다.
		# 0.75면 11 x 30px — 노란 막대(18 x 6px) 자리보다 살짝 크게, 눈에 띌 만큼만 키운
		# 것이다(처음엔 0.6이었다). 연사가 0.1초마다 20발을 뿌리므로 너무 키우면
		# 화면이 탄으로 덮인다. **판정은 하나도 안 바뀐다** (`projectile_scale`과 다른 점이다).
		"projectile_art_scale": 0.75,
		"basic": "일정 시간 일정 데미지",
		"special": "스킬 누르고 있으면 연사",
		# 간격 0.4 → 0.5초 (확정) → **1.2초** (#217). 발당 5는 세 번 다 그대로여서
		# 초당이 12.5 → 10 → **4.2** 가 되었다.
		#
		# 이번(#217)에 크게 늘린 이유는 **빠른 사격이 특수(`연발`)의 자리**이기 때문이다.
		# 기본이 0.5초마다 나가면 특수를 쓰지 않아도 계속 총알이 날아가서, 쿨타임 8초를
		# 써서 얻는 연발이 "원래 하던 것을 조금 더 빨리 하는 것"이 되어 있었다.
		# 이제 기본은 뜸하게 한 발씩이고, 탄을 쏟아붓는 것은 특수만 할 수 있다.
		"basic_damage": 5.0, "basic_interval": 1.2, "basic_kind": "ranged",
		"special_damage": 1.5, "special_cooldown": 8.0, "knockback": 0,
		# 발당 3 → 1.5 로 낮춤 (확정).
		# 연사 지속시간도 3초 → 2초 로 줄였다 (확정) — 개별 무적이 되면서 다 맞으면 너무 셌다.
		"burst_interval": 0.1, "burst_duration": 2.0,
	},
	{
		"name": "방패",
		"desc": "스킬 버튼을 짧게 누를 시, 방패를 던집니다.\n길게 누를 시, 방패 크기를 증가시킵니다.",
		# 원화가 0.815:1(가로:세로)라 46 x 56px이 된다 — 가로 제한(80px)에는 안 걸리고,
		# 몸통(48px)과 거의 같은 폭이다. 방패는 원래 넓게 막는 물건이라 이 폭이 맞다.
		# 폭탄(0.949:1)도 `weapon_art_scale` 없이 그대로 두었으므로 기준도 어긋나지 않는다.
		"file": "shield.png",
		# **특수의 "크기 증가"가 그림에서도 보여야 한다.** 그림이 없던 동안은 임시 막대의
		# **두께**가 `_size_multiplier`였는데(`_update_weapon_shape` 아래쪽), 그림을 붙이면
		# 막대가 사라져서 4초 동안 사거리만 조용히 2배가 되고 화면에는 아무 표시가 없다 —
		# 장대가 똑같이 겪었던 일이다. 방패는 길이가 아니라 통째로 커지므로
		# `art_grows_with_reach`(길이만)가 아니라 이쪽을 쓴다.
		"art_grows_with_size": true,
		# **막는 자세다.** 커져 있는 동안 날아오는 탄과 **샷건 산탄**(#222)을 막고,
		# 그 대신 기본 근접 공격이 안 나간다 — 크게 든 방패로 몸을 가리는 것이라
		# 그 자세로 때릴 수는 없다.
		# 근접 막기는 여기 적을 필요가 없다: 크기 버프가 `current_reach()`를 2배로
		# 늘려서 `is_blocked()`의 "상대 사거리 > 내 사거리"가 이미 참이 된다.
		"size_buff_guards": true,
		"basic": "닿으면 일정 데미지",
		"special": "방패 크기 증가 or 방패 던지기",
		"basic_damage": 7.0, "basic_interval": 0.0, "basic_kind": "melee",
		"special_damage": 16.0, "special_cooldown": 5.0, "knockback": 1,
		# 짧게 누르면 던지기(16), 길게 누르고 있으면 크기 증가 (확정).
		# 가르는 시간은 `Player.LONG_PRESS_TIME`(0.3초)이고 **서버가 잰다** —
		# 클라이언트가 재면 길게/짧게를 속일 수 있다.
		# 던진 방패도 손에 든 것과 같은 `shield.png`로 날아간다 (main.gd 의 "방패" 분기).
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


## 대기실 선택창에 보여줄 무기 그림 (#173). `preview_file` 이 있으면 그쪽을,
## 없으면 손에 드는 그림(`file`)을 그대로 쓴다 — 나머지 16종은 달라지지 않는다.
##
## 파일이 없어 null 이 나오면 `file` 로 되돌아간다. 선택창 그림만 빠졌을 때
## 빈칸으로 남는 것보다 손에 든 그림이라도 보이는 편이 낫다.
static func preview_texture(weapon_name: String) -> Texture2D:
	var file: String = get_weapon(weapon_name).get("preview_file", "")
	var preview := texture_file(file)
	if preview != null:
		return preview
	return texture(weapon_name)


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


## 크기 버프가 "막는 자세"인가 (방패). 참이면 커져 있는 동안 날아오는 탄을 막고
## 기본 근접 공격이 안 나간다 — 판단은 `Player.is_guarding()` 한 곳에서만 한다.
static func size_buff_guards(weapon_name: String) -> bool:
	return bool(get_weapon(weapon_name).get("size_buff_guards", false))


## 라운드마다 제시할 후보를 겹치지 않게 뽑는다 (#205: 모든 무기 중 랜덤 3개).
##
## `pool` 을 섞어서 앞에서 끊으므로 **한 사람의 후보 안에서는 무기가 겹치지 않는다.**
## 두 사람의 후보끼리는 겹칠 수 있다 — 서로 따로 뽑고, 같은 무기를 둘이 들어도 문제가 없다.
static func random_choices(count: int) -> Array[String]:
	var pool := names()
	pool.shuffle()
	return pool.slice(0, count)


## 선택 카드에 적을 설명 (#205). 출처는 "무기 증강 설명 리스트" 문서다.
##
## 개발용 요약인 `basic`·`special` 과 섞지 말 것 — 그쪽은 "닿으면 일정 데미지" 처럼
## 표를 읽는 사람을 위한 글이고, 이쪽은 플레이어가 카드에서 읽는 글이다.
static func description(weapon_name: String) -> String:
	var text: String = get_weapon(weapon_name).get("desc", "")
	return text
