extends Node
## 성능 측정기 (#501). **게임에 들어가지 않는다** — `tools/ci/ci_check.gd` 처럼 `override.cfg` 로
## 오토로드에 붙여 돌리고, 끝나면 그 파일을 지운다:
##     [autoload]
##     PerfProbe="*res://tools/perf_probe.gd"
##
##     [display]
##     window/vsync/vsync_mode=0
##
##     [application]
##     run/max_fps=0
## 렌더링까지 재야 하므로 **창을 띄워** 돌린다(`Godot --path . --resolution 1600x720`).
## vsync 를 끄는 것은 프레임 시간이 화면 주기(16.7ms)에 묶이지 않고 실제 일한 만큼 나오게 하려는 것이다.
##
## 모드 (환경 변수 `PROBE_MODE`):
## - 없음: 사람 손 없이 한 경기를 돌리며(이동·점프·궁극기 연타) 구간별 프레임 시간을 표로 찍고,
##   25ms 넘는 프레임은 따로 찍는다. `PROBE_TOUCH=1` 이면 PC 에서도 터치 조작물을 띄운다.
## - `parts`: 무기·젤리 그림, 곡, 맵, 씬을 하나씩 읽어 걸리는 시간을 찍는다.
## - `rects`: `ArtRects` 표의 여백과 실제로 잰 여백을 대조한다(`gen_art_rects.gd` 를 다시 돌린 뒤 확인).

const FIGHT_TIME := 9.0
const ROUNDS := 6

var _phase := "boot"
## 구간 → {n: 프레임 수, sf/mf: 프레임 시간 합/최대, sd/md: 그리기 호출 합/최대, mn: 노드 최대, slow, frames}
var _stats := {}
var _last_us := 0
var _done := false
var _main: Node


func _ready() -> void:
	process_priority = 1000
	_last_us = Time.get_ticks_usec()
	get_tree().create_timer(400.0).timeout.connect(func() -> void: _finish())
	_run.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if _phase == "boot":
		return
	var s: Dictionary = _stats.get(_phase, {})
	if s.is_empty():
		s = {"n": 0, "sf": 0.0, "mf": 0.0, "sd": 0.0, "md": 0.0, "mn": 0, "slow": 0, "frames": []}
		_stats[_phase] = s
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	s.n += 1
	s.sf += frame_ms
	s.mf = maxf(s.mf, frame_ms)
	s.sd += draws
	s.md = maxf(s.md, draws)
	s.mn = maxi(s.mn, nodes)
	(s.frames as Array).append(frame_ms)
	if frame_ms > 25.0:
		print("PROBE slow frame %.1fms in %s at %d" % [frame_ms, _phase, Time.get_ticks_msec()])
	if frame_ms > 16.7:
		s.slow += 1


func _compare_rects() -> void:
	await get_tree().process_frame
	var worst := 0.0
	for path: String in ArtRects.RECTS:
		var tex: Texture2D = load(path)
		var a := Art._table_rect(tex)
		var b := Art._measure_content(tex)
		var d := maxf(maxf(absf(a.position.x - b.position.x), absf(a.position.y - b.position.y)),
			maxf(absf(a.end.x - b.end.x), absf(a.end.y - b.end.y)))
		worst = maxf(worst, d)
		if d > 1.0:
			print("RECT diff %s table=%s measured=%s" % [path, a, b])
	print("RECT compared=%d worst_px=%.2f" % [ArtRects.RECTS.size(), worst])
	get_tree().quit()


