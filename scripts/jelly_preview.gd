extends Control
## 젤리 캐릭터 미리보기 (코드로 직접 그림)

@export var body_color := Color(0.25, 0.95, 0.95):
	set(value):
		body_color = value
		queue_redraw()

@export var eye_color := Color(0.15, 0.15, 0.25):
	set(value):
		eye_color = value
		queue_redraw()


func _draw() -> void:
	var w := 170.0
	var h := 220.0
	var rect := Rect2((size.x - w) / 2.0, (size.y - h) / 2.0, w, h)

	var sb := StyleBoxFlat.new()
	sb.bg_color = body_color
	sb.corner_radius_top_left = 85
	sb.corner_radius_top_right = 85
	sb.corner_radius_bottom_left = 25
	sb.corner_radius_bottom_right = 25
	draw_style_box(sb, rect)

	var eye_y := rect.position.y + 75.0
	draw_circle(Vector2(rect.position.x + w * 0.33, eye_y), 11.0, eye_color)
	draw_circle(Vector2(rect.position.x + w * 0.67, eye_y), 11.0, eye_color)
