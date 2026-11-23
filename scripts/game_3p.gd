extends Node3D
const CutsceneKit = preload("res://scripts/cutscene.gd")
const ScoreStore = preload("res://scripts/score_store.gd")
const RigHelper = preload("res://scripts/rig_helper.gd")
const Poker = preload("res://scripts/poker.gd")
const Sfx = preload("res://scripts/sfx.gd")
## 五张牌 · 圆桌三人（3D）—— 由 root.gd 挂载
##
## 三张椅子围圆桌摆成 120°，镜头站在当前玩家的椅子后面。
## 轮到谁，谁的手牌才亮；结算后镜头自动转到下一位。
##
## 场景全部代码生成。

const BASE_POINTS := 40
const PUNISH_THRESHOLD := 100
const REPLACE_COST := 2
const MAX_ROUNDS := 3

const MODEL_FBX := "res://assets/model_rigged.fbx"
const MODEL_FBX_OLD := "res://assets/model.fbx"
const MODEL_PATH := "res://assets/model.glb"
const CHARACTER_HEIGHT := 1.48

const TABLE_RADIUS := 2.15
const TABLE_TOP := 0.62
const SEAT_ANGLES := [0.0, 120.0, 240.0]
const HAND_Z := 1.30
const CAM_RADIUS := 5.15
const CAM_HEIGHT := 3.10

var rng := RandomNumberGenerator.new()

var camera: Camera3D
var cam_pivot: Node3D
var hands: Array = []          # 每个玩家一组：{group, cards, labels, score_label, name_label, btn, btn_label}
var players: Array = []        # {name, values, used, points, settled, score}
var active := 0
var deck: Array = []          # 本轮共用的牌堆
var first_seat := 0        # 每轮轮换先手
var round := 1
var all_settled := false
var best := 0
var phase := "play"
var cutscene_active := false          # play / round_end / punish / game_end
var end_button: MeshInstance3D
var end_label: Label3D

var characters: Array = []
var character_roots: Array = []
var back_material: StandardMaterial3D


func _get_back_material() -> StandardMaterial3D:
	if back_material == null:
		back_material = StandardMaterial3D.new()
		back_material.albedo_texture = load("res://assets/ui/card_back.png")
		back_material.roughness = 0.55
		back_material.metallic = 0.05
	return back_material
var character_base_y: Array = []
var skels: Array = []
var idle_time := 0.0
var nod_times: Array = [-1.0, -1.0, -1.0]
var _dots_dbg := false
var nod_time := -1.0

var tip_label: Label3D
var round_label: Label3D
var best_label: Label3D


func _ready() -> void:
	rng.randomize()
	_build_environment()
	_build_table()
	_build_floor()
	_build_camera_rig()
	_build_seats()
	_build_character_slot()
	_load_characters()
	best = ScoreStore.get_best()
	print("[3P] 最高分（存档）=", best)
	if best_label != null:
		best_label.text = "最高分 %d" % best
	_new_round()



# ---------------- 场景 ----------------

func _build_environment() -> void:
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

	var spot := OmniLight3D.new()
	spot.position = Vector3(0, 3.2, 0)
	spot.light_energy = 1.1
	spot.omni_range = 6.0
	spot.light_color = Color(1.0, 0.90, 0.75)
	add_child(spot)


func _build_table() -> void:
	var table := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = TABLE_RADIUS
	cyl.bottom_radius = TABLE_RADIUS
	cyl.height = 0.16
	cyl.radial_segments = 64
	table.mesh = cyl
	table.position = Vector3(0, TABLE_TOP - 0.08, 0)
	table.material_override = _mat(Color(0.08, 0.20, 0.15), 0.6, 0.2)
	add_child(table)

	var rim_mesh := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = TABLE_RADIUS - 0.03
	ring.outer_radius = TABLE_RADIUS + 0.03
	rim_mesh.mesh = ring
	rim_mesh.position = Vector3(0, TABLE_TOP - 0.02, 0)
	rim_mesh.material_override = _mat(Color(0.55, 0.45, 0.25), 0.35, 0.7)
	add_child(rim_mesh)


func _build_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(22, 22)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -0.02, 0)
	floor_mesh.material_override = _mat(Color(0.04, 0.04, 0.055), 0.95, 0.0)
	add_child(floor_mesh)


