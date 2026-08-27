extends Control
## 캐릭터 선택창의 배경과 가운데 장식 (요청, 사용자가 준 목업 기준).
##
## **그림 파일 없이 `_draw()` 로만 그린다** — 목업은 원화 한 장이었지만 이 저장소의 연출은
## 전부 `_draw()` 라서(`light_burst.gd`·`point_gain.gd`) 같은 방식으로 옮겼다. 덕분에
## 화면 크기가 바뀌어도 따라오고, 색을 고치는 것도 상수 한 줄이다.
##
## 화면을 **왼쪽 분홍 · 오른쪽 남색**으로 갈라 두 사람의 편을 배경부터 나눈다. 가운데
## 이음선은 번개이고 그 위에 `VS` 가 얹힌다 — 카드 사이의 빈 자리가 곧 대결의 자리가 된다.
##
## **이 노드는 아무것도 가리지 않는다.** 씬에서 맨 앞(`BG` 다음)에 두어 카드·버튼·글자가
## 모두 이 위에 그려진다. 가운데 장식(번개·`VS`·리본)은 카드 사이 빈 자리에만 있으므로
## 뒤에서 그려도 가려지지 않는다.

# ─────────────────────────── 배경 색 ───────────────────────────
## 네 귀퉁이 색. 가로로는 두 편을 섞고 세로로는 위(어둡게)에서 아래(밝게)로 간다 —
## 위가 밤하늘, 아래가 꽃밭인 목업의 짜임이다.
const TOP_LEFT := Color(0.82, 0.31, 0.58)
const BOTTOM_LEFT := Color(0.98, 0.68, 0.80)
const TOP_RIGHT := Color(0.21, 0.17, 0.47)
const BOTTOM_RIGHT := Color(0.51, 0.45, 0.87)

## 배경에 뭉실하게 얹는 구름의 개수. 목업의 붓 자국을 이것으로 대신한다 —
## 고른 그라데이션만 두면 색종이 두 장을 붙인 것으로 보인다.
const CLOUD_COUNT := 9

## 배경을 세로 띠 몇 개로 나눠 그릴지 결정하는 띠 폭(px). 좁을수록 매끄럽지만
## 그리는 횟수가 늘어난다. 8px이면 기준 화면에서 144번이고 눈으로는 이어져 보인다.
const BAND_WIDTH := 8.0

## 가운데 이음선이 번지는 폭(px). 이 안에서 두 편 색이 섞인다 —
## 딱 잘리면 화면을 반으로 자른 판때기가 된다.
const SEAM_BLEND := 260.0

# ─────────────────────────── 번개 ───────────────────────────
## 가운데를 위에서 아래로 지르는 번개. 꺾이는 지점의 (세로 비율, 가로 치우침) 이다.
const BOLT_NODES := [
	Vector2(0.00, 0.030), Vector2(0.16, -0.035), Vector2(0.31, 0.028),
	Vector2(0.46, -0.020), Vector2(0.58, 0.036), Vector2(0.72, -0.030),
	Vector2(0.86, 0.022), Vector2(1.00, -0.012),
]
## 번개의 두께(px)와 그 안쪽 흰 심의 비율.
const BOLT_WIDTH := 26.0
const BOLT_CORE := 0.38

# ─────────────────────────── VS ───────────────────────────
## `VS` 의 중심과 크기. 두 글자를 따로 그려 색을 나눈다 — 한 덩어리로 적으면
## 어느 쪽이 누구인지 색으로 읽히지 않는다.
const VS_CENTER_Y := 208.0
const VS_SIZE := 116
const VS_OUTLINE := 22
const VS_LEFT_COLOR := Color(0.93, 0.28, 0.50)
const VS_RIGHT_COLOR := Color(0.36, 0.60, 0.95)
const VS_OUTLINE_COLOR := Color(1.0, 1.0, 1.0)

