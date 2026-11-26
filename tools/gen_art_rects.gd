extends SceneTree
## 그림 여백 표 생성기 (#501). **게임에 들어가지 않는다.**
##
## 무기·캐릭터 원화(`assets/weapons/*.png`·`assets/characters/*.png`)의 **투명 여백을 뺀 실제
## 그림 영역**을 재어 `scripts/art_rects.gd` 에 비율(0~1)로 적는다. `Art.content_rect()` 가
## 이 표를 먼저 본다 — 실행 중에 텍스처를 GPU 에서 되읽어(`get_image()`) 픽셀을 훑는 일이
## 폰에서 판이 넘어갈 때마다 멈칫하게 만들었다.
##
## **원본 PNG 가 아니라 가져온 텍스처를 잰다.** 가져오기가 원화를 줄이면서(`process/size_limit`
## 무기 512·캐릭터 768, #475) 원본 가장자리의 거의 투명한 점들이 사라진다 — 원본으로 재면 활이
## 44px 넓게 나왔다. 게임이 쓰는 것과 같은 텍스처를 같은 방법(`Art._measure_content()`)으로 잰다.
## 그래서 **창을 띄워 돌린다**(`--headless` 는 가짜 렌더러라 텍스처를 되읽지 못한다):
##     Godot --path . --script tools/gen_art_rects.gd
## 비율로 적는 이유는 `size_limit` 을 바꿔도 표가 맞게 하기 위해서다.
##
## **원화를 더하거나 바꾸면 다시 돌린다.** 표에 없는 그림은 예전처럼 실행 중에 잰다
## (느릴 뿐 틀리지는 않는다).

const DIRS: Array[String] = ["res://assets/weapons/", "res://assets/characters/"]
const OUT := "res://scripts/art_rects.gd"

var _frames := 0


func _process(_delta: float) -> bool:
	# 첫 프레임에는 렌더러가 아직 텍스처를 다 올리지 않았을 수 있다.
	_frames += 1
	if _frames < 3:
		return false
	_generate()
	return true


func _generate() -> void:
	var lines: Array[String] = []
	for dir in DIRS:
		var files := Array(ResourceLoader.list_directory(dir))
		files.sort()
		for file: String in files:
			if file.get_extension() != "png":
				continue
			var path := dir + file
			var texture: Texture2D = load(path)
			var image := texture.get_image() if texture != null else null
			if image == null or image.is_empty() or image.is_compressed():
				push_error("텍스처를 되읽지 못했다(헤드리스로 돌렸나?): %s" % path)
				continue
			var size := Vector2(image.get_size())
			var used := Rect2(image.get_used_rect())
			if used.size.x <= 0.0 or used.size.y <= 0.0:
				used = Rect2(Vector2.ZERO, size)
			lines.append('\t"%s": Rect2(%.6f, %.6f, %.6f, %.6f),' % [path,
				used.position.x / size.x, used.position.y / size.y,
				used.size.x / size.x, used.size.y / size.y])

	var text := "\n".join([
		"class_name ArtRects",
		"extends RefCounted",
		"## **생성 파일 — 손으로 고치지 않는다.** `tools/gen_art_rects.gd` 가 만든다 (#501).",
		"## 가져온 원화 텍스처의 투명 여백을 뺀 실제 그림 영역을 텍스처 크기에 대한 비율(0~1)로 적는다.",
		"## 쓰는 곳은 `Art.content_rect()` 하나다.",
		"",
		"const RECTS := {",
	]) + "\n" + "\n".join(lines) + "\n}\n"
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("ART_RECTS wrote %d entries to %s" % [lines.size(), OUT])