func _build_camera_rig() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0, TABLE_TOP + 0.15, 0)
	add_child(cam_pivot)

	camera = Camera3D.new()
	camera.name = "Cam"
	# 第一人称：站在当前玩家座位后面，镜头略高于桌面
	camera.position = Vector3(0, 2.95, 4.30)
	camera.rotation_degrees = Vector3(-31, 0, 0)
	camera.fov = 52
	cam_pivot.add_child(camera)


func _build_seats() -> void:
	players.clear()
	hands.clear()

	for i in 3:
		var deg: float = SEAT_ANGLES[i]
		var a := deg_to_rad(deg)

		var group := Node3D.new()
		group.rotation.y = a
		add_child(group)

		var data := {
			"name": "玩家 %d" % (i + 1),
			"slots": [],
			"used": [],
			"points": BASE_POINTS,
			"round": 1,
			"settled": false,
			"score": 0,
		}
		players.append(data)

		var entry := {"group": group, "cards": [], "labels": [], "backs": [], "buttons": []}

		# 椅子（0 号位在镜头与桌子之间，不放椅子）
		var chair := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.9, 0.08, 0.7)
		chair.mesh = cbox
		chair.position = Vector3(0, 0.46, 2.95)
		chair.material_override = _mat(Color(0.10, 0.10, 0.13), 0.8, 0.0)
		group.add_child(chair)

		var back := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(0.95, 0.85, 0.08)
		back.mesh = bbox
		back.position = Vector3(0, 0.9, 3.30)
		back.material_override = _mat(Color(0.10, 0.10, 0.13), 0.8, 0.0)
		group.add_child(back)

		# 五张牌
		for k in 5:
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.52, 0.012, 0.74)
			mi.mesh = mesh
			mi.position = Vector3((k - 2) * 0.58, TABLE_TOP + 0.01, HAND_Z)
			mi.rotation.y = -(k - 2) * 0.06
			mi.material_override = _mat(Color(0.92, 0.90, 0.84), 0.35, 0.05)
			group.add_child(mi)
			entry.cards.append(mi)

			var label := Label3D.new()
			label.font_size = 84
			label.pixel_size = 0.0032
			label.rotation_degrees = Vector3(-90, 0, 0)
			label.position = mi.position + Vector3(0, 0.014, 0)
			group.add_child(label)
			entry.labels.append(label)

			# 牌背：贴在牌面上的薄片，正面朝上
			var back_quad := MeshInstance3D.new()
			var bq := QuadMesh.new()
			bq.size = Vector2(0.52, 0.74)
			back_quad.mesh = bq
			back_quad.rotation_degrees = Vector3(-90, 0, 0)
			back_quad.position = mi.position + Vector3(0, 0.020, 0)
			back_quad.material_override = _get_back_material()
			back_quad.visible = false
			group.add_child(back_quad)
			entry.backs.append(back_quad)

		# 名字 / 分数
		var name_label := _label_in(group, data["name"], Vector3(0, TABLE_TOP + 0.02, 1.95), 34, Color(0.86, 0.82, 0.72))
		entry.name_label = name_label
		var score_label := _label_in(group, "", Vector3(0, TABLE_TOP + 0.02, 0.55), 60, Color(1.0, 0.85, 0.45))
		entry.score_label = score_label

		# 结算完就冒出来的「等待」点点
		var dots := Label3D.new()
		dots.text = "等 待 中"
		dots.font_size = 64
		dots.pixel_size = 0.0032
		dots.position = Vector3(0, TABLE_TOP + 1.35, 1.45)
		dots.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dots.no_depth_test = true
		dots.modulate = Color(0.92, 0.86, 0.62)
		dots.visible = false
		group.add_child(dots)
		entry.dots = dots

		# 结束回合按钮
		var btn := MeshInstance3D.new()
		var btn_mesh := BoxMesh.new()
		btn_mesh.size = Vector3(0.82, 0.05, 0.30)
		btn.mesh = btn_mesh
		btn.position = Vector3(-0.55, TABLE_TOP + 0.03, 2.15)
		btn.material_override = _mat(Color(0.92, 0.82, 0.52), 0.3, 0.1)
		group.add_child(btn)
		entry.btn = btn
		entry.btn_label = _label_in(group, "结 算", Vector3(-0.55, TABLE_TOP + 0.062, 2.15), 30, Color(0.06, 0.06, 0.08))

		hands.append(entry)

	# 轮间按钮：放桌心，任何座位都看得到
	end_button = MeshInstance3D.new()
	var eb := BoxMesh.new()
	eb.size = Vector3(1.15, 0.05, 0.38)
	end_button.mesh = eb
	end_button.position = Vector3(0, TABLE_TOP + 0.04, 0.0)
	end_button.material_override = _mat(Color(0.95, 0.78, 0.35), 0.3, 0.15)
	end_button.visible = false
	add_child(end_button)

	end_label = Label3D.new()
	end_label.text = "下 一 轮"
	end_label.font_size = 44
	end_label.pixel_size = 0.0032
	end_label.position = Vector3(0, TABLE_TOP + 0.45, 0.0)
	end_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	end_label.no_depth_test = true
	end_label.modulate = Color(1.0, 0.92, 0.70)
	end_label.visible = false
	add_child(end_label)

	# HUD：挂在相机上，镜头转到哪都在画面里
	best_label = _hud("最高分 0", Vector3(-0.95, 0.62, -2.6), 26, Color(0.78, 0.86, 0.82))
	round_label = _hud("第 1/%d 轮" % MAX_ROUNDS, Vector3(0, 0.62, -2.6), 30, Color(0.92, 0.88, 0.76))
	tip_label = _hud("", Vector3(0, -0.95, -2.6), 30, Color(0.95, 0.90, 0.72))


