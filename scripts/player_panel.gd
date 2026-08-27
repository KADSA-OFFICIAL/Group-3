extends Control
## 선택 창의 플레이어 한 명 분량 패널 (미리보기 + 캐릭터 선택)
##
## **무기는 여기서 고르지 않는다**(#205). 라운드가 시작될 때마다 전투 화면에서 고른다.
##
## 젤리 위에는 아무것도 얹지 않는다 (요청). `Player` 한 줄만 든 `OptionButton`이 있었는데
## 고를 것이 하나뿐이라 누를 수 없는 칸이었고, 읽는 곳도 없었다 — 젤리 위에 남은 것은
## 자리 이름이라기보다 정체를 알 수 없는 상자였다. 다시 넣지 말 것: 1P·2P 구분은
## 패널 위치(왼쪽·오른쪽)와 카드 색이 이미 하고 있다.
##
## 온라인에서는 자기 패널만 조작할 수 있고(`set_interactive`),
## 상대 패널은 서버가 보낸 값을 `apply_config()`로 표시만 한다.

## 이 패널의 선택이 사용자 조작으로 바뀌었을 때 (서버 전송용)
signal config_changed

@export var mirrored := false          # 2P는 아이콘 열이 오른쪽으로
@export var default_character := 0

## 이 패널의 **편 색** (요청, 사용자가 준 목업 기준). 왼쪽은 분홍, 오른쪽은 라벤더이고
## 카드 테두리·랜덤 버튼·캐릭터 버튼 글자가 모두 이 색을 쓴다.
##
## **테마가 아니라 여기서 정하는 이유**: 테마의 `Panel` 스타일은 한 벌뿐인데 이 화면에는
## 편마다 다른 카드가 두 장 필요하다(`CLAUDE.md` 의 "색은 테마에서" 규칙은 화면 전체에
## 걸리는 색을 말한다). 색이 흩어지지 않도록 **씬에서 이 속성 하나만** 정하고,
## 나머지 짙기·옅기는 아래 `_apply_accent()` 가 그것에서 만들어 낸다.
@export var accent := Color(0.96, 0.55, 0.78):
	set(value):
		accent = value
		if is_inside_tree():
			_apply_accent()

var character_i := 0

@onready var hbox: HBoxContainer = $HBox
@onready var icon_column: VBoxContainer = $HBox/IconColumn
@onready var character_button: Button = $HBox/IconColumn/CharacterButton
@onready var preview = $HBox/Center/Preview
@onready var random_button: Button = $HBox/Center/RandomButton
@onready var card: Panel = $Card
## panel_star.gd는 class_name이 없어 타입을 붙이지 않는다 (jelly_preview.gd와 같은 방식).
@onready var star = $Star


func _ready() -> void:
	character_i = default_character % GameState.CHARACTERS.size()
	if mirrored:
		hbox.move_child(icon_column, 1)
		# 배지도 아이콘 열과 같은 쪽으로 간다 — 카드의 바깥 위 모서리에 달려야
		# 두 장이 마주 보는 한 쌍으로 읽힌다 (요청, 목업 기준).
		star.anchor_left = 1.0
		star.anchor_right = 1.0
		star.offset_left = -74.0
		star.offset_right = -6.0
	character_button.pressed.connect(_cycle.bind("character"))
	random_button.pressed.connect(_randomize_all)
	_apply_accent()
	_update_ui()


## 편 색을 카드·버튼·배지에 입힌다 (요청).
##
## **스타일박스를 반드시 `duplicate()` 해서 쓴다.** 씬에 박아 둔 `SubResource` 는 그 씬을
## 여러 번 만들어도 **같은 객체 하나를 나눠 쓴다** — 복제하지 않고 색을 바꾸면 1P를
## 칠하는 순간 2P 카드까지 같이 분홍이 된다.
func _apply_accent() -> void:
	var deep := accent.darkened(0.28)
	var pale := accent.lerp(Color(1.0, 1.0, 1.0), 0.86)

	# 카드: 아주 옅은 편 색 바탕에 편 색 테두리. 모서리·그림자는 테마의 카드를 물려받는다.
	var card_style := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if card_style != null:
		card_style.bg_color = pale
		card_style.border_width_left = 4
		card_style.border_width_top = 4
		card_style.border_width_right = 4
		card_style.border_width_bottom = 4
		card_style.border_color = accent
		card_style.shadow_color = Color(deep, 0.30)
		card.add_theme_stylebox_override("panel", card_style)

	# 랜덤 버튼: 씬에 라벤더로 박혀 있는 모습들을 편 색으로 옮긴다.
	# **`disabled` 도 함께 옮긴다** — 상대 패널은 늘 잠겨 있으므로 이것을 빼면
	# 두 카드 중 한쪽 버튼만 회색으로 남아 편 색이 반쪽만 칠해진 화면이 된다.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := random_button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if style == null:
			continue
		# 원래 짙기 차이(보통·올림·누름)를 그대로 유지하려고 상태마다 조금씩 다르게 잡는다.
		# 잠긴 모습만 흰색을 섞어 옅게 — 색은 남기고 "지금은 못 누른다"만 말한다.
		var body := accent
		if state == "hover":
			body = accent.lightened(0.08)
		elif state == "pressed":
			body = accent.darkened(0.12)
		elif state == "disabled":
			body = accent.lerp(Color(1.0, 1.0, 1.0), 0.45)
		style.bg_color = body
		style.border_color = deep if state != "disabled" else accent.lerp(deep, 0.4)
		style.shadow_color = Color(deep, 0.30 if state != "disabled" else 0.14)
		random_button.add_theme_stylebox_override(state, style)

	# 캐릭터 버튼은 흰 알약 그대로 두고 글자만 편 색으로 물들인다 (목업과 같다).
	for name_ in ["font_color", "font_hover_color", "font_pressed_color"]:
		character_button.add_theme_color_override(name_, deep)

	star.color = accent


## 조작 가능 여부. 상대 패널은 false로 두어 표시 전용이 된다.
func set_interactive(value: bool) -> void:
	for button in [character_button, random_button]:
		button.disabled = not value


## 관전자용 표시 전용 모드 (이슈 #184).
##
## `set_interactive(false)`는 버튼을 **잠근 채로 남겨** 두는데, 관전자에게는 애초에 조작할 것이
## 없으므로 누를 것은 치우고 볼 것만 남긴다. 캐릭터 버튼은 값이 글자로 적혀 있어
## **그 자체가 표시**이므로 남기되, 잠가서 흐리게 만들지 않고 눌리지만 않게 한다.
func set_display_only(flag: bool) -> void:
	random_button.visible = not flag
	for button in [character_button]:
		button.disabled = false if flag else button.disabled
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE if flag else Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_NONE if flag else Control.FOCUS_ALL


## 서버가 보낸 선택값을 그대로 표시한다. config_changed를 내보내지 않는다.
func apply_config(config: Dictionary) -> void:
	character_i = maxi(GameState.CHARACTERS.find(config.get("character", "")), 0)
	_update_ui()


func _cycle(what: String) -> void:
	match what:
		"character":
			character_i = (character_i + 1) % GameState.CHARACTERS.size()
	_update_ui()
	config_changed.emit()


func _randomize_all() -> void:
	character_i = randi() % GameState.CHARACTERS.size()
	_update_ui()
	config_changed.emit()


func _update_ui() -> void:
	character_button.text = "캐릭터\n" + GameState.CHARACTERS[character_i]
	preview.character_id = GameState.CHARACTERS[character_i]


func get_config() -> Dictionary:
	return {
		"character": GameState.CHARACTERS[character_i],
	}