# ─────────────────────────── 리본 ───────────────────────────
## 맨 위 가운데의 `캐릭터 선택` 이름표. 좌우가 접힌 리본 모양이다.
const RIBBON_TEXT := "캐릭터 선택"
const RIBBON_TOP := 22.0
const RIBBON_HEIGHT := 44.0
const RIBBON_HALF := 136.0
## 좌우로 접혀 들어가는 깊이.
const RIBBON_FOLD := 20.0
const RIBBON_SIZE := 24
const RIBBON_COLOR := Color(0.94, 0.44, 0.64)
const RIBBON_EDGE := Color(0.78, 0.26, 0.48)

# ─────────────────────────── 반짝임·젤리 조각 ───────────────────────────
const STAR_COUNT := 120
## 그중 십자로 뻗는 큰 반짝임의 개수. 나머지는 작은 점이다.
const SPARKLE_COUNT := 22
## 떠 있는 젤리 조각(네모)의 개수.
const CUBE_COUNT := 12

## 아래쪽 꽃밭 띠의 높이(px)와 색.
const GROUND_HEIGHT := 74.0
const GROUND_COLOR := Color(0.26, 0.32, 0.28)
const GROUND_LIGHT := Color(0.42, 0.56, 0.36)
const FLOWER_COUNT := 22

## 자리를 정할 때 쓰는 씨앗. 고정해 두면 켤 때마다 같은 하늘이 나온다 —
## 매번 달라지면 화면을 고칠 때 무엇이 바뀐 것인지 알 수 없다.
const SEED := 20260828

const FONT := preload("res://resources/display_font.tres")

## 자리와 크기는 `_ready()` 에서 한 번 뽑아 둔다. 매 프레임 다시 뽑으면 하늘이 떤다.
var _stars: Array[Dictionary] = []
var _cubes: Array[Dictionary] = []
var _flowers: Array[Dictionary] = []
var _clouds: Array[Dictionary] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# 화면 크기는 앵커가 잡아 주므로 `_ready()` 시점에는 아직 0일 수 있다 —
	# 자리는 비율로 뽑고 그릴 때 실제 크기를 곱한다.
	for i in STAR_COUNT:
		_stars.append({
			"at": Vector2(rng.randf(), rng.randf() * 0.86),
			"size": rng.randf_range(1.2, 3.2),
			"alpha": rng.randf_range(0.45, 1.0),
			"sparkle": i < SPARKLE_COUNT,
			"reach": rng.randf_range(7.0, 16.0),
		})
	# 젤리 조각은 **카드에 가리지 않는 자리**에만 놓는다 — 카드가 화면의 좌우 3분의 2를
	# 덮고 있어서 아무 데나 뿌리면 열두 개 중 두세 개만 보인다. 절반은 카드 위쪽 띠에,
	# 절반은 두 카드 사이 가운데 칸에 둔다.
	for i in CUBE_COUNT:
		var at := Vector2(rng.randf(), rng.randf_range(0.005, 0.10))
		if i % 2 == 1:
			at = Vector2(rng.randf_range(0.385, 0.615), rng.randf_range(0.05, 0.86))
		_cubes.append({
			"at": at,
			"size": rng.randf_range(22.0, 42.0),
			"angle": rng.randf_range(-0.5, 0.5),
			"alpha": rng.randf_range(0.55, 0.9),
		})
	for i in FLOWER_COUNT:
		_flowers.append({
			"at": Vector2(rng.randf(), rng.randf_range(0.25, 0.85)),
			"size": rng.randf_range(2.4, 4.4),
			"hue": rng.randi_range(0, 3),
		})
	for i in CLOUD_COUNT:
		_clouds.append({
			"at": Vector2(rng.randf(), rng.randf_range(0.06, 0.78)),
			"radius": rng.randf_range(0.10, 0.26),
			"alpha": rng.randf_range(0.10, 0.24),
		})


func _draw() -> void:
	_draw_background()
	_draw_clouds()
	_draw_bolt()
	_draw_stars()
	_draw_cubes()
	_draw_ground()
	_draw_vs()
	_draw_ribbon()