func _hud(text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0016
	l.modulate = color
	l.position = pos
	l.no_depth_test = true
	l.render_priority = 20
	camera.add_child(l)
	return l


func _label_in(parent: Node3D, text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0032
	l.modulate = color
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	parent.add_child(l)
	return l


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


# ---------------- 角色 ----------------

func _load_one_character(seat: int) -> void:
	var character: Node3D = null
	if ResourceLoader.exists(MODEL_FBX):
		var packed = load(MODEL_FBX)
		if packed is PackedScene:
			character = (packed as PackedScene).instantiate()
			_place_one_character(character, seat)
			return

	if FileAccess.file_exists(MODEL_FBX):
		var fdoc = FBXDocument.new()
		var fstate = FBXState.new()
		if fdoc.append_from_file(MODEL_FBX, fstate) == OK:
			character = fdoc.generate_scene(fstate)
			if character != null:
				_place_one_character(character, seat)
				return
		push_warning("FBX 读取失败")
	_spawn_placeholder(seat)


func _place_one_character(character: Node3D, seat: int) -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.70, 0.76, 0.80) if seat == 0 else Color(0.78, 0.74, 0.70)
	skin.roughness = 0.72
	skin.metallic = 0.0
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_material(character, skin)

	var size := _local_size(character)
	var height: float = maxf(size.y, size.z)
	var sc: float = CHARACTER_HEIGHT / maxf(height, 0.001)

	character.scale = Vector3.ONE * sc
	character.position = Vector3.ZERO
	character_roots[seat].add_child(character)
	characters.append(character)

	var skel := RigHelper.find_skeleton(character)
	skels.append(skel)
	print("[3P] 座位 %d 角色就位（骨骼=%s）" % [seat + 1, "有" if skel != null else "无"])


func _idle_hands(delta: float) -> void:
	if hands.size() != 3:
		return
	if cutscene_active:
		for e in hands:
			e.dots.visible = false
		return
	for i in 3:
		var p = players[i]
		var e = hands[i]
		var settled: bool = p["settled"]
		for k in 5:
			var mi: MeshInstance3D = e.cards[k]
			if settled:
				# 收牌：向中间并拢、摆正
				mi.position.x = lerpf(mi.position.x, 0.0, delta * 4.0)
				mi.position.z = lerpf(mi.position.z, HAND_Z, delta * 4.0)
				mi.position.y = lerpf(mi.position.y, TABLE_TOP + 0.014 + k * 0.010, delta * 4.0)
				mi.rotation.y = lerpf(mi.rotation.y, 0.0, delta * 4.0)
			elif i != active:
				# 干等着：轻微上下浮
				mi.position.y = TABLE_TOP + 0.01 + sin(idle_time * 1.6 + k * 0.7) * 0.012
			else:
				mi.position.y = TABLE_TOP + 0.01

			var lb: Label3D = e.labels[k]
			lb.position = mi.position + Vector3(0, 0.014, 0)

		var dots: Label3D = e.dots
		dots.visible = settled
		if settled:
			dots.position.y = TABLE_TOP + 1.35 + sin(idle_time * 2.2 + i) * 0.06


func _reset_hand(i: int) -> void:
	var e = hands[i]
	for k in 5:
		var mi: MeshInstance3D = e.cards[k]
		mi.position = Vector3((k - 2) * 0.58, TABLE_TOP + 0.01, HAND_Z)
		mi.rotation.y = -(k - 2) * 0.06
		mi.material_override = _mat(Color(0.92, 0.90, 0.84), 0.35, 0.05)
		e.labels[k].position = mi.position + Vector3(0, 0.014, 0)
	e.dots.visible = false


func _spawn_placeholder(seat: int) -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.26
	cap.height = 1.1
	body.mesh = cap
	body.position = Vector3(0, 0.55, 0)
	body.material_override = _mat(Color(0.55, 0.66, 0.72), 0.7, 0.0)
	character_roots[seat].add_child(body)

	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.27
	sph.height = 0.54
	head.mesh = sph
	head.position = Vector3(0, 1.28, 0)
	head.material_override = _mat(Color(0.62, 0.72, 0.78), 0.65, 0.0)
	character_roots[seat].add_child(head)


func _apply_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_material(child, mat)


func _local_size(node: Node) -> Vector3:
	var box := AABB()
	var has := false
	for mi in _mesh_instances(node):
		var b: AABB = mi.get_aabb()
		box = b if not has else box.merge(b)
		has = true
	return box.size if has else Vector3.ONE


func _mesh_instances(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_mesh_instances(c, out)
	return out


func _build_character_slot() -> void:
	character_roots.clear()
	nod_times = [-1.0, -1.0, -1.0]
	for i in 3:
		var a := deg_to_rad(SEAT_ANGLES[i])
		var root := Node3D.new()
		root.name = "SeatChar%d" % (i + 1)
		# 站在椅子外侧、往旁边偏一点，别挡在镜头和桌面之间
		var forward := Vector3(sin(a), 0, cos(a))
		var side := Vector3(cos(a), 0, -sin(a))
		root.position = forward * 3.05 + side * 0.55
		root.rotation.y = a + PI
		add_child(root)
		character_roots.append(root)
		character_base_y.append(a + PI)


func _load_characters() -> void:
	for i in 3:
		_load_one_character(i)


func _process(delta: float) -> void:
	_idle_hands(delta)
	idle_time += delta

	# 等待人数（用于“往前探身”）
	var settled_count := 0
	for pl in players:
		if pl["settled"]:
			settled_count += 1
	var waiting := phase == "play" and settled_count > 0

	for i in character_roots.size():
		var root: Node3D = character_roots[i]
		var ph := float(i) * 1.7

		# 呼吸：上下浮 + 轻微压扁
		root.position.y = sin(idle_time * 1.7 + ph) * 0.035
		root.scale = Vector3(1.0, 1.0 + sin(idle_time * 1.25 + ph) * 0.012, 1.0)

		# 左右微晃
		root.rotation.z = sin(idle_time * 0.85 + ph) * 0.022

		# 慢慢东张西望（整身转一点）
		if i < character_base_y.size():
			root.rotation.y = character_base_y[i] + sin(idle_time * 0.45 + ph) * 0.16

		# 每 6 秒左右耸一下肩（整体压一下再弹回）
		var shrug := pow(maxf(0.0, sin(idle_time * 0.52 + ph * 2.0)), 12.0) * 0.045
		root.scale.y = root.scale.y - shrug

		# 点头（谁结算谁点）
		var pitch := 0.0
		var nt: float = nod_times[i]
		if nt >= 0.0:
			nt += delta
			nod_times[i] = nt
			pitch = sin(nt * 12.0) * 0.18 * exp(-nt * 5.0)
			if nt > 1.2:
				nod_times[i] = -1.0

		# 等人时往前探身
		var lean := 0.0
		if waiting and not players[i]["settled"]:
			lean = 0.10 + sin(idle_time * 1.9 + ph) * 0.03
		elif waiting:
			lean = 0.04

		root.rotation.x = pitch + lean


# ---------------- 玩法 ----------------

func _new_round() -> void:
	round = 1
	all_settled = false
	phase = "play"
	deck = Poker.build_deck()
	Poker.shuffle_deck(deck, rng)
	if end_button != null:
		end_button.visible = false
	if end_label != null:
		end_label.visible = false
	for i in 3:
		var p = players[i]
		p["slots"] = []
		p["used"] = [false, false, false, false, false]
		p["done"] = false
		p["points"] = BASE_POINTS
		p["score"] = 0
		p["settled"] = false
		_reset_hand(i)
		for k in 5:
			_draw_card(i, k)
			_stagger_deal(i * 5 + k)
		hands[i].score_label.text = ""
		hands[i].btn_label.text = "结 束 回 合"
		_refresh_name(i)
	_start_round()


## 一轮开始：三家都解锁换牌，从先手位开始
func _start_round() -> void:
	all_settled = false
	for i in 3:
		players[i]["used"] = [false, false, false, false, false]
		players[i]["done"] = false
		hands[i].cards_need_refresh = true if false else false
	active = first_seat
	_focus(active, true)
	_update_round_hud(active)
	_update_character_visibility()
	_update_hand_visibility(true)
	Sfx.play(self, "round", -9.0)
	tip_label.text = "第 %d/%d 轮 · 玩家 %d 先手" % [round, MAX_ROUNDS, active + 1]
	print("[3P] 第 %d 轮开始，先手玩家 %d" % [round, active + 1])


## 这家换完了，轮到下一位；三家都结束就进下一轮
func _end_turn(pi: int) -> void:
	if phase != "play" or pi != active:
		return
	if players[pi]["done"]:
		return
	players[pi]["done"] = true
	Sfx.play(self, "click", -6.0)
	_refresh_name(pi)

	var next := -1
	for k in 3:
		var idx := (pi + 1 + k) % 3
		if not players[idx]["done"]:
			next = idx
			break

	if next >= 0:
		active = next
		_focus(next)
		_update_round_hud(next)
		_update_character_visibility()
		_update_hand_visibility(true)
		tip_label.text = "轮到 玩家 %d · 换完点「结束回合」" % (next + 1)
	else:
		_finish_round()


func _finish_round() -> void:
	if round < MAX_ROUNDS:
		round += 1
		first_seat = (first_seat + 1) % 3
		_start_round()
	else:
		_settle_all()


## 三轮都换完，一次性算分
func _settle_all() -> void:
	phase = "settle"
	all_settled = true
	var lowest := 0
	for i in 3:
		var info := Poker.settle(players[i]["slots"], BASE_POINTS)
		players[i]["score"] = int(info["score"])
		players[i]["settled"] = true
		hands[i].score_label.text = "%d 分" % int(info["score"])
		hands[i].btn.visible = false
		hands[i].btn_label.visible = false
		if int(info["score"]) < int(players[lowest]["score"]):
			lowest = i
		if int(info["score"]) > best:
			best = int(info["score"])
			ScoreStore.set_best(best)
	best_label.text = "最高分 %d" % best
	_focus(lowest)
	_update_character_visibility()
	_update_hand_visibility(true)

	Sfx.play(self, "win" if int(players[lowest]["score"]) >= PUNISH_THRESHOLD else "lose", -5.0)
	var low_score: int = int(players[lowest]["score"])
	var scores := "%d / %d / %d" % [players[0]["score"], players[1]["score"], players[2]["score"]]
	print("[3P] 三轮结算：%s，最低玩家 %d（%d 分）" % [scores, lowest + 1, low_score])

	# 三家分数并排展示，谁最高谁最低一目了然
	var entries := []
	var highest := 0
	for i in 3:
		if int(players[i]["score"]) > int(players[highest]["score"]):
			highest = i
	for i in 3:
		var sc: int = int(players[i]["score"])
		var tag := "平安"
		var col := Color(0.86, 0.85, 0.78)
		if i == lowest and low_score < PUNISH_THRESHOLD:
			tag = "最低 · 受罚"
			col = Color(0.96, 0.42, 0.36)
		elif i == highest:
			tag = "本局最高"
			col = Color(1.0, 0.86, 0.35)
		entries.append({"name": players[i]["name"], "score": sc, "tag": tag, "color": col})

	cutscene_active = true
	var board := CutsceneKit.score_board(self, "CamPivot/Cam", entries)

	if low_score < PUNISH_THRESHOLD:
		phase = "punish"
		tip_label.text = "玩家 %d 最低（%d 分）· 惩戒阶段，点击跳过" % [lowest + 1, low_score]
		_play_cut(board, "结算展示", func() -> void:
			_play_cut(CutsceneKit.punishment(self, "CamPivot/Cam"), "惩戒"))
	else:
		tip_label.text = "三轮结束 · 全员达标（最低 %d 分）" % low_score
		_play_cut(board, "结算展示", func() -> void:
			end_label.text = "重 新 开 始"
			end_label.visible = true
			end_button.visible = true)


func _advance() -> void:
	_new_round()


func _stagger_deal(idx: int) -> void:
	var t := get_tree().create_timer(0.055 * float(idx))
	t.timeout.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			Sfx.play(self, "deal", -12.0))


func _draw_card(pi: int, ci: int) -> void:
	var p = players[pi]
	var slots: Array = p["slots"]
	while slots.size() < 5:
		slots.append(null)
	if deck.is_empty():
		return
	var card: Dictionary = deck.pop_back()
	slots[ci] = card
	var label: Label3D = hands[pi].labels[ci]
	label.text = Poker.card_text(card)
	label.modulate = Color(0.72, 0.16, 0.14) if Poker.is_red(card) else Color(0.08, 0.08, 0.1)


func _refresh_name(i: int) -> void:
	var p = players[i]
	var state := ""
	if p["settled"]:
		state = " · %d 分" % int(p["score"])
	elif p["done"]:
		state = " · 已结束回合"
	elif i == active and phase == "play":
		state = " · 轮到你"
	hands[i].name_label.text = "%s（%d 点）%s" % [p["name"], int(p["points"]), state]


func _set_hand_active(i: int, on: bool) -> void:
	hands[i].name_label.modulate = Color(0.95, 0.90, 0.72) if on else Color(0.55, 0.55, 0.5)


func focus_seat(i: int) -> void:
	active = i
	_focus(i, true)


func _focus(i: int, instant := false) -> void:
	# 第一人称：镜头转到这家座位，把自己隐藏
	var target := deg_to_rad(SEAT_ANGLES[i])
	_update_character_visibility()
	if instant:
		cam_pivot.rotation.y = target
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cam_pivot, "rotation:y", target, 0.65)


