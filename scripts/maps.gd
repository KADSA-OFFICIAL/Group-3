class_name Maps
extends RefCounted
## 맵 표. 이름과 씬 경로의 유일한 출처.
##
## **맵을 추가·변경하려면 이 LIST와 씬 파일만 고친다** — 대기실 선택지(`GameState.MAPS`),
## 서버 검증·랜덤 확정(`Lobby`), 전투 화면의 지형 로드가 모두 여기서 나온다.
##
## ## 맵 씬이 지켜야 할 것
##
## - 루트는 `Node2D`.
## - `Spawns` 아래에 `Spawn1`·`Spawn2` (Marker2D). 순서가 1P·2P이고 서로 마주 본다.
## - 지형은 `StaticBody2D` + `CollisionShape2D`.
## - 즉사 구역(물·용암)이 있으면 `Hazard`(Area2D). 닿으면 서버가 죽인다.
## - 배경까지 맵이 그린다. 맵마다 하늘색이 다르다.
##
## 좌우 벽이 없는 맵은 화면 밖으로 나가면 `Combat.is_out_of_bounds()`로 낙사한다.

const DIR := "res://scenes/maps/"

## 실제 맵이 아닌 특수값. 서버가 실제 맵 하나로 확정한다 (resolve 참고).
const RANDOM := "랜덤"

const LIST: Array[Dictionary] = [
	{"name": "평지", "file": "flat.tscn"},
	{"name": "바다", "file": "ocean.tscn"},
	{"name": "용암", "file": "lava.tscn"},
	{"name": "벽돌", "file": "brick.tscn"},
]


static func names() -> Array[String]:
	var out: Array[String] = []
	for map in LIST:
		out.append(map["name"])
	return out


static func get_map(map_name: String) -> Dictionary:
	for map in LIST:
		if map["name"] == map_name:
			return map
	return {}


static func has(map_name: String) -> bool:
	return not get_map(map_name).is_empty()


static func default_name() -> String:
	return LIST[0]["name"]


## "랜덤"을 실제 맵 이름으로 바꾼다.
## **서버에서만 호출한다** — 클라이언트가 각자 뽑으면 양쪽이 다른 맵을 본다.
static func resolve(map_name: String) -> String:
	if map_name == RANDOM:
		return names().pick_random()
	return map_name


## 맵 지형 씬. 이름이 목록에 없거나 파일이 없으면 첫 맵으로 대신한다 —
## 맵을 못 불러와서 허공에서 시작하는 것보다 낫다.
static func scene(map_name: String) -> PackedScene:
	var path := DIR + get_map(map_name).get("file", "")
	if not ResourceLoader.exists(path):
		path = DIR + LIST[0]["file"]
	if not ResourceLoader.exists(path):
		return null
	return load(path)
