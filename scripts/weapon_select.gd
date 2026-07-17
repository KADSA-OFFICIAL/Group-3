extends Control
## 무기 선택 화면. 각 플레이어가 자기 이동 키(좌/우)로 무기를 고르고 공격 키로 확정한다.

var weapon_ids: Array = GameManager.WEAPONS.keys()
var index := {1: 0, 2: 0}
var locked := {1: false, 2: false}
var _started := false

@onready var name_labels := {
	1: $Center/VBox/Panels/P1Panel/WeaponName,
	2: $Center/VBox/Panels/P2Panel/WeaponName,
}
@onready var status_labels := {
	1: $Center/VBox/Panels/P1Panel/Status,
	2: $Center/VBox/Panels/P2Panel/Status,
}


func _ready() -> void:
	for id in [1, 2]:
		_refresh(id)


func _process(_delta: float) -> void:
	if _started:
		return
	for id in [1, 2]:
		if locked[id]:
			continue
		if Input.is_action_just_pressed("p%d_left" % id):
			index[id] = (index[id] - 1 + weapon_ids.size()) % weapon_ids.size()
			_refresh(id)
		elif Input.is_action_just_pressed("p%d_right" % id):
			index[id] = (index[id] + 1) % weapon_ids.size()
			_refresh(id)
		elif Input.is_action_just_pressed("p%d_attack" % id):
			locked[id] = true
			status_labels[id].text = "준비 완료!"

	if locked[1] and locked[2]:
		_started = true
		GameManager.p1_weapon = weapon_ids[index[1]]
		GameManager.p2_weapon = weapon_ids[index[2]]
		get_tree().change_scene_to_file("res://scenes/match.tscn")


func _refresh(id: int) -> void:
	var weapon_id: String = weapon_ids[index[id]]
	name_labels[id].text = GameManager.WEAPONS[weapon_id]["name"]
	status_labels[id].text = "선택 중..."
