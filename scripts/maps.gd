class_name Maps
extends RefCounted
## 맵 표. 이름과 씬 경로의 유일한 출처.
##
## **맵을 추가·변경하려면 이 LIST와 씬 파일만 고친다** — 라운드마다 도는 뽑기와
## 전투 화면의 지형 로드가 모두 여기서 나온다.
##
## ## 맵은 라운드마다 새로 뽑는다
##
## 고르는 자리가 없다 (요청). 대기실에서 사람마다 하나씩 골라 시작할 때 둘 중 하나를
## 뽑던 것을 없앴고, 지금은 라운드가 열릴 때 서버가 `resolve(RANDOM)` 으로 직접 뽑아
## 모두에게 보낸다 (`main.gd` 의 `_start_round` → `_receive_round_map`). 무기(#205)가
## 간 길과 같다 — 판마다 정해지는 것은 판이 열릴 때 정한다.
##
## 그래서 **이 표에 맵을 하나 넣으면 그 순간부터 뽑기에 들어간다**. 선택 UI 를 손댈
## 일도, 이름을 다른 목록에 옮겨 적을 일도 없다.
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
## ## 뚫고 올라가는 발판 (one-way)
##
## 오두막의 나무 판자들은 `CollisionShape2D` 에 `one_way_collision = true` 를 준다 —
## **아래에서 뛰어 올라가면 통과하고, 위에서는 밟고 선다.** 판자가 촘촘한 맵에서
## 이것이 없으면 바로 위 판자의 밑면에 머리를 박아, 옆으로 돌아가야만 올라갈 수 있는
## 자리가 생긴다. 지붕처럼 **맨 위**에 있는 것에는 주지 않는다 — 위에 아무것도 없어서
## 머리를 박을 일이 없고, 비스듬한 면은 one-way 의 방향 기준이 모호하다.
##
## **투사체는 이 규칙을 타지 않는다** (`projectile.gd` 가 `Area2D` 라서다) — 겹침 판정은
## one-way 를 보지 않는다. 아래에서 던져 올린 폭탄은 판자 밑면에서 멎는다. 젤리와
## 다르게 움직이지만, 판자가 통짜였던 때와 **같은** 움직임이라 달라진 것은 없다.
##
## ## 비스듬한 면
##
## 오두막 지붕은 `ConvexPolygonShape2D` 다. 기울기가 30도라 기본 `floor_max_angle`(45도)
## 안에 들어와 걸어서 오르내릴 수 있다. 이보다 가파르면 미끄러지는 벽이 된다.
##
## 좌우 벽이 없는 맵은 화면 밖으로 나가면 `Combat.is_out_of_bounds()`로 낙사한다.

const DIR := "res://scenes/maps/"

## 실제 맵이 아닌 특수값. 서버가 실제 맵 하나로 확정한다 (resolve 참고).
const RANDOM := "랜덤"

const LIST: Array[Dictionary] = [
	{"name": "바다", "file": "ocean.tscn"},
	{"name": "화산", "file": "volcano.tscn"},
	{"name": "협곡", "file": "canyon.tscn"},
	{"name": "오두막", "file": "cottage.tscn"},
	{"name": "투기장", "file": "arena.tscn"},
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
