extends Control
## 대기실의 무기 그림 미리보기. `jelly_preview.gd`와 같은 형태다.
##
## 그림이 있는 무기는 7종뿐이라 **나머지는 아무것도 그리지 않는다** —
## 이름은 옆의 라벨이 항상 보여주므로 빈칸으로 남지 않는다.

@export var weapon_id := "":
	set(value):
		weapon_id = value
		_texture = Weapons.texture(value)
		queue_redraw()

## 칸을 채우는 비율. 1.0이면 꽉 차서 답답해 보인다.
@export_range(0.1, 1.0, 0.05) var fill_ratio := 0.85:
	set(value):
		fill_ratio = value
		queue_redraw()

var _texture: Texture2D = null


func _draw() -> void:
	if _texture == null:
		return
	# 원화의 투명 여백까지 그리면 무기가 작아 보이므로 실제 그림 부분만 쓴다.
	var region := Art.content_rect(_texture)
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	var fit := minf(size.x / region.size.x, size.y / region.size.y) * fill_ratio
	var draw_size := region.size * fit
	draw_texture_rect_region(_texture, Rect2((size - draw_size) * 0.5, draw_size), region)
