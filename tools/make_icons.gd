extends SceneTree
## 앱 아이콘을 게임 원화로 만든다 (#478). 결과는 `assets/icon/` 에 쓴다.
##
##     godot --headless --path . --script res://tools/make_icons.gd
##
## 만드는 것:
## - `play_512.png` — Play 스토어 등록용 512×512 (스토어가 모서리를 둥글게 깎는다)
## - `launcher_192.png` — 안드로이드 기본 런처 아이콘
## - `adaptive_fg_432.png`·`adaptive_bg_432.png` — 안드로이드 8+ 적응형 아이콘 앞·뒤 판.
##   기기가 앞판을 원·둥근 네모 등으로 잘라 보여 주므로 **곰은 가운데 66% 안에만** 둔다.
##
## 그림은 1P 분홍 곰의 승리 포즈(손 흔들기)를 라벤더→하늘 그라데이션 위에 올린다 —
## 분홍 바탕에 분홍 곰은 작은 크기에서 묻힌다.

const OUT := "res://assets/icon/"
const BEAR := "res://assets/characters/bear_pink_win.png"
const TOP := Color(0.56, 0.59, 0.91)
const BOTTOM := Color(0.62, 0.86, 0.97)
const HALO := Color(1, 1, 1, 0.55)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# 가져오기에서 줄인 텍스처가 아니라 원본 PNG 를 읽는다 — 큰 원본에서 줄여야 선명하다.
	var bear := Image.load_from_file(ProjectSettings.globalize_path(BEAR))
	bear = bear.get_region(bear.get_used_rect())

	_compose(512, bear, 0.80, true).save_png(ProjectSettings.globalize_path(OUT + "play_512.png"))
	_compose(192, bear, 0.80, true).save_png(ProjectSettings.globalize_path(OUT + "launcher_192.png"))
	_background(432).save_png(ProjectSettings.globalize_path(OUT + "adaptive_bg_432.png"))
	var fg := Image.create_empty(432, 432, false, Image.FORMAT_RGBA8)
	_paste_bear(fg, bear, 0.58, false)
	fg.save_png(ProjectSettings.globalize_path(OUT + "adaptive_fg_432.png"))
	print("icons written to ", OUT)
	quit()


func _compose(size: int, bear: Image, fill: float, halo: bool) -> Image:
	var img := _background(size)
	_paste_bear(img, bear, fill, halo)
	return img


func _background(size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var c := TOP.lerp(BOTTOM, float(y) / float(size - 1))
		for x in size:
			img.set_pixel(x, y, c)
	return img


## 곰을 `fill`(한 변 대비 비율) 크기로 가운데에 놓는다. `halo` 면 뒤에 흰 빛무리를 깐다.
func _paste_bear(img: Image, bear: Image, fill: float, halo: bool) -> void:
	var size := img.get_width()
	if halo:
		var center := Vector2(size, size) * 0.5
		var radius := size * fill * 0.52
		for y in size:
			for x in size:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / radius
				if d < 1.0:
					var a := HALO.a * (1.0 - d * d)
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(HALO, 1.0), a))
	var box := size * fill
	var scale := minf(box / bear.get_width(), box / bear.get_height())
	var scaled := bear.duplicate() as Image
	scaled.resize(maxi(1, roundi(bear.get_width() * scale)), maxi(1, roundi(bear.get_height() * scale)),
			Image.INTERPOLATE_LANCZOS)
	var pos := Vector2i((size - scaled.get_width()) / 2, (size - scaled.get_height()) / 2)
	img.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), pos)
