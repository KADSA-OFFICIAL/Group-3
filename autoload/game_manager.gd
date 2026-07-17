extends Node
## 매치 전역 상태: 무기 선택, 점수, 맵 목록.
## 기획서 핵심 루프: 무기 선택 -> 맵 배정(랜덤) -> 전투 -> 승자 1점 -> 3점 선취 승리.

const WIN_SCORE := 3

## 무기 레지스트리. 새 무기는 scripts/weapons/에 Weapon 상속 스크립트를 만들고 여기 등록한다.
const WEAPONS := {
	"sword": {"name": "검", "script": "res://scripts/weapons/sword.gd"},
	"gun": {"name": "총", "script": "res://scripts/weapons/gun.gd"},
	"hammer": {"name": "망치", "script": "res://scripts/weapons/hammer.gd"},
}

## 맵 목록. 새 맵은 scenes/maps/에 SpawnP1/SpawnP2 Marker2D를 포함한 씬을 만들고 여기 등록한다.
const MAPS := [
	"res://scenes/maps/flat_map.tscn",
	"res://scenes/maps/obstacle_map.tscn",
]

var p1_weapon: String = "sword"
var p2_weapon: String = "sword"
var scores := {1: 0, 2: 0}


func reset_match() -> void:
	scores = {1: 0, 2: 0}


func add_point(winner_id: int) -> void:
	scores[winner_id] += 1


func is_match_over() -> bool:
	return scores[1] >= WIN_SCORE or scores[2] >= WIN_SCORE


func match_winner() -> int:
	if scores[1] >= WIN_SCORE:
		return 1
	if scores[2] >= WIN_SCORE:
		return 2
	return 0


func random_map() -> String:
	return MAPS[randi() % MAPS.size()]


func weapon_for(player_id: int) -> String:
	return p1_weapon if player_id == 1 else p2_weapon