## 두 편 색을 가로로 섞고 세로로 밝혀 가며 세로 띠로 칠한다.
func _draw_background() -> void:
	var bands := int(ceil(size.x / BAND_WIDTH))
	for i in bands:
		var x0 := float(i) * BAND_WIDTH
		var x1 := minf(x0 + BAND_WIDTH, size.x)
		var top_left := _side_color(x0, true)
		var top_right := _side_color(x1, true)
		var bottom_left := _side_color(x0, false)
		var bottom_right := _side_color(x1, false)
		draw_polygon(
			PackedVector2Array([
				Vector2(x0, 0.0), Vector2(x1, 0.0),
				Vector2(x1, size.y), Vector2(x0, size.y),
			]),
			PackedColorArray([top_left, top_right, bottom_right, bottom_left]))


## 가로 위치 하나의 색. `top` 이면 위쪽 색, 아니면 아래쪽 색이다.
##
## 가운데에서는 두 편 색을 부드럽게 섞고, 이음선 바로 옆은 번개 빛으로 조금 밝힌다.
func _side_color(x: float, top: bool) -> Color:
	var center := size.x * 0.5
	# -1(왼쪽 끝) ~ +1(오른쪽 끝). 이음선 폭 안에서만 섞이도록 눌러 잡는다.
	var mix := clampf((x - center) / (SEAM_BLEND * 0.5), -1.0, 1.0)
	# 부드럽게(smoothstep) 섞어야 섞이는 구간의 경계가 또 보이지 않는다.
	var t := 0.5 + 0.5 * (mix * mix * mix * 0.5 + mix * 0.5)
	var left := TOP_LEFT if top else BOTTOM_LEFT
	var right := TOP_RIGHT if top else BOTTOM_RIGHT
	var color := left.lerp(right, t)
	# 이음선 가까이는 번개가 비추는 만큼 밝다.
	var glow := 1.0 - clampf(absf(x - center) / (SEAM_BLEND * 0.8), 0.0, 1.0)
	return color.lerp(Color(1.0, 0.96, 1.0), glow * glow * 0.22)


## 배경에 뭉실하게 얹는 구름. 자기 쪽 편 색을 밝힌 빛무리다.
func _draw_clouds() -> void:
	for cloud: Dictionary in _clouds:
		var at: Vector2 = cloud["at"]
		var pos := Vector2(at.x * size.x, at.y * size.y)
		var radius: float = cloud["radius"]
		var alpha: float = cloud["alpha"]
		var side := TOP_LEFT if pos.x < size.x * 0.5 else TOP_RIGHT
		Art.draw_glow(self, pos, radius * size.x,
				side.lerp(Color(1.0, 0.96, 1.0), 0.72), alpha, 14)


## 가운데를 지르는 번개. 넓고 옅은 것 위에 좁고 흰 심을 겹쳐 가운데를 태운다.
func _draw_bolt() -> void:
	var center := size.x * 0.5
	var points := PackedVector2Array()
	for node: Vector2 in BOLT_NODES:
		points.append(Vector2(center + node.y * size.x, node.x * size.y))
	# 뒤에 옅은 빛무리를 깔아 번개가 배경을 밝히는 것으로 보이게 한다.
	# **꺾이는 지점에만 놓지 않는다** — 큰 빛무리 여덟 개면 이음선에 동그란 얼룩이
	# 여덟 개 생긴다. 선을 따라 촘촘히 나눠 작게 놓으면 한 줄기 빛으로 이어진다.
	for i in points.size() - 1:
		var from: Vector2 = points[i]
		var to: Vector2 = points[i + 1]
		for j in 6:
			var point := from.lerp(to, float(j) / 6.0)
			Art.draw_glow(self, point, 46.0, Color(1.0, 0.92, 1.0), 0.10, 10)
	draw_polyline(points, Color(0.98, 0.86, 1.0, 0.55), BOLT_WIDTH, true)
	draw_polyline(points, Color(1.0, 1.0, 1.0, 0.92), BOLT_WIDTH * BOLT_CORE, true)


