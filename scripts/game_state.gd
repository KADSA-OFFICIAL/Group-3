extends Node
## 화면 간에 공유되는 게임 설정 (오토로드 싱글톤 GameState)

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

const WEAPONS := ["랜덤", "광선검", "망치", "총", "활", "의자", "우산", "방패"]
const HEADS := ["없음", "중절모", "왕관", "헬멧"]
const MAPS := ["랜덤", "평지", "냉장고", "봉지 속", "위 속"]

var p1_config := {"weapon": "랜덤", "head": "없음", "color1": COLORS[0], "color2": COLORS[8]}
var p2_config := {"weapon": "랜덤", "head": "없음", "color1": COLORS[1], "color2": COLORS[8]}
var map_name := "평지"


func get_config(prefix: String) -> Dictionary:
	return p1_config if prefix == "p1" else p2_config
