extends Control
## 크레딧 창 (#478). 타이틀의 `크레딧` 버튼이 연다.
##
## **스토어 배포에 앞서 출처 표기가 의무인 것들을 게임 안에 둔다** — 메뉴 곡(Kevin MacLeod)은
## CC BY 4.0 이라 이름과 라이선스를 적어야 하고, Godot 엔진(MIT)과 Black Han Sans 글꼴(SIL OFL
## 1.1)도 저작권 문구를 함께 배포해야 한다. 엔진 라이선스 원문은 `Engine.get_license_text()` 로
## 엔진에서 그대로 꺼낸다 — 손으로 옮겨 적으면 엔진 버전을 올릴 때 어긋난다.
##
## 글은 `SECTIONS` 한 곳에서만 고친다. 음원을 더하거나 바꾸면 여기에 한 줄을 더한다.

signal closed

const SECTIONS := [
	["음악", [
		"\"Pixel Peeker Polka - faster\" Kevin MacLeod (incompetech.com)",
		"Licensed under Creative Commons: By Attribution 4.0 License",
		"http://creativecommons.org/licenses/by/4.0/",
		"",
		"\"Combat Loop\" · \"Arcade Battle\" · \"Face Off Groove\"",
	]],
	["효과음", [
		"dragon-studio · universfield · humordome · poorartistt · dariocoiro (Pixabay)",
		"그 밖의 효과음은 직접 합성했습니다.",
	]],
	["글꼴", [
		"Black Han Sans — Copyright 2015 The Black Han Sans Project Authors",
		"SIL Open Font License, Version 1.1",
	]],
	["엔진", [
		"Godot Engine (godotengine.org) — MIT License",
	]],
]

@onready var _body: Label = $Card/Margin/VBox/Scroll/Body
@onready var _close: Button = $Card/Margin/VBox/CloseButton


func _ready() -> void:
	_close.pressed.connect(close)
	_body.text = _compose()


func open() -> void:
	show()
	($Card/Margin/VBox/Scroll as ScrollContainer).scroll_vertical = 0


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _compose() -> String:
	var lines: PackedStringArray = []
	for section: Array in SECTIONS:
		lines.append("[ %s ]" % section[0])
		for line: String in section[1]:
			lines.append(line)
		lines.append("")
	lines.append("[ Godot Engine 라이선스 ]")
	lines.append(Engine.get_license_text())
	return "\n".join(lines)