## 밤하늘의 반짝임. 큰 것은 십자로 뻗고 작은 것은 점이다.
func _draw_stars() -> void:
	for star: Dictionary in _stars:
		var at: Vector2 = star["at"]
		var pos := Vector2(at.x * size.x, at.y * size.y)
		var alpha: float = star["alpha"]
		var radius: float = star["size"]
		var color := Color(1.0, 1.0, 1.0, alpha)
		if not star["sparkle"]:
			draw_circle(pos, radius, color)
			continue
		var reach: float = star["reach"]
		# 십자 두 줄을 끝으로 갈수록 투명해지는 삼각형 넷으로 그린다.
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var perp := direction.orthogonal() * radius * 0.7
			draw_polygon(
				PackedVector2Array([pos - perp, pos + perp, pos + direction * reach]),
				PackedColorArray([color, color, Color(1.0, 1.0, 1.0, 0.0)]))
		Art.draw_glow(self, pos, radius * 3.4, Color(1.0, 1.0, 1.0), alpha * 0.5, 10)


## 떠 있는 젤리 조각. 자기 쪽 편 색을 띠고 흰 반짝임이 하나 얹힌다.
func _draw_cubes() -> void:
	for cube: Dictionary in _cubes:
		var at: Vector2 = cube["at"]
		var pos := Vector2(at.x * size.x, at.y * size.y)
		var side := TOP_LEFT if pos.x < size.x * 0.5 else TOP_RIGHT
		var body := side.lerp(Color(1.0, 1.0, 1.0), 0.42)
		var half: float = cube["size"] * 0.5
		var alpha: float = cube["alpha"]
		var angle: float = cube["angle"]
		draw_set_transform(pos, angle, Vector2.ONE)
		draw_colored_polygon(_rounded_box(half, half * 0.34), Color(body, alpha))
		draw_colored_polygon(_rounded_box(half * 0.62, half * 0.24),
				Color(body.lerp(Color(1.0, 1.0, 1.0), 0.5), alpha * 0.75))
		# 왼쪽 위 모서리의 흰 빛 — 이것 하나로 딱딱한 네모가 젤리로 읽힌다.
		draw_circle(Vector2(-half * 0.38, -half * 0.4), half * 0.2,
				Color(1.0, 1.0, 1.0, alpha * 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 반지름이 `radius` 인 둥근 네모. 중심이 원점이고 한 변의 절반이 `half` 다.
func _rounded_box(half: float, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [
		Vector2(half - radius, half - radius),
		Vector2(-half + radius, half - radius),
		Vector2(-half + radius, -half + radius),
		Vector2(half - radius, -half + radius),
	]
	var steps := 4
	for i in corners.size():
		var corner: Vector2 = corners[i]
		var start := PI * 0.5 * float(i)
		for j in steps + 1:
			var a := start + PI * 0.5 * float(j) / float(steps)
			points.append(corner + Vector2(cos(a), sin(a)) * radius)
	return points


## 아래쪽 꽃밭. 물결치는 윤곽 위에 작은 꽃을 흩는다.
##
## **한 덩어리 다각형으로 그리지 않는다** — 윗변이 물결쳐서 오목한 다각형이 되는데,
## `draw_colored_polygon()` 은 볼록한 것을 전제로 삼각형을 나누므로 오목한 자리가
## 엉뚱하게 메워진다. 세로 띠로 잘라 그리면 조각마다 볼록해서 그럴 수 없다.
func _draw_ground() -> void:
	var base := size.y - GROUND_HEIGHT
	var outline := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var t := float(i) / float(steps)
		# 물결 두 개를 겹쳐 규칙적으로 보이지 않게 한다.
		var y := base + sin(t * TAU * 1.6) * 12.0 + sin(t * TAU * 3.7 + 1.2) * 6.0
		outline.append(Vector2(t * size.x, y))
	for i in steps:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[i + 1]
		draw_colored_polygon(
			PackedVector2Array([a, b, Vector2(b.x, size.y), Vector2(a.x, size.y)]),
			GROUND_COLOR)
	# 윤곽 바로 위에 밝은 줄을 얹어 풀이 빛을 받는 것으로 보이게 한다.
	draw_polyline(outline, GROUND_LIGHT, 4.0, true)
	_draw_flowers(base)


func _draw_flowers(base: float) -> void:
	var hues := [
		Color(1.0, 0.85, 0.35), Color(0.98, 0.55, 0.72),
		Color(0.55, 0.72, 1.0), Color(0.86, 0.70, 1.0),
	]
	for flower: Dictionary in _flowers:
		var at: Vector2 = flower["at"]
		var pos := Vector2(at.x * size.x, base + at.y * GROUND_HEIGHT)
		var radius: float = flower["size"]
		var color: Color = hues[flower["hue"]]
		# 꽃잎 넷과 가운데 점. 이 크기에서는 이것으로 꽃으로 읽힌다.
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_circle(pos + direction * radius * 0.8, radius * 0.62, color)
		draw_circle(pos, radius * 0.5, Color(1.0, 0.97, 0.85))


## 가운데의 `VS`. 두 글자를 따로 그려 왼쪽은 분홍, 오른쪽은 파랑으로 나눈다.
func _draw_vs() -> void:
	var center := Vector2(size.x * 0.5, VS_CENTER_Y)
	var v_width := FONT.get_string_size("V", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE).x
	var s_width := FONT.get_string_size("S", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE).x
	var total := v_width + s_width
	var baseline := center.y + VS_SIZE * 0.36
	var v_at := Vector2(center.x - total * 0.5, baseline)
	var s_at := Vector2(v_at.x + v_width, baseline)
	# 두 글자 뒤에 흰 빛무리를 깔아 번개에서 나온 것처럼 보이게 한다.
	Art.draw_glow(self, center, VS_SIZE * 1.1, Color(1.0, 0.95, 1.0), 0.3, 16)
	# 테두리를 흰색으로 둘러 어느 쪽 배경에서도 글자가 뜬다.
	# **테두리 둘을 먼저 다 두르고 속을 채운다** — 한 글자씩 테두리·속을 번갈아 그리면
	# 뒷 글자의 테두리가 앞 글자의 속을 덮는다(`V` 와 `S` 는 붙어 있다).
	draw_string_outline(FONT, v_at, "V", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE,
			VS_OUTLINE, VS_OUTLINE_COLOR)
	draw_string_outline(FONT, s_at, "S", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE,
			VS_OUTLINE, VS_OUTLINE_COLOR)
	draw_string(FONT, v_at, "V", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE, VS_LEFT_COLOR)
	draw_string(FONT, s_at, "S", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE, VS_RIGHT_COLOR)


## 맨 위 가운데의 `캐릭터 선택` 리본. 좌우가 접혀 들어간 띠에 글자를 얹는다.
func _draw_ribbon() -> void:
	var cx := size.x * 0.5
	var top := RIBBON_TOP
	var bottom := RIBBON_TOP + RIBBON_HEIGHT
	var mid := (top + bottom) * 0.5
	var body := PackedVector2Array([
		Vector2(cx - RIBBON_HALF, top),
		Vector2(cx + RIBBON_HALF, top),
		Vector2(cx + RIBBON_HALF - RIBBON_FOLD, mid),
		Vector2(cx + RIBBON_HALF, bottom),
		Vector2(cx - RIBBON_HALF, bottom),
		Vector2(cx - RIBBON_HALF + RIBBON_FOLD, mid),
	])
	draw_colored_polygon(body, RIBBON_COLOR)
	draw_polyline(body + PackedVector2Array([body[0]]), RIBBON_EDGE, 3.0, true)
	_draw_centered(RIBBON_TEXT, Vector2(cx, mid + RIBBON_SIZE * 0.36), RIBBON_SIZE,
			Color(1.0, 1.0, 1.0), 4, RIBBON_EDGE)
	# 글자 좌우의 작은 별. 목업의 리본에 있던 것이다.
	for direction: float in [-1.0, 1.0]:
		_draw_star(Vector2(cx + direction * (RIBBON_HALF - 26.0), mid), 8.0,
				Color(1.0, 0.86, 0.42))


## 오각별 하나. 리본 장식과 카드 배지가 같은 모양을 쓴다.
func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * float(i) / 5.0
		var r := radius if i % 2 == 0 else radius * 0.46
		points.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(points, color)


func _draw_centered(text: String, center: Vector2, font_size: int, color: Color,
		outline := 0, outline_color := Color(0, 0, 0, 0)) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var at := Vector2(center.x - width * 0.5, center.y)
	if outline > 0:
		draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
				outline, outline_color)
	draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