func _replace(pi: int, ci: int) -> void:
	if phase != "play" or pi != active:
		return
	var p = players[pi]
	if p["used"][ci]:
		return
	if int(p["points"]) < REPLACE_COST:
		tip_label.text = "点数不足，换一张需要 %d 点" % REPLACE_COST
		return
	if deck.is_empty():
		return
	p["used"][ci] = true
	p["points"] = int(p["points"]) - REPLACE_COST
	_draw_card(pi, ci)
	_flip_card(pi, ci, true)
	Sfx.play(self, "flip", -6.0)
	hands[pi].cards[ci].material_override = _mat(Color(0.80, 0.78, 0.72), 0.4, 0.05)
	_refresh_name(pi)


## 只有正在行动的那家能看到自己的牌面，另外两家显示牌背
func _face_material(pi: int, k: int) -> StandardMaterial3D:
	var used: bool = players[pi]["used"][k]
	return _mat(Color(0.80, 0.78, 0.72) if used else Color(0.92, 0.90, 0.84), 0.35, 0.05)


func _apply_card_face(pi: int, k: int, face_up: bool) -> void:
	if not is_instance_valid(hands[pi].cards[k]):
		return
	hands[pi].labels[k].visible = face_up
	hands[pi].backs[k].visible = not face_up
	hands[pi].cards[k].material_override = _face_material(pi, k)


