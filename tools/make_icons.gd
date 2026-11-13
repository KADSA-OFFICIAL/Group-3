extends SceneTree
## 앱 아이콘을 게임 원화로 만든다 (#478). 결과는 `assets/icon/` 에 쓴다.
##
##     godot --headless --path . --script res://tools/make_icons.gd
##
## **타이틀 배경(`assets/ui/cover.png`)의 가운데 정사각형을 그대로 쓴다** (요청) — 원화가
## 1152×768 이라 가운데 768×768(로고와 분홍·파랑 곰)이다.
##
## 만드는 것:
## - `play_512.png` — Play 스토어 등록용 512×512 (스토어가 모서리를 둥글게 깎는다)
## - `launcher_192.png` — 안드로이드 기본 런처 아이콘
## - `adaptive_bg_432.png`·`adaptive_fg_432.png` — 안드로이드 8+ 적응형 아이콘 뒤·앞 판.
##   그림을 뒤판에 깔고 앞판은 비워 둔다. 기기는 108dp 캔버스의 **가운데 72dp(2/3)** 만 원·둥근
##   네모로 잘라 보여 준다. 그림을 판에 꽉 채우면 원래 정사각형의 가운데 2/3만 보여 로고와 곰이
##   잘렸다(#492). 그래서 그림을 줄여 깔고(`ADAPTIVE_VISIBLE`), 남는 가장자리는 그림 가장자리
##   픽셀을 늘려 채운다 — 보통은 마스크 밖이라 안 보이지만, 판을 움직이는 런처에서 빈 칸이
##   드러나지 않게 한다.

const OUT := "res://assets/icon/"
const COVER := "res://assets/ui/cover.png"

## 적응형 아이콘 판의 한 변 길이(px). 안드로이드가 정한 108dp 캔버스다.
const ADAPTIVE_SIZE := 432
## 런처가 실제로 보여 주는 칸의 비율 — 108dp 중 72dp.
const ADAPTIVE_WINDOW := 72.0 / 108.0
## 그 칸 안에 원래 정사각형이 얼마나 들어오게 할지 (#492). 1.0 이면 그림 전체가 칸에 딱 맞지만
## 원형 마스크가 네 귀퉁이를 깎는다. 0.85 면 칸의 가장자리까지 그림이 차 있으면서 로고와 곰이
## 잘리지 않는다. 판에 깔리는 그림은 `ADAPTIVE_SIZE * ADAPTIVE_WINDOW / ADAPTIVE_VISIBLE`(약 339px)이다.
const ADAPTIVE_VISIBLE := 0.85


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# 가져오기한 텍스처가 아니라 원본 PNG 를 읽는다.
	var cover := Image.load_from_file(ProjectSettings.globalize_path(COVER))
	var side := mini(cover.get_width(), cover.get_height())
	var square := cover.get_region(Rect2i(
			(cover.get_width() - side) / 2, (cover.get_height() - side) / 2, side, side))
	square.convert(Image.FORMAT_RGBA8)

	_resized(square, 512).save_png(ProjectSettings.globalize_path(OUT + "play_512.png"))
	_resized(square, 192).save_png(ProjectSettings.globalize_path(OUT + "launcher_192.png"))
	_adaptive_background(square).save_png(ProjectSettings.globalize_path(OUT + "adaptive_bg_432.png"))
	Image.create_empty(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8) \
			.save_png(ProjectSettings.globalize_path(OUT + "adaptive_fg_432.png"))
	print("icons written to ", OUT)
	quit()


## 줄인 그림을 판 가운데에 놓고, 남는 가장자리는 가장 가까운 그림 가장자리 픽셀로 채운다.
func _adaptive_background(square: Image) -> Image:
	var art_size := roundi(ADAPTIVE_SIZE * ADAPTIVE_WINDOW / ADAPTIVE_VISIBLE)
	var art := _resized(square, art_size)
	var origin := (ADAPTIVE_SIZE - art_size) / 2
	var out := Image.create_empty(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8)
	for y in ADAPTIVE_SIZE:
		var sy := clampi(y - origin, 0, art_size - 1)
		for x in ADAPTIVE_SIZE:
			out.set_pixel(x, y, art.get_pixel(clampi(x - origin, 0, art_size - 1), sy))
	return out


func _resized(image: Image, size: int) -> Image:
	var out := image.duplicate() as Image
	out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return out
