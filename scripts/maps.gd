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
## ## 배경 원화를 쓰는 맵
##
## 화산·협곡·오두막·투기장은 `ColorRect` 대신 `assets/maps/`의 원화 한 장을
## `Background`(Sprite2D)로 깐다. 원화는 1920x1080이고 게임 좌표는 1152x648이라
## **`position = (576, 324)` + `scale = 0.6`**이면 화면에 정확히 들어맞는다 —
## 원화 픽셀에 0.6을 곱한 값이 곧 충돌 상자 좌표다.
## 발판 사이 높이차는 **160px을 넘기지 않는다**(점프 높이 = 560²/(2*980)).
## 넘기면 올라갈 수 없는 발판이나 빠져나올 수 없는 구덩이가 생긴다.
##
## 좌우 벽이 없는 맵은 화면 밖으로 나가면 `Combat.is_out_of_bounds()`로 낙사한다.

const DIR := "res://scenes/maps/"

## 대기실 미리보기가 쓰는 배경 원화 폴더. 전투 화면이 `Background`로 깔는 것과 같은 그림이다.
const ART_DIR := "res://assets/maps/"

## 원화가 없는 맵·`랜덤`·빈 자리에 쓰는 색. 카드 테두리보다 한 톤 밝게 둔다 —
## 테두리와 같은 색이면 그 절반이 있는지조차 안 보이고 가운데 `?` 배지도 묻힌다.
const UNKNOWN_COLOR := Color(0.35, 0.3, 0.41)

## 실제 맵이 아닌 특수값. 서버가 실제 맵 하나로 확정한다 (resolve 참고).
const RANDOM := "랜덤"

const LIST: Array[Dictionary] = [
	{"name": "바다", "file": "ocean.tscn", "color": Color(0.72, 0.82, 0.98)},
	{"name": "화산", "file": "volcano.tscn", "art": "volcano.png"},
	{"name": "협곡", "file": "canyon.tscn", "art": "canyon.png"},
	{"name": "오두막", "file": "cottage.tscn", "art": "cottage.png"},
	{"name": "투기장", "file": "arena.tscn", "art": "arena.png"},
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
## 표에서 꺼낸 값은 Variant라서 **반드시 명시 타입으로 받는다** —
## `var x := DIR + dict.get(...)`처럼 쓰면 타입 추론이 실패해 스크립트가 파싱되지 않는다.
static func scene(map_name: String) -> PackedScene:
	var file: String = get_map(map_name).get("file", "")
	var path: String = DIR + file
	if file.is_empty() or not ResourceLoader.exists(path):
		var fallback: String = LIST[0]["file"]
		path = DIR + fallback
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## 대기실 맵 카드가 배경으로 깔 배경 원화 (#289). 없으면 null이고
## 부르는 쪽이 `art_color()`의 단색으로 대신한다 — 무기 그림이 없을 때와 같은 방식이다.
##
## 표에서 꺼낸 값은 Variant라서 **반드시 명시 타입으로 받는다** (이슈 #66).
static func art_texture(map_name: String) -> Texture2D:
	var art: String = get_map(map_name).get("art", "")
	if art.is_empty():
		return null
	var path: String = ART_DIR + art
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## 원화가 없을 때 그 자리를 채울 색. 맵마다 `color`로 적어 두고,
## 목록에 없는 이름(`랜덤`·빈 자리)이면 "모른다"는 뜻의 카드 바탕색을 준다.
static func art_color(map_name: String) -> Color:
	var color: Variant = get_map(map_name).get("color")
	if color is Color:
		return color
	return UNKNOWN_COLOR