## 翻一张牌：先压扁，翻面的瞬间换内容，再弹回来
func _flip_card(pi: int, k: int, face_up: bool) -> void:
	var card: MeshInstance3D = hands[pi].cards[k]
	var back: MeshInstance3D = hands[pi].backs[k]
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector3(1.0, 1.0, 0.05), 0.07)
	tw.parallel().tween_property(back, "scale", Vector3(1.0, 1.0, 0.05), 0.07)
	tw.tween_callback(_apply_card_face.bind(pi, k, face_up))
	tw.tween_property(card, "scale", Vector3.ONE, 0.10)
	tw.parallel().tween_property(back, "scale", Vector3.ONE, 0.10)


func _update_hand_visibility(animated := false) -> void:
	var reveal_all: bool = phase != "play"      # 结算/惩戒阶段全部亮牌
	for i in 3:
		var mine: bool = reveal_all or (i == active and not players[i]["done"])
		for k in 5:
			if animated:
				_flip_card(i, k, mine)
			else:
				_apply_card_face(i, k, mine)


func _update_character_visibility() -> void:
	# 第一人称：自己那家不显示，另外两家都在座位上
	for i in character_roots.size():
		character_roots[i].visible = (i != active)


func _refresh_buttons() -> void:
	_update_character_visibility()
	for i in 3:
		var show: bool = (i == active) and phase == "play" and not players[i]["done"]
		hands[i].btn.visible = show
		hands[i].btn_label.visible = show


