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
##   그림 전체를 뒤판에 깔고 앞판은 비워 둔다. 기기는 뒤판의 **가운데 약 2/3** 만 원·둥근
##   네모로 잘라 보여 주므로 런처에서는 스토어 아이콘보다 조금 더 가까이 보인다.

const OUT := "res://assets/icon/"
const COVER := "res://assets/ui/cover.png"


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
	_resized(square, 432).save_png(ProjectSettings.globalize_path(OUT + "adaptive_bg_432.png"))
	Image.create_empty(432, 432, false, Image.FORMAT_RGBA8) \
			.save_png(ProjectSettings.globalize_path(OUT + "adaptive_fg_432.png"))
	print("icons written to ", OUT)
	quit()


func _resized(image: Image, size: int) -> Image:
	var out := image.duplicate() as Image
	out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return out
