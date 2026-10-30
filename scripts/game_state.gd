extends Node
## 화면 간에 공유되는 게임 설정 (오토로드 싱글톤 GameState)
##
## **한 기기 한 화면에서 둘이 하는 오프라인 대전이다** (#320). 접속도 서버도 자리 배정도
## 없으므로 화면과 화면을 잇는 상태는 이 싱글톤 하나뿐이다 — 선택 창이 캐릭터를 여기에
## 적고 전투 화면이 그것을 읽어 젤리를 세운다. 되돌리지 말 것: 예전에는 `Lobby` 오토로드가
## 서버에서 자리와 선택을 정해 양쪽에 복제했는데, 한 화면에서는 정할 상대도 보낼 곳도 없다.

## 선택 가능한 캐릭터 목록. 선택 UI·검증이 모두 이 배열을 따른다.
##
## 실제 캐릭터 표는 `scripts/characters.gd`에 있고 여기서는 이름만 꺼내 쓴다 —
## **캐릭터를 추가·변경하려면 `Characters.LIST`를 고친다.**
var CHARACTERS: Array[String] = Characters.names()

## **무기 목록은 여기 없다**(#205). 무기는 선택 창이 아니라 라운드가 시작될 때 고르고,
## 그때 제시할 후보는 전투 화면이 `Weapons.random_choices()`로 직접 뽑는다 —
## 화면이 훑을 목록이 필요 없어졌다. 통합 가이드: docs/weapon-system.md

## **맵 목록도 여기 없다** (요청). 무기(#205)와 같은 길을 갔다 — 선택 창에서 고르던 것을
## 없앴고, 지금은 라운드가 열릴 때마다 전투 화면이 직접 뽑는다
## (`main.gd`의 `_pick_round_map()`). 화면이 훑을 목록이 필요 없어졌다.
## 뽑기는 맵 목록을 섞은 가방에서 한 장씩 꺼내므로 **판마다 지형이 반드시 바뀐다** (#310).
## **맵을 추가·변경하려면 `Maps.LIST`를 고친다** — 뽑기가 그 표를 그대로 읽는다.

## 싸우는 자리 수. 한 화면에 젤리 둘이다.
const PLAYER_COUNT := 2

## 플레이어 번호 목록. **1P는 1, 2P는 2다** (#320).
##
## 전투 화면의 표(점수·공격 간격·출혈 …)가 전부 이 번호를 열쇠로 쓴다. 자리(slot)는
## 0부터 세므로 `번호 = 자리 + 1` 이고, 그 변환은 `id_at()`·`slot_of()`가 한다 —
## 두 셈을 코드 여기저기서 직접 하지 말고 이 둘만 쓴다.
const PLAYER_IDS := [1, 2]

## 자리별 선택값. `{"character": String}` 하나뿐이고 선택 창이 고쳐 쓴다.
var configs: Array[Dictionary] = [
	{"character": Characters.id_at(0)},
	{"character": Characters.id_at(1)},
]


## 이 자리(0·1)의 플레이어 번호.
func id_at(slot: int) -> int:
	return slot + 1


## 이 플레이어 번호의 자리(0·1).
func slot_of(player_id: int) -> int:
	return player_id - 1


func config_for(player_id: int) -> Dictionary:
	var slot := slot_of(player_id)
	if slot < 0 or slot >= configs.size():
		return {"character": Characters.id_at(0)}
	return configs[slot]


## 선택 창이 고른 값을 적는다. 목록에 없는 캐릭터는 그 자리의 기본값으로 되돌린다.
func set_config(player_id: int, config: Dictionary) -> void:
	var slot := slot_of(player_id)
	if slot < 0 or slot >= configs.size():
		return
	var fallback := Characters.id_at(slot)
	var character: String = config.get("character", fallback)
	configs[slot] = {"character": character if Characters.has(character) else fallback}


## 이 플레이어의 입력 이름 (`project.godot`의 `[input]`).
##
## **키를 두 벌 두고 이름 앞에 자리를 붙이는 것이 오프라인 2인의 전부다** (#320) —
## 젤리는 자기 번호로 만든 이름만 읽으므로 한 화면에서 둘이 서로 간섭하지 않는다.
## 1P는 `WASD`+왼쪽 `Shift`, 2P는 방향키+`Space`.
func action(player_id: int, name: String) -> String:
	return "p%d_%s" % [player_id, name]


## 이 플레이어의 조작으로 읽을 키 묶음의 번호들 (#361).
##
## 오프라인은 자기 번호 한 벌뿐이다 — 한 키보드를 둘이 나눠 쓰므로 섞이면 안 된다.
## **온라인 클라이언트는 두 벌을 다 읽는다** — 기기 앞에 한 사람뿐이라 `WASD` 든 방향키든
## 손에 익은 쪽으로 조작하면 된다. 2P로 붙었다고 방향키만 써야 할 이유가 없다.
func input_ids(player_id: int) -> Array:
	return PLAYER_IDS if Network.is_client() else [player_id]


## 이 플레이어의 조작으로 `name` 이 눌려 있는가. 읽을 묶음은 `input_ids()` 가 정한다.
func is_pressed(player_id: int, name: String) -> bool:
	for id: int in input_ids(player_id):
		if Input.is_action_pressed(action(id, name)):
			return true
	return false


func is_just_pressed(player_id: int, name: String) -> bool:
	for id: int in input_ids(player_id):
		if Input.is_action_just_pressed(action(id, name)):
			return true
	return false


## 좌우 입력 (-1 ~ 1). 두 벌을 읽을 때는 더해서 자른다 — 양손이 서로 반대로 밀면 멈춘다.
func axis(player_id: int) -> float:
	var total := 0.0
	for id: int in input_ids(player_id):
		total += Input.get_axis(action(id, "left"), action(id, "right"))
	return clampf(total, -1.0, 1.0)


## 이 입력 이벤트가 이 플레이어의 `name` 누름인가 (무기 카드처럼 이벤트로 받는 곳이 쓴다).
func event_pressed(event: InputEvent, player_id: int, name: String) -> bool:
	for id: int in input_ids(player_id):
		if event.is_action_pressed(action(id, name)):
			return true
	return false