func _update_round_hud(pi: int) -> void:
	round_label.text = "第 %d/%d 轮 · 玩家 %d" % [round, MAX_ROUNDS, pi + 1]
	_refresh_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if phase == "punish":
		_skip_punishment()
		return

	if phase == "settle":
		if _hit(end_button, mb.position, 130.0):
			_advance()
		return

	if phase != "play":
		return

	var entry = hands[active]
	for k in 5:
		if _hit(entry.cards[k], mb.position, 55.0):
			_replace(active, k)
			return
	if _hit(entry.btn, mb.position, 80.0):
		_end_turn(active)


func _hit(node: Node3D, screen_pos: Vector2, radius: float) -> bool:
	if camera == null or node == null:
		return false
	var projected := camera.unproject_position(node.global_position)
	return projected.distance_to(screen_pos) <= radius


# ---------------- 自检 ----------------


func run_test() -> void:
	print("[3P] 测试开始 round=%d 先手=玩家 %d" % [round, first_seat + 1])
	for r in MAX_ROUNDS:
		var guard := 0
		while phase == "play" and guard < 6:
			_end_turn(active)
			guard += 1
		print("[3P] 第 %d 轮走完 phase=%s round=%d" % [r + 1, phase, round])
	print("[3P] 最终分数 %d / %d / %d" % [players[0]["score"], players[1]["score"], players[2]["score"]])


