extends Node3D
const Sfx = preload("res://scripts/sfx.gd")
## 入口：模式选择（单人 / 三人），选中后切换成对应的 3D 场景。

const MODE_SINGLE := 0
const MODE_THREE := 1

var current: Node3D
var camera: Camera3D
var buttons: Array = []
var _hovered := -1
var labels: Array = []


func _ready() -> void:
	rng_seed()

	var args := OS.get_cmdline_user_args()
	var mode := ""
	var seat := -1
	var test3p := false
	var state_arg := ""
	var shot_delay := 0.9
	for a in args:
		if a.begins_with("--mode="):
			mode = a.split("=")[1]
		elif a.begins_with("--seat="):
			seat = int(a.split("=")[1])
		elif a == "--test3p":
			test3p = true
		elif a.begins_with("--state="):
			state_arg = a.split("=")[1]
		elif a.begins_with("--shot-delay="):
			shot_delay = float(a.split("=")[1])

	if mode == "single":
		_start_mode(MODE_SINGLE)
		if state_arg == "end" and current != null and current.has_method("force_end"):
			current.force_end()
		elif state_arg == "victory" and current != null and current.has_method("force_record"):
			current.force_record()
		elif state_arg == "punish" and current != null and current.has_method("force_punish"):
			current.force_punish()
		elif state_arg == "round3" and current != null and current.has_method("force_third_round"):
			current.force_third_round()
		elif state_arg == "click3" and current != null and current.has_method("verify_buttons"):
			current.verify_buttons()
		elif state_arg == "round2" and current != null and current.has_method("force_second_round"):
			current.force_second_round()
		elif state_arg == "wait" and current != null and current.has_method("force_wait"):
			current.force_wait()
	elif mode == "3p":
		_start_mode(MODE_THREE, seat)
		if state_arg == "end" and current != null and current.has_method("force_end"):
			current.force_end()
		elif state_arg == "victory" and current != null and current.has_method("force_record"):
			current.force_record()
		elif state_arg == "punish" and current != null and current.has_method("force_punish"):
			current.force_punish()
		elif state_arg == "round3" and current != null and current.has_method("force_third_round"):
			current.force_third_round()
		elif state_arg == "round2" and current != null and current.has_method("force_second_round"):
			current.force_second_round()
		elif state_arg == "wait" and current != null and current.has_method("force_wait"):
			current.force_wait()
		if test3p and current != null and current.has_method("run_test"):
			current.run_test()
			get_tree().quit()
			return
	else:
		_build_menu()
	_play_menu_theme()

	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		await get_tree().process_frame
		if "--test" in args and current != null and current.has_method("_selftest"):
			current._selftest()
			return
		print("[ROOT] headless 启动正常，当前场景：", "菜单" if current == null else current.name)
		get_tree().quit()
	elif "--shot" in args:
		await get_tree().create_timer(shot_delay).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shot.png")
		print("[ROOT] 截图已保存到 res://shot.png")
		get_tree().quit()


func rng_seed() -> void:
	seed(Time.get_ticks_usec())


# ---------------- 菜单 ----------------

func _play_menu_theme() -> void:
	await get_tree().create_timer(0.35).timeout
	if is_inside_tree() and current == null:
		Sfx.play(self, "round", -16.0)


func _build_menu() -> void:
	_build_world()
	_build_floor()

	camera = Camera3D.new()
	camera.position = Vector3(0, 2.35, 4.15)
	camera.rotation_degrees = Vector3(-22, 0, 0)
	camera.fov = 50
	add_child(camera)

	# 牌子
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 0.06, 1.5)
	board.mesh = box
	board.position = Vector3(0, 0.72, 0.2)
	board.material_override = _mat(Color(0.08, 0.20, 0.15), 0.6, 0.2)
	add_child(board)

	_label("五 张 牌", Vector3(0, 2.10, 0.1), 96, Color(0.95, 0.90, 0.78), false)
	_label("选 择 模 式", Vector3(0, 1.74, 0.1), 34, Color(0.70, 0.72, 0.64), false)

	_add_button("res://assets/ui/btn_single.png", Vector3(-0.64, 0.95, 0.45), MODE_SINGLE)
	_add_button("res://assets/ui/btn_multi.png", Vector3(0.64, 0.95, 0.45), MODE_THREE)


func _add_button(tex_path: String, pos: Vector3, mode: int) -> void:
	var spr := Sprite3D.new()
	spr.texture = load(tex_path)
	spr.pixel_size = 0.00165          # 640px 宽 → 1.056 世界单位
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.no_depth_test = true
	spr.render_priority = 6
	spr.position = pos
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.shaded = false
	spr.transparent = true
	spr.alpha_cut = Sprite3D.ALPHA_CUT_DISCARD
	spr.modulate = Color(1.25, 1.25, 1.25)
	add_child(spr)
	buttons.append({"node": spr, "mode": mode})


func _process(delta: float) -> void:
	if current != null or camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var hit := -1
	for idx in buttons.size():
		var node: Node3D = buttons[idx]["node"]
		var sp := camera.unproject_position(node.global_position)
		var near := sp.distance_to(mouse) <= 150.0
		var target := Vector3.ONE * (1.08 if near else 1.0)
		node.scale = node.scale.lerp(target, clampf(delta * 12.0, 0.0, 1.0))
		if near:
			hit = idx
	if hit != _hovered:
		_hovered = hit
		if hit >= 0:
			Sfx.play(self, "hover", -14.0)

func _unhandled_input(event: InputEvent) -> void:
	if current != null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for b in buttons:
		var sp := camera.unproject_position(b["node"].global_position)
		if sp.distance_to(mb.position) <= 150.0:
			Sfx.play(self, "click", -6.0)
			_start_mode(int(b["mode"]))
			return


func _start_mode(mode: int, seat := -1) -> void:
	for c in get_children():
		c.queue_free()
	buttons.clear()
	labels.clear()
	camera = null
	current = null

	var path := "res://scripts/game_single.gd" if mode == MODE_SINGLE else "res://scripts/game_3p.gd"
	var script: Script = load(path)
	var node: Node3D = script.new()
	node.name = "Single" if mode == MODE_SINGLE else "ThreePlayers"
	add_child(node)
	current = node

	if seat >= 0 and node.has_method("focus_seat"):
		node.focus_seat(seat)


# ---------------- 公共 ----------------

func _build_world() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.44, 0.50)
	env.ambient_light_energy = 0.95
	env.glow_enabled = true
	world.environment = env
	add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -30, 0)
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.96, 0.88)
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 160, 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.55, 0.68, 0.92)
	add_child(rim)


func _build_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(22, 22)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -0.02, 0)
	floor_mesh.material_override = _mat(Color(0.04, 0.04, 0.055), 0.95, 0.0)
	add_child(floor_mesh)


func _label(text: String, pos: Vector3, size: int, color: Color, flat := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0032
	l.modulate = color
	l.position = pos
	if flat:
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
	add_child(l)
	return l


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m
