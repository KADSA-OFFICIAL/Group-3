extends Node
## 화면 간에 공유되는 게임 설정 (오토로드 싱글톤 GameState)
##
## 온라인 전제이므로 "1P/2P 설정"이 아니라
## - local_config : 이 기기의 플레이어가 고른 것
## - configs      : 슬롯(1/2) -> 확정된 설정. 매치 시작 시 서버가 채워준다.
## 로 나뉜다.

const COLORS: Array[Color] = [
	Color(0.25, 0.95, 0.95), # 하늘색
	Color(1.0, 0.9, 0.2),    # 노랑
	Color(1.0, 0.42, 0.55),  # 분홍
	Color(0.4, 0.85, 0.4),   # 초록
	Color(0.7, 0.5, 1.0),    # 보라
	Color(1.0, 0.6, 0.2),    # 주황
	Color(0.9, 0.25, 0.3),   # 빨강
	Color(0.35, 0.55, 1.0),  # 파랑
	Color(0.15, 0.15, 0.25), # 남색
	Color(0.95, 0.95, 0.95), # 흰색
]

## 무기 이름 목록. 실제 표는 weapons.gd 에 있다 ("무기 리스트(정리본).docx" 기준 17종).
## 맨 앞의 "랜덤" 은 기존 선택 창에서 쓰던 항목이라 그대로 두었다.
var weapon_names: Array[String] = _build_weapon_names()

const HEADS := ["없음", "중절모", "왕관", "헬멧"]

## 계획서의 맵 6종. 아직 "일반 평맵"만 구현되어 있다.
const MAPS := ["랜덤", "일반 평맵", "기물 평맵", "낙사 공중다리", "냉장고", "봉지 속", "위 속"]
const IMPLEMENTED_MAPS := ["일반 평맵"]

const POINTS_TO_WIN := 3

var local_config := {}
var configs := {}          ## slot(int) -> config(Dictionary)
var map_name := "일반 평맵"


func _ready() -> void:
	local_config = default_config(1)


static func _build_weapon_names() -> Array[String]:
	var out: Array[String] = ["랜덤"]
	out.append_array(Weapons.names())
	return out


## 무기는 여기에 없다. 계획서대로 라운드마다 3개 중 1개를 고른다.
func default_config(slot: int) -> Dictionary:
	return {
		"head": "없음",
		"color1": COLORS[0] if slot == 1 else COLORS[1],
		"color2": COLORS[8],
	}


func get_config(slot: int) -> Dictionary:
	return configs.get(slot, default_config(slot))
