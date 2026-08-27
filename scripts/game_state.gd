extends Node
## 화면 간에 공유되는 게임 설정 (오토로드 싱글톤 GameState)

## 선택 가능한 캐릭터 목록. 선택 UI·검증·전송이 모두 이 배열을 따른다.
##
## 실제 캐릭터 표는 `scripts/characters.gd`에 있고 여기서는 이름만 꺼내 쓴다 —
## **캐릭터를 추가·변경하려면 `Characters.LIST`를 고친다.**
var CHARACTERS: Array[String] = Characters.names()

## **무기 목록은 여기 없다**(#205). 무기는 대기실이 아니라 라운드가 시작될 때 고르고,
## 그때 제시할 후보는 서버가 `Weapons.random_choices()`로 직접 뽑는다 —
## 화면이 훑을 목록이 필요 없어졌다. 통합 가이드: docs/weapon-system.md

## **맵 목록도 여기 없다** (요청). 무기(#205)와 같은 길을 갔다 — 대기실에서 고르던 것을
## 없앴고, 지금은 라운드가 열릴 때마다 전투 화면의 서버가 `Maps.resolve(Maps.RANDOM)`로
## 직접 뽑는다 (`main.gd`의 `_start_round`). 화면이 훑을 목록이 필요 없어졌다.
## **맵을 추가·변경하려면 `Maps.LIST`를 고친다** — 뽑기가 그 표를 그대로 읽는다.

var p1_config := {"character": Characters.id_at(0)}
var p2_config := {"character": Characters.id_at(1)}


func get_config(prefix: String) -> Dictionary:
	return p1_config if prefix == "p1" else p2_config