func force_end() -> void:
	run_test()


func force_second_round() -> void:
	for r in 1:
		var guard := 0
		while phase == "play" and guard < 6:
			_end_turn(active)
			guard += 1


func force_punish() -> void:
	# 把三家的牌都塞成小牌，保证结算低于 100
	for i in 3:
		players[i]["slots"] = [
			{"suit": 0, "value": 2 + i}, {"suit": 1, "value": 4 + i},
			{"suit": 2, "value": 6 + i}, {"suit": 3, "value": 8 + i},
			{"suit": 0, "value": 10 + i},
		]
	round = MAX_ROUNDS
	for i in 3:
		players[i]["done"] = false
	_settle_all()


func force_wait() -> void:
	_end_turn(active)
	_end_turn(active)

func _play_cut(container: Node3D, label: String, then := Callable()) -> void:
	var ap: AnimationPlayer = container.get_node("Anim")
	ap.animation_finished.connect(func(_n: String) -> void:
		container.queue_free()
		cutscene_active = false
		if then.is_valid():
			then.call()
		elif phase == "punish":
			_on_punish_done()
		else:
			tip_label.text = "%s过场结束" % label
	)
	print("[3P] %s开始" % label)


func _on_punish_done() -> void:
	phase = "settle"
	tip_label.text = "惩戒完毕 · 点「重新开始」再来一局"
	end_label.text = "重 新 开 始"
	end_label.visible = true
	end_button.visible = true


func _skip_punishment() -> void:
	for c in get_children():
		if c.name == "PunishmentCut" or c.name == "VictoryCut":
			c.queue_free()
	if phase == "punish":
		_on_punish_done()


