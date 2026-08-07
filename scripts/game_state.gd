extends Node
## 화면 간에 공유되는 게임 설정 (오토로드 싱글톤 GameState)

## 선택 가능한 캐릭터 목록. 선택 UI·검증·전송이 모두 이 배열을 따른다.
##
## 실제 캐릭터 표는 `scripts/characters.gd`에 있고 여기서는 이름만 꺼내 쓴다 —
## **캐릭터를 추가·변경하려면 `Characters.LIST`를 고친다.**
var CHARACTERS: Array[String] = Characters.names()

## 선택 가능한 무기 목록. 선택 UI·검증·전송이 모두 이 배열을 따른다.
## 0번 "랜덤"은 실제 무기가 아닌 특수값이며 서버가 실제 무기로 확정한다.
##
## 실제 무기 표는 `scripts/weapons.gd`에 있고 여기서는 앞에 "랜덤"만 붙인다 —
## **무기를 추가·변경하려면 `Weapons.LIST`를 고친다.** 통합 가이드: docs/weapon-system.md
var WEAPONS: Array[String] = _selectable_weapons()
const MAPS := ["랜덤", "평지", "냉장고", "봉지 속", "위 속"]

var p1_config := {"weapon": Weapons.RANDOM, "character": Characters.id_at(0)}
var p2_config := {"weapon": Weapons.RANDOM, "character": Characters.id_at(1)}
var map_name := "평지"


func get_config(prefix: String) -> Dictionary:
	return p1_config if prefix == "p1" else p2_config


## "랜덤" + 무기 표 전체. 사본을 따로 두지 않기 위해 Weapons에서 만들어 쓴다.
static func _selectable_weapons() -> Array[String]:
	var out: Array[String] = [Weapons.RANDOM]
	out.append_array(Weapons.names())
	return out
