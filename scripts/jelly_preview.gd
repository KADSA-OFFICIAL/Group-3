extends Control
## 젤리곰 미리보기. 캐릭터 표의 그림을 비율을 지켜 가운데에 그린다.
##
## 그림 자체는 Characters가 들고 있다 — 여기서는 어떤 캐릭터인지만 받는다.

@export var character_id := "":
	set(value):
		character_id = value
		_texture = Characters.texture(value)
		queue_redraw()

var _texture: Texture2D = null


func _ready() -> void:
	# 씬에서 캐릭터를 지정하지 않았으면 첫 캐릭터를 보여준다.
	if _texture == null:
		character_id = Characters.default_id()


func _draw() -> void:
	if _texture == null:
		return
	# 원화의 투명 여백까지 그리면 캐릭터가 작아 보이므로 실제 그림 부분만 쓴다.
	var region := Characters.content_rect(_texture)
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	# 패널 크기에 맞추되 가로세로 비율은 유지한다.
	var fit := minf(size.x / region.size.x, size.y / region.size.y)
	var draw_size := region.size * fit
	draw_texture_rect_region(_texture, Rect2((size - draw_size) * 0.5, draw_size), region)
