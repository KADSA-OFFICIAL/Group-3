class_name Art
extends RefCounted
## 그림 공통 처리.
##
## 캐릭터도 무기도 정사각 캔버스에 투명 여백을 두고 그려져 있다. 파일 크기를 그대로 쓰면
## 캐릭터는 발이 땅에서 뜨고 무기는 캐릭터에서 멀찍이 떨어져 보인다.
## 그래서 그리는 쪽은 항상 여백을 뺀 실제 영역을 기준으로 크기와 위치를 잡는다.


## 투명한 여백을 뺀 실제 그림 영역.
## 픽셀을 읽을 수 없는 텍스처(VRAM 압축 등)면 파일 전체를 돌려준다.
static func content_rect(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var full := Rect2(Vector2.ZERO, Vector2(texture.get_size()))
	var image := texture.get_image()
	if image == null or image.is_compressed():
		return full
	var used := Rect2(image.get_used_rect())
	if used.size.x <= 0.0 or used.size.y <= 0.0:
		return full
	return used
