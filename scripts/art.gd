class_name Art
extends RefCounted
## 그림 공통 처리.
##
## 캐릭터도 무기도 정사각 캔버스에 투명 여백을 두고 그려져 있다. 파일 크기를 그대로 쓰면
## 캐릭터는 발이 땅에서 뜨고 무기는 캐릭터에서 멀찍이 떨어져 보인다.
## 그래서 그리는 쪽은 항상 여백을 뺀 실제 영역을 기준으로 크기와 위치를 잡는다.


## `content_rect()` 가 잰 값 (#475). 텍스처 인스턴스 → 영역.
static var _content_rects := {}


## 투명한 여백을 뺀 실제 그림 영역.
## 픽셀을 읽을 수 없는 텍스처(VRAM 압축 등)면 파일 전체를 돌려준다.
##
## **텍스처마다 한 번만 잰다** (#475). 재는 일은 텍스처를 GPU 에서 이미지로 되읽고 픽셀을
## 전부 훑는 것이라 PC 에서도 한 번에 수십 ms 다 — 그런데 궁극기 버튼의 `_draw()` 가
## 쿨타임이 차는 동안 매 프레임, 투사체가 한 발마다 이것을 불러 폰에서 프레임이 무너졌다.
## 같은 경로의 그림은 `load()` 가 같은 인스턴스를 주므로 인스턴스로 기억하면 된다.
static func content_rect(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var key := texture.get_instance_id()
	if _content_rects.has(key):
		return _content_rects[key]
	var rect := _measure_content(texture)
	_content_rects[key] = rect
	return rect


## 판이 열리기 전에 미리 재 둔다 (#475) — 처음 쓰는 순간이 전투 한가운데면 그 한 번이 멈칫한다.
static func warm(textures: Array) -> void:
	for texture in textures:
		if texture is Texture2D:
			content_rect(texture)


static func _measure_content(texture: Texture2D) -> Rect2:
	var full := Rect2(Vector2.ZERO, Vector2(texture.get_size()))
	var image := texture.get_image()
	if image == null or image.is_compressed():
		return full
	var used := Rect2(image.get_used_rect())
	if used.size.x <= 0.0 or used.size.y <= 0.0:
		return full
	return used


## 가운데가 가장 밝고 가장자리로 갈수록 옅어지는 빛무리를 그린다.
##
## 원 하나로 그리면 테두리가 딱 끊겨서 어두운 판때기처럼 보인다. 같은 옅기의 원을
## 크기만 줄여 가며 겹쳐 쌓으면 겹친 횟수만큼 밝아져서 가운데가 밝은 감쇠가 나온다.
## `steps`가 클수록 매끄럽고, 작으면 동심원 띠가 보인다.
static func draw_glow(canvas: CanvasItem, center: Vector2, radius: float,
		color: Color, alpha: float, steps := 26) -> void:
	if radius <= 0.0 or alpha <= 0.0:
		return
	var step_alpha := alpha / float(steps)
	for i in range(steps, 0, -1):
		canvas.draw_circle(center, radius * float(i) / float(steps), Color(color, step_alpha))
