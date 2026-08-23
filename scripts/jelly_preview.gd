extends Control
## 젤리곰 미리보기. 캐릭터 표의 그림을 비율을 지켜 가운데에 그린다.
##
## 그림 자체는 Characters가 들고 있다 — 여기서는 어떤 캐릭터인지만 받는다.

@export var character_id := "":
	set(value):
		character_id = value
		_refresh()

## 어느 포즈를 보여줄지 (#178). 비어 있으면 평소 모습이다 —
## 대기실 패널과 타이틀 젤리는 지정하지 않으므로 지금까지와 똑같이 동작한다.
## 값은 `Characters.POSE_*` 중 하나이고, 그 포즈의 원화가 없으면 평소 그림으로 되돌아간다.
@export var pose := "":
	set(value):
		pose = value
		_refresh()

## 미리보기 칸을 채우는 비율. 1.0이면 칸에 꽉 차서 너무 커 보인다.
@export_range(0.1, 1.0, 0.05) var fill_ratio := 0.65:
	set(value):
		fill_ratio = value
		queue_redraw()

var _texture: Texture2D = null


func _ready() -> void:
	# 씬에서 캐릭터를 지정하지 않았으면 첫 캐릭터를 보여준다.
	if _texture == null:
		character_id = Characters.default_id()


## 캐릭터와 포즈 어느 쪽이 바뀌어도 같은 곳을 지나가게 모아 둔다 —
## 둘 중 하나만 그림을 갱신하면 나중에 지정한 값이 앞의 것을 지운다.
func _refresh() -> void:
	_texture = Characters.pose_texture(character_id, pose)
	queue_redraw()


func _draw() -> void:
	if _texture == null:
		return
	# 원화의 투명 여백까지 그리면 캐릭터가 작아 보이므로 실제 그림 부분만 쓴다.
	var region := Art.content_rect(_texture)
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	# 패널 크기에 맞추되 가로세로 비율은 유지한다.
	var fit := minf(size.x / region.size.x, size.y / region.size.y) * fill_ratio
	var draw_size := region.size * fit
	draw_texture_rect_region(_texture, Rect2((size - draw_size) * 0.5, draw_size), region)
