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
##
## **원화는 재지 않고 표에서 꺼낸다** (#501). 처음 한 번 재는 것조차 폰에서는 판이 넘어갈
## 때마다(무기 카드·카운트다운) 멈칫하게 만들었다 — `ArtRects.RECTS`(`tools/gen_art_rects.gd`
## 가 원본 PNG 에서 미리 잰 비율)에 있으면 텍스처 크기를 곱하기만 한다. 표에 없는 그림
## (새로 넣고 표를 안 다시 만든 원화)만 예전처럼 잰다 — 느릴 뿐 값은 같다.
static func content_rect(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var key := texture.get_instance_id()
	if _content_rects.has(key):
		return _content_rects[key]
	var rect := _table_rect(texture)
	if rect.size == Vector2.ZERO:
		rect = _measure_content(texture)
	_content_rects[key] = rect
	return rect


## 미리 잰 표에서 꺼낸다 (#501). 표에 없으면 빈 영역.
static func _table_rect(texture: Texture2D) -> Rect2:
	var ratio: Rect2 = ArtRects.RECTS.get(texture.resource_path, Rect2())
	if ratio.size == Vector2.ZERO:
		return Rect2()
	var size := Vector2(texture.get_size())
	return Rect2(ratio.position * size, ratio.size * size)


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