func _parts() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var preloader := get_node_or_null("/root/Preloader")
	if preloader != null:
		var t0 := Time.get_ticks_msec()
		await _wait_until(func() -> bool: return preloader.is_done())
		print("PART preload finished in %d ms" % (Time.get_ticks_msec() - t0))
	var t := Time.get_ticks_usec()
	var tl := 0.0
	var tm := 0.0
	var count := 0
	for w in Weapons.names():
		var t0 := Time.get_ticks_usec()
		var texs := Weapons.all_textures(w)
		var t1 := Time.get_ticks_usec()
		for tex: Texture2D in texs:
			Art._measure_content(tex)
			count += 1
		var t2 := Time.get_ticks_usec()
		tl += (t1 - t0) / 1000.0
		tm += (t2 - t1) / 1000.0
		print("PART weapon %s load=%.1fms measure=%.1fms n=%d" % [w, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, texs.size()])
	print("PART weapons total load=%.1fms measure=%.1fms textures=%d" % [tl, tm, count])
	for c in Characters.names():
		for pose in [Characters.POSE_IDLE, Characters.POSE_WIN, Characters.POSE_LOSE]:
			var t0 := Time.get_ticks_usec()
			var tex := Characters.pose_texture(c, pose)
			var t1 := Time.get_ticks_usec()
			Art._measure_content(tex)
			var t2 := Time.get_ticks_usec()
			print("PART char %s/%s load=%.1fms measure=%.1fms size=%s" % [c, pose, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, tex.get_size()])
	for f in DirAccess.get_files_at("res://assets/music"):
		if f.ends_with(".ogg"):
			var t0 := Time.get_ticks_usec()
			var s = load("res://assets/music/" + f)
			print("PART music %s load=%.1fms" % [f, (Time.get_ticks_usec() - t0) / 1000.0])
	for m in Maps.names():
		var t0 := Time.get_ticks_usec()
		var ps := Maps.scene(m)
		var t1 := Time.get_ticks_usec()
		var inst := ps.instantiate()
		add_child(inst)
		var t2 := Time.get_ticks_usec()
		await get_tree().process_frame
		var t3 := Time.get_ticks_usec()
		inst.queue_free()
		print("PART map %s load=%.1fms inst+add=%.1fms next_frame=%.1fms" % [m, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
	for sc in ["res://scenes/select.tscn", "res://scenes/main.tscn"]:
		var t0 := Time.get_ticks_usec()
		var ps: PackedScene = load(sc)
		print("PART scene %s load=%.1fms" % [sc, (Time.get_ticks_usec() - t0) / 1000.0])
	get_tree().quit()


func _run() -> void:
	if OS.get_environment("PROBE_MODE") == "parts":
		await _parts()
		return
	if OS.get_environment("PROBE_MODE") == "rects":
		await _compare_rects()
		return
	var title: Node = await _wait_scene("res://scenes/title.tscn")
	_phase = "title"
	var preloader := get_node_or_null("/root/Preloader")
	if preloader != null:
		var t0 := Time.get_ticks_msec()
		await _wait_until(func() -> bool: return preloader.is_done())
		print("PROBE preload finished in %d ms" % (Time.get_ticks_msec() - t0))
	else:
		await get_tree().create_timer(1.0).timeout
	title._on_start_pressed()
	var select: Node = await _wait_scene("res://scenes/select.tscn")
	_phase = "select"
	await get_tree().create_timer(1.0).timeout
	if preloader != null:
		var t1 := Time.get_ticks_msec()
		await _wait_until(func() -> bool: return preloader.is_done())
		print("PROBE main.tscn background load done %d ms after 1s on select" % (Time.get_ticks_msec() - t1))
	var tg := Time.get_ticks_usec()
	var ps: PackedScene = load("res://scenes/main.tscn")
	var tl := Time.get_ticks_usec()
	var inst := ps.instantiate()
	var ti := Time.get_ticks_usec()
	inst.free()
	print("PROBE main.tscn load()=%.1fms instantiate=%.1fms" % [(tl - tg) / 1000.0, (ti - tl) / 1000.0])
	_phase = "go-press"
	select._on_go_pressed()
	_main = await _wait_scene("res://scenes/main.tscn")
	var touch: Control = _main.get_node_or_null("UI/TouchControls")
	if touch == null:
		touch = _main.find_child("TouchControls", true, false)
	if touch != null and OS.get_environment("PROBE_TOUCH") == "1":
		touch.show()
	var pick: Node = _main.get_node("UI/HUD/WeaponPick")
	for r in ROUNDS:
		if not _main_alive():
			break
		_phase = "pick r%d" % r
		for player_id in GameState.PLAYER_IDS:
			if not await _wait_until(func() -> bool: return _main_alive() and pick._armed and pick._picker == player_id):
				print("PROBE pick never opened r=%d" % r)
				_finish()
				return
			await get_tree().create_timer(0.6).timeout
			pick._on_card_pressed((r + player_id) % 3)
		var p1: Node = _main.get_player(1)
		var p2: Node = _main.get_player(2)
		_phase = "countdown"
		await _wait_until(func() -> bool: return not p1.frozen and not p2.frozen)
		_phase = "fight %s vs %s" % [p1.weapon_id, p2.weapon_id]
		await _fight(p1, p2)
		_release_all()
		if not _main_alive():
			break
		_phase = "point"
		if p1.alive and p2.alive:
			(p1 if r % 2 == 0 else p2).kill()
		if int(_main.scores.get(1, 0)) >= 3 or int(_main.scores.get(2, 0)) >= 3:
			_phase = "result"
			await get_tree().create_timer(4.5).timeout
			break
	_finish()


func _main_alive() -> bool:
	return is_instance_valid(_main) and get_tree().current_scene == _main


func _fight(p1: Node, p2: Node) -> void:
	var t := 0.0
	var step := 0
	while t < FIGHT_TIME:
		if not _main_alive() or not is_instance_valid(p1) or not is_instance_valid(p2):
			return
		if not p1.alive or not p2.alive:
			return
		for pid in [1, 2]:
			var me: Node = p1 if pid == 1 else p2
			var other: Node = p2 if pid == 1 else p1
			var dir := "right" if other.global_position.x > me.global_position.x else "left"
			var away := "left" if dir == "right" else "right"
			Input.action_release(GameState.action(pid, away))
			Input.action_press(GameState.action(pid, dir))
			if step % 40 == pid * 7:
				Input.action_press(GameState.action(pid, "jump"))
			elif step % 40 == pid * 7 + 3:
				Input.action_release(GameState.action(pid, "jump"))
			if step % 30 == pid * 5:
				Input.action_press(GameState.action(pid, "skill"))
			elif step % 30 == pid * 5 + 4:
				Input.action_release(GameState.action(pid, "skill"))
		await get_tree().physics_frame
		t += 1.0 / 60.0
		step += 1


func _release_all() -> void:
	for pid in [1, 2]:
		for a in ["left", "right", "jump", "skill", "fast_fall"]:
			Input.action_release(GameState.action(pid, a))


func _wait_scene(path: String) -> Node:
	await _wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == path and scene.is_node_ready())
	return get_tree().current_scene


func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _finish() -> void:
	if _done:
		return
	_done = true
	print("PROBE phase | frames | avg_ms | p95_ms | max_ms | draws_avg/max | nodes_max | >16.7ms")
	for phase in _stats:
		var s: Dictionary = _stats[phase]
		var n: int = s.n
		var fr: Array = s.frames
		fr.sort()
		var p95: float = fr[int(fr.size() * 0.95)] if fr.size() > 0 else 0.0
		print("PROBE %s | %d | %.2f | %.2f | %.2f | %.0f/%.0f | %d | %d" % [
			phase, n, s.sf / n, p95, s.mf, s.sd / n, s.md, s.mn, s.slow])
	get_tree().quit.call_deferred(0)
