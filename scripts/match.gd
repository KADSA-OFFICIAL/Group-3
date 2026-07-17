extends Node2D
## 라운드 진행: 랜덤 맵 로드 -> 전투 -> 승자 1점 -> 3점 선취 시 매치 종료.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const KILL_Y := 800.0
const ROUND_DELAY := 2.0
const MATCH_END_DELAY := 3.0

var players := {}
var _round_active := false

@onready var map_holder: Node2D = $MapHolder
@onready var banner: Label = $HUD/Banner
@onready var score_label: Label = $HUD/ScoreLabel
@onready var health_bars := {1: $HUD/P1Health, 2: $HUD/P2Health}


func _ready() -> void:
	for id in [1, 2]:
		var player: Player = PLAYER_SCENE.instantiate()
		player.player_id = id
		player.died.connect(_on_player_died)
		player.health_changed.connect(_on_health_changed)
		add_child(player)
		players[id] = player
	_start_round()


func _start_round() -> void:
	banner.text = ""
	for child in map_holder.get_children():
		child.queue_free()
	for projectile in get_tree().get_nodes_in_group("projectiles"):
		projectile.queue_free()

	var map: Node2D = load(GameManager.random_map()).instantiate()
	map_holder.add_child(map)
	for id in [1, 2]:
		players[id].show()
		players[id].set_physics_process(true)
		players[id].reset(map.get_node("SpawnP%d" % id).global_position)
	_update_score_label()
	_round_active = true


func _physics_process(_delta: float) -> void:
	if not _round_active:
		return
	for id in players:
		var player: Player = players[id]
		if player.global_position.y > KILL_Y and player.health > 0.0:
			player.take_damage(Player.MAX_HEALTH)


func _on_player_died(dead_id: int) -> void:
	if not _round_active:
		return
	_round_active = false
	players[dead_id].hide()
	players[dead_id].set_physics_process(false)

	var winner: int = 2 if dead_id == 1 else 1
	GameManager.add_point(winner)
	_update_score_label()

	if GameManager.is_match_over():
		banner.text = "%dP 최종 승리!" % GameManager.match_winner()
		get_tree().create_timer(MATCH_END_DELAY).timeout.connect(_back_to_menu)
	else:
		banner.text = "%dP 라운드 승리!" % winner
		get_tree().create_timer(ROUND_DELAY).timeout.connect(_start_round)


func _on_health_changed(id: int, health: float) -> void:
	health_bars[id].value = health


func _update_score_label() -> void:
	score_label.text = "%d  :  %d" % [GameManager.scores[1], GameManager.scores[2]]


func _back_to_menu() -> void:
	GameManager.reset_match()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
