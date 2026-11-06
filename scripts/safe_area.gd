class_name SafeArea
extends Control
## 노치·펀치홀 카메라를 피하는 칸 (#445). 화면 끝에 붙는 UI를 이 노드 아래에 두면
## 기기의 **안전 영역** 안쪽으로 들어온다.
##
## ## 왜 필요한가
##
## 가로로 눕힌 폰은 카메라 구멍이 왼쪽이나 오른쪽 끝에 온다. Godot 안드로이드는 몰입
## 모드에서 그 자리까지 그리므로, 화면 끝에서 16~46px 떨어진 조작물·패널이 구멍 밑에
## 깔릴 수 있다(#329로 화면 비율은 기기를 따라가게 됐지만 구멍은 보지 않았다).
##
## ## 쓰는 법
##
## - 이 노드를 **전체 화면 앵커**(0,0,1,1)로 두고 피해야 하는 UI를 그 아래에 넣는다.
##   자식의 앵커·offset은 그대로 두면 된다 — 이 칸이 줄어드는 만큼 같이 밀린다.
## - 이미 자기 스크립트가 있는 전체 화면 노드는 `SafeArea.fit(self)`를 직접 부른다
##   (`touch_controls.gd`).
## - **배경은 넣지 않는다** — 맵 배경·타이틀 원화·선택 창 진열장은 화면 끝까지 깔려야
##   한다. 밀리는 것은 누르거나 읽어야 하는 것뿐이다.
##
## 부모의 사각형이 뷰포트 전체라고 가정한다(씬 루트의 자식, `UI`(CanvasLayer) 아래
## 전체 화면 HUD의 자식). 그래서 offset에 넣는 값이 곧 뷰포트 좌표의 여백이다.
##
## **모바일에서만 잰다.** PC의 "안전 영역"은 작업 표시줄·메뉴 막대를 뺀 화면이라 창과
## 무관한 여백이 생긴다 — PC에서는 늘 0이라 화면이 이 변경 전과 같다.

## 여백이 이보다 크면 잘못 읽은 값으로 본다(가로·세로의 비율). 컷아웃은 화면 폭의
## 몇 %다 — 이상한 값 하나로 UI가 화면 가운데로 몰리는 것을 막는다.
const MAX_SHARE := 0.2

## 화면 크기가 바뀐 뒤 안전 영역을 다시 재는 때(초) (#451). 폴더블을 접고 펴면 노치·펀치홀
## 자리가 화면마다 다른데, 안드로이드는 새 컷아웃을 창 크기보다 몇 프레임 늦게 줄 수 있다 —
## 바뀐 순간 한 번만 재면 옛 화면의 여백이 남는다.
const SETTLE_TIMES: Array[float] = [0.1, 0.3, 0.6, 1.0]


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_on_size_changed)
	fit(self)


func _on_size_changed() -> void:
	refit(self)


## 크기가 바뀐 순간과 그 뒤 잠깐 동안 다시 잰다 (#451). 크기 변경 신호는 **부르는 쪽의
## 인스턴스 함수**로 받아 이것을 부를 것 — 정적 함수에 노드를 묶어 뷰포트 신호에 걸면
## 씬이 바뀐 뒤에도 연결이 남아 해제된 노드로 불린다(뷰포트는 씬보다 오래 산다).
static func refit(control: Control) -> void:
	fit(control)
	if not OS.has_feature("mobile"):
		return
	var tree := control.get_tree()
	for delay in SETTLE_TIMES:
		tree.create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(control) and control.is_inside_tree():
				fit(control))


## `control`(전체 화면 앵커)의 offset을 안전 영역 여백으로 맞춘다.
static func fit(control: Control) -> void:
	var viewport := control.get_viewport()
	var view := viewport.get_visible_rect().size
	var safe := safe_rect(viewport)
	control.offset_left = safe.position.x
	control.offset_top = safe.position.y
	control.offset_right = safe.end.x - view.x
	control.offset_bottom = safe.end.y - view.y


## 뷰포트(캔버스) 좌표의 안전 영역. 피할 것이 없으면 뷰포트 전체다.
static func safe_rect(viewport: Viewport) -> Rect2:
	var view := viewport.get_visible_rect().size
	if not OS.has_feature("mobile"):
		return Rect2(Vector2.ZERO, view)
	var window := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	return to_viewport(DisplayServer.get_display_safe_area(), window, view)


## 화면 픽셀의 안전 영역(`safe`)을 창(`window`)에 맞춰 잘라 뷰포트 좌표(`view` 크기)로 옮긴다.
## 계산만 하는 함수라 기기 없이도 값을 넣어 확인할 수 있다.
##
## 창이 뷰포트를 같은 배율로 늘려 그리므로(`stretch/aspect = expand`라 검은 띠가 없다)
## 픽셀 여백 × (뷰포트 폭 / 창 폭)이 곧 뷰포트 여백이다.
static func to_viewport(safe: Rect2i, window: Rect2i, view: Vector2) -> Rect2:
	if window.size.x <= 0 or window.size.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Rect2(Vector2.ZERO, view)
	var ratio := view.x / float(window.size.x)
	var left := _inset(safe.position.x - window.position.x, window.size.x) * ratio
	var right := _inset(window.end.x - safe.end.x, window.size.x) * ratio
	var top := _inset(safe.position.y - window.position.y, window.size.y) * ratio
	var bottom := _inset(window.end.y - safe.end.y, window.size.y) * ratio
	return Rect2(left, top, view.x - left - right, view.y - top - bottom)


static func _inset(pixels: int, span: int) -> float:
	return clampf(float(pixels), 0.0, span * MAX_SHARE)
