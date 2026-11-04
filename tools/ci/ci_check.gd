extends Node
## CI 전용 검사 (#436). **게임에 들어가지 않는다** — `.github/workflows/godot-check.yml` 이
## 실행 직전에 `override.cfg` 를 만들어 이것을 오토로드로 붙이고, 그 파일은 저장소에 없다.
##
## 오토로드로 붙이는 이유: `--script` 로 돌리면 오토로드(`GameState`·`Sfx`)가 안 올라와서
## 그 이름을 쓰는 스크립트가 전부 "식별자를 찾지 못한다"고 헛짚는다 (CLAUDE.md 참고).
##
## 두 단계를 한 번의 실행에서 한다.
## 1. **전체 로드** — `scripts`·`scenes`·`resources` 의 파일을 전부 `ResourceLoader.load()` 한다.
##    타입 추론 실패(#66) 같은, 정적 확인으로는 안 보이는 컴파일 오류가 여기서 걸린다.
## 2. **한 경기 스모크** — title → select → main 으로 넘어가 두 사람의 무기를 고르고, 판이
##    열린 뒤 1P 를 죽여 2P 에게 점수가 들어가는지까지 사람 손 없이 돈다.
##
## 끝나면 `CI_RESULT ok` 또는 `CI_RESULT fail: <이유>` 를 찍고 종료 코드 0/1 로 나간다.
## 워크플로는 이 종료 코드와 출력의 `SCRIPT ERROR` 따위를 함께 본다.
##
## 로컬에서도 같은 것을 돌릴 수 있다 — 프로젝트 폴더에 아래 두 줄로 `override.cfg` 를 만들고
## `godot --headless --path .` 를 실행한 뒤, 끝나면 `override.cfg` 를 지운다.
##     [autoload]
##     CICheck="*res://tools/ci/ci_check.gd"

const LOAD_DIRS: Array[String] = ["res://scripts", "res://scenes", "res://resources"]
const LOAD_EXTS: Array[String] = ["gd", "tscn", "tres", "gdshader"]

## 이 시간 안에 끝나지 않으면 어딘가에서 멎은 것이다.
const TOTAL_TIMEOUT := 120.0
## 화면 하나가 뜨기를 기다리는 한도. 경기 표지(2초)·카운트다운(1.68초)이 끼어도 넉넉하다.
const STEP_TIMEOUT := 15.0

var _done := false


func _ready() -> void:
	get_tree().create_timer(TOTAL_TIMEOUT).timeout.connect(
		func() -> void: _finish(false, "전체 시간 초과 (%d초)" % int(TOTAL_TIMEOUT)))
	_run.call_deferred()


func _run() -> void:
	var failures := _load_all()
	if failures > 0:
		_finish(false, "로드 실패 %d개" % failures)
		return
	var reason: String = await _smoke()
	if _done:
		return
	_finish(reason == "", reason)


# --- 1. 전체 로드 ---------------------------------------------------------------

func _load_all() -> int:
	var files: Array[String] = []
	for dir in LOAD_DIRS:
		_collect(dir, files)
	var failures := 0
	for path in files:
		var res := ResourceLoader.load(path)
		# 컴파일에 실패한 스크립트도 `load()` 는 null 이 아닌 빈 껍데기를 돌려준다 —
		# `can_instantiate()` 가 false 인 것으로만 알 수 있다.
		var script := res as Script
		if res == null or (script != null and not script.can_instantiate()):
			failures += 1
			print("CI_LOAD fail: %s" % path)
	print("CI_LOAD files=%d failures=%d" % [files.size(), failures])
	return failures


func _collect(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for sub in da.get_directories():
		_collect(dir.path_join(sub), out)
	for file in da.get_files():
		if file.get_extension() in LOAD_EXTS:
			out.append(dir.path_join(file))


# --- 2. 한 경기 스모크 ------------------------------------------------------------

## 실패 이유를 돌려준다. 빈 문자열이면 통과다.
func _smoke() -> String:
	var title: Node = await _wait_scene("res://scenes/title.tscn")
	if title == null:
		return "title 화면이 뜨지 않았다"
	title._on_start_pressed()

	var select: Node = await _wait_scene("res://scenes/select.tscn")
	if select == null:
		return "select 화면이 뜨지 않았다"
	select._on_go_pressed()

	var main: Node = await _wait_scene("res://scenes/main.tscn")
	if main == null:
		return "main 화면이 뜨지 않았다"

	# 1P → 2P 차례로 고른다.
	var pick: Node = main.get_node("UI/HUD/WeaponPick")
	for player_id in GameState.PLAYER_IDS:
		if not await _wait_until(func() -> bool: return pick._armed and pick._picker == player_id):
			return "%dP 무기 선택 카드가 열리지 않았다" % player_id
		pick._on_card_pressed(0)
	print("CI_SMOKE weapons picked")

	# 카운트다운이 끝나 판이 열린다 — 얼음이 풀리면 싸울 수 있는 상태다.
	var p1: Node = main.get_player(1)
	var p2: Node = main.get_player(2)
	if p1 == null or p2 == null:
		return "젤리가 세워지지 않았다"
	if not await _wait_until(func() -> bool: return not p1.frozen and not p2.frozen):
		return "카운트다운 뒤에도 젤리가 얼어 있다"
	print("CI_SMOKE round open")

	# 잠깐 싸우는 틱을 돌린다 (근접 판정·자동 발사가 이 사이에 돈다).
	await get_tree().create_timer(1.0).timeout

	p1.kill()
	if not await _wait_until(func() -> bool: return int(main.scores.get(2, 0)) == 1):
		return "1P 가 죽었는데 2P 점수가 오르지 않았다 (scores=%s)" % str(main.scores)
	print("CI_SMOKE point scored")
	return ""


func _wait_scene(path: String) -> Node:
	var ok: bool = await _wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == path and scene.is_node_ready())
	return get_tree().current_scene if ok else null


func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _done:
			return false
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _finish(ok: bool, reason: String) -> void:
	if _done:
		return
	_done = true
	print("CI_RESULT ok" if ok else "CI_RESULT fail: %s" % reason)
	# 씬을 갈아타는 도중일 수 있으므로 한 프레임 미룬다.
	get_tree().quit.call_deferred(0 if ok else 1)
