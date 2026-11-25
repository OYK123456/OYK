extends Node3D
const CutsceneKit = preload("res://scripts/cutscene.gd")
const ScoreStore = preload("res://scripts/score_store.gd")
const RigHelper = preload("res://scripts/rig_helper.gd")
const Poker = preload("res://scripts/poker.gd")
const Sfx = preload("res://scripts/sfx.gd")
## 五张牌 · 单人（3D）—— 由 root.gd 挂载
##
## 规则照 Flutter 版：3 轮，每轮 5 张牌，每张每轮可换一次（换牌扣 2 点），
## 结算 = (底注 40 + 点数和) × 倍数。低于 100 进惩罚，破纪录加冕。
##
## 场景全部代码生成，不用手写 .tscn。

const BASE_POINTS := 40
const PUNISH_THRESHOLD := 100
const MAX_ROUNDS := 3
const REPLACE_COST := 2

const MODEL_FBX := "res://assets/model_rigged.fbx"
const MODEL_FBX_OLD := "res://assets/model.fbx"
const MODEL_PATH := "res://assets/model.glb"
const CHARACTER_HEIGHT := 1.75

const CARD_SIZE := Vector3(0.62, 0.012, 0.88)
const CARD_GAP := 0.70
const TABLE_TOP := 0.70

var rng := RandomNumberGenerator.new()

var camera: Camera3D
var cards: Array[MeshInstance3D] = []
var card_labels: Array[Label3D] = []
var card_values: Array[int] = []
var card_used: Array[bool] = []

var round_label: Label3D
var points_label: Label3D
var total_label: Label3D
var hand_label: Label3D
var hint_label: Label3D
var score_label: Label3D
var button_next: MeshInstance3D
var button_next_label: Label3D
var button_settle: MeshInstance3D
var button_settle_label: Label3D
var best_label: Label3D

var character: Node3D
var character_root: Node3D
var skel: Skeleton3D
var idle_time := 0.0
var nod_time := -1.0

var round := 1
var points := BASE_POINTS
var total := BASE_POINTS
var replaces := 0
var settled := false
var best := 0
var victory_player: AnimationPlayer
var crown: Node3D
var burst: CPUParticles3D


func _ready() -> void:
	rng.randomize()
	_build_environment()
	_build_table()
	_build_floor()
	_build_character_slot()
	_load_character()
	_build_cards()
	_build_ui()
	best = ScoreStore.get_best()
	print("[3D] 最高分（存档）=", best)
	_new_game()



# ---------------- 搭场景 ----------------

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.44, 0.50)
	env.ambient_light_energy = 0.9
	env.glow_enabled = true
	world.environment = env
	add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -34, 0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.95, 0.86)
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-28, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.55, 0.68, 0.90)
	add_child(rim)

	camera = Camera3D.new()
	camera.name = "Cam"
	camera.position = Vector3(0, 3.85, 4.25)
	camera.fov = 42
	add_child(camera)
	camera.look_at(Vector3(0, TABLE_TOP + 0.25, 0.1))


func _build_table() -> void:
	var table := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.6, 0.16, 3.2)
	table.mesh = box
	table.position = Vector3(0, TABLE_TOP - 0.08, 0)
	table.material_override = _mat(Color(0.09, 0.22, 0.16), 0.55, 0.25)
	add_child(table)

	var edge := MeshInstance3D.new()
	var ebox := BoxMesh.new()
	ebox.size = Vector3(4.9, 0.06, 3.5)
	edge.mesh = ebox
	edge.position = Vector3(0, TABLE_TOP - 0.17, 0)
	edge.material_override = _mat(Color(0.05, 0.05, 0.07), 0.4, 0.6)
	add_child(edge)


func _build_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -0.02, 0)
	floor_mesh.material_override = _mat(Color(0.045, 0.045, 0.06), 0.95, 0.0)
	add_child(floor_mesh)


func _build_character_slot() -> void:
	character_root = Node3D.new()
	character_root.position = Vector3(0, 0, -2.05)
	add_child(character_root)


func _build_cards() -> void:
	for i in 5:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = CARD_SIZE
		mi.mesh = mesh
		mi.position = Vector3((i - 2) * CARD_GAP, TABLE_TOP + 0.01, 0.15)
		mi.material_override = _mat(Color(0.92, 0.90, 0.84), 0.35, 0.05)
		add_child(mi)
		cards.append(mi)

		var label := Label3D.new()
		label.font_size = 96
		label.pixel_size = 0.0032
		label.rotation_degrees = Vector3(-90, 0, 0)
		label.position = mi.position + Vector3(0, 0.014, 0)
		add_child(label)
		card_labels.append(label)


func _build_ui() -> void:
	best_label = _label("最高分 0", Vector3(-1.55, TABLE_TOP + 0.02, -1.10), 36, Color(0.78, 0.86, 0.82))
	round_label = _label("第 1/%d 轮" % MAX_ROUNDS, Vector3(0, TABLE_TOP + 0.02, -1.10), 40, Color(0.92, 0.88, 0.78))
	points_label = _label("当前点数 %d" % points, Vector3(-1.55, TABLE_TOP + 0.02, -0.80), 30, Color(0.8, 0.84, 0.8))
	total_label = _label("累计总分 %d" % total, Vector3(0, TABLE_TOP + 0.02, -0.80), 30, Color(0.8, 0.84, 0.8))
	hand_label = _label("当前牌型：高牌 ×0", Vector3(1.55, TABLE_TOP + 0.02, -0.80), 30, Color(0.8, 0.84, 0.8))

	score_label = _label("", Vector3(0, TABLE_TOP + 0.02, 0.92), 96, Color(1.0, 0.85, 0.45))
	hint_label = _label("点牌换牌（每张一次，每次扣 2 点）", Vector3(0, TABLE_TOP + 0.02, 1.24), 28, Color(0.68, 0.71, 0.66))

	button_next = _button(Vector3(-0.62, TABLE_TOP + 0.03, 1.62), Vector3(0.92, 0.05, 0.34),
		Color(0.30, 0.62, 0.85))
	button_next_label = _label("下 一 轮", Vector3(-0.62, TABLE_TOP + 0.062, 1.62), 40, Color(0.06, 0.06, 0.08))

	button_settle = _button(Vector3(0.62, TABLE_TOP + 0.03, 1.62), Vector3(0.92, 0.05, 0.34),
		Color(0.92, 0.82, 0.52))
	button_settle_label = _label("结 算 本 局", Vector3(0.62, TABLE_TOP + 0.062, 1.62), 34, Color(0.06, 0.06, 0.08))


func _button(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, 0.25, 0.1)
	add_child(mi)
	return mi


func _label(text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0032
	l.modulate = color
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	add_child(l)
	return l


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


# ---------------- 角色 ----------------

func _load_character() -> void:
	if ResourceLoader.exists(MODEL_FBX):
		var packed = load(MODEL_FBX)
		if packed is PackedScene:
			character = (packed as PackedScene).instantiate()
			_place_character()
			return

	if FileAccess.file_exists(MODEL_FBX):
		var fdoc = FBXDocument.new()
		var fstate = FBXState.new()
		if fdoc.append_from_file(MODEL_FBX, fstate) == OK:
			character = fdoc.generate_scene(fstate)
			if character != null:
				_place_character()
				return
		push_warning("FBX 读取失败，试试 GLB")

	if FileAccess.file_exists(MODEL_PATH):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(MODEL_PATH, state) == OK:
			character = doc.generate_scene(state)
			if character != null:
				_place_character()
				return
		push_warning("GLB 读不了（大概率是 meshopt 压缩）")

	_spawn_placeholder()


func _place_character() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.70, 0.76, 0.80)
	skin.roughness = 0.72
	skin.metallic = 0.0
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_material(character, skin)

	var size := _local_size(character)
	var height: float = maxf(size.y, size.z)
	var s: float = CHARACTER_HEIGHT / maxf(height, 0.001)

	character.rotation_degrees = Vector3(0, 0, 0)
	character.scale = Vector3.ONE * s
	character.position = Vector3(-1.05, 0, 0)
	character_root.add_child(character)
	print("[3D] 角色已加载：原始尺寸 %s，缩放 %.2f" % [str(size), s])

	skel = RigHelper.find_skeleton(character)
	if skel != null:
		print("[3D] 找到骨骼，骨数=", skel.get_bone_count())
		RigHelper.relax_arms(skel)

	else:
		print("[3D] 模型没有骨骼")


func _spawn_placeholder() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.30
	cap.height = 1.25
	body.mesh = cap
	body.position = Vector3(-1.05, 0.63, 0)
	body.material_override = _mat(Color(0.55, 0.66, 0.72), 0.7, 0.0)
	character_root.add_child(body)

	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.31
	sph.height = 0.62
	head.mesh = sph
	head.position = Vector3(-1.05, 1.48, 0)
	head.material_override = _mat(Color(0.62, 0.72, 0.78), 0.65, 0.0)
	character_root.add_child(head)


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


## 待机：上下浮 + 呼吸缩放 + 结算点头
func _process(delta: float) -> void:
	if character_root == null:
		return
	idle_time += delta
	if skel != null:
		RigHelper.idle(skel, idle_time)
		if nod_time >= 0.0:
			var amt := maxf(0.0, sin(nod_time * 6.0)) * exp(-nod_time * 3.0)
			RigHelper.nod(skel, amt)
	character_root.position.y = sin(idle_time * 1.7) * 0.035
	character_root.scale = Vector3(1.0, 1.0 + sin(idle_time * 1.25) * 0.012, 1.0)

	var pitch := 0.0
	if nod_time >= 0.0:
		nod_time += delta
		pitch = sin(nod_time * 12.0) * 0.16 * exp(-nod_time * 5.0)
		if nod_time > 1.2:
			nod_time = -1.0
	character_root.rotation.x = pitch


# ---------------- 玩法（照 app1 的规则） ----------------

var deck: Array = []
var slots: Array = []          # 五张牌，每张是 {suit, value}


func _new_game() -> void:
	deck = Poker.build_deck()
	Poker.shuffle_deck(deck, rng)
	round = 1
	points = BASE_POINTS
	total = BASE_POINTS
	replaces = 0
	settled = false
	card_used = [false, false, false, false, false]
	slots.clear()
	for i in 5:
		slots.append(deck.pop_back())
		_draw_card(i)
		_stagger_deal(i)



	score_label.text = ""
	hint_label.text = "点牌换牌（每张每轮一次，换后锁定）"
	button_next_label.text = "结 束 回 合"
	button_settle_label.text = "结 算"
	_refresh_ui()


func _stagger_deal(i: int) -> void:
	var t := get_tree().create_timer(0.07 * float(i))
	t.timeout.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			Sfx.play(self, "deal", -10.0))


func _draw_card(index: int) -> void:
	card_labels[index].text = Poker.card_text(slots[index])
	card_labels[index].modulate = Color(0.72, 0.16, 0.14) if Poker.is_red(slots[index]) else Color(0.08, 0.08, 0.1)
	var used := card_used.size() > index and card_used[index]
	cards[index].material_override = _mat(
		Color(0.80, 0.78, 0.72) if used else Color(0.92, 0.90, 0.84), 0.35, 0.05)


func _refresh_ui() -> void:
	round_label.text = "第 %d/%d 轮" % [round, MAX_ROUNDS]
	if not settled:
		var last := round >= MAX_ROUNDS
		button_next.visible = not last
		button_next_label.visible = not last
		button_settle.visible = last
		button_settle_label.visible = last
		var bx := 0.0
		button_next.position.x = bx
		button_next_label.position.x = bx
		button_settle.position.x = bx
		button_settle_label.position.x = bx
	points_label.text = "当前点数 %d" % points
	total_label.text = "累计总分 %d" % total
	best_label.text = "最高分 %d" % best
	if slots.size() == 5:
		var info := Poker.evaluate(slots)
		hand_label.text = "当前牌型：%s ×%d" % [info["label"], info["multiplier"]]


func _replace(index: int) -> void:
	if settled or card_used[index]:
		return
	if points < REPLACE_COST:
		hint_label.text = "点数不足，换一张需要 %d 点" % REPLACE_COST
		return
	if deck.is_empty():
		return
	card_used[index] = true
	points -= REPLACE_COST
	replaces += 1
	slots[index] = deck.pop_back()
	_draw_card(index)
	Sfx.play(self, "flip", -5.0)
	_refresh_ui()


## 下一轮：不重新发牌，只解锁换牌次数（app1 的行为）
func _next_round() -> void:
	if settled or round >= MAX_ROUNDS:
		return
	round += 1
	Sfx.play(self, "round", -7.0)
	card_used = [false, false, false, false, false]
	for i in 5:
		_draw_card(i)
	if round >= MAX_ROUNDS:
		hint_label.text = "第 %d 轮 · 最后一轮，换完点「结算」" % round
	else:
		hint_label.text = "第 %d 轮 · 换完点「结束回合」" % round
	_refresh_ui()


func _settle() -> void:
	if settled:
		_new_game()
		return
	if round < MAX_ROUNDS:
		hint_label.text = "三轮换完才能结算（现在是第 %d 轮）" % round
		return

	var result := Poker.settle(slots, BASE_POINTS)
	var score: int = result["score"]
	settled = true
	total = score
	points = score
	score_label.text = "%d 分" % score

	var is_record := score > best
	if is_record:
		best = score
		ScoreStore.set_best(best)

	var msg := ""
	if int(result["multiplier"]) > 0:
		msg = "【%s】(%d+%d)×%d = %d" % [result["label"], BASE_POINTS, result["sum"], result["multiplier"], score]
	else:
		msg = "【%s】未中奖" % result["label"]

	Sfx.play(self, "win" if score >= PUNISH_THRESHOLD else "lose", -5.0)

	if score < PUNISH_THRESHOLD:
		hint_label.text = msg + " · 低于 %d，进惩戒" % PUNISH_THRESHOLD
		nod_time = 0.0
		var focus_cut := CutsceneKit.closeup(
			self, "Cam", "本局得分", str(score), "低于 %d 分" % PUNISH_THRESHOLD,
			Color(0.96, 0.38, 0.32))
		_play_cut(focus_cut, "分数特写", func() -> void:
			_play_cut(CutsceneKit.punishment(self, "Cam"), "惩戒"))
	elif is_record:
		hint_label.text = msg + " · 破纪录！"
		nod_time = 0.0
		var focus_cut := CutsceneKit.closeup(
			self, "Cam", "本局得分", str(score), "打破纪录 · 历史最高 %d" % best,
			Color(1.0, 0.86, 0.35))
		_play_cut(focus_cut, "分数特写", func() -> void:
			_play_cut(CutsceneKit.victory(self, "Cam"), "加冕"))
	else:
		hint_label.text = msg

	button_next.visible = false
	button_next_label.visible = false
	button_settle.visible = true
	button_settle_label.visible = true
	button_settle.position.x = 0.0
	button_settle_label.position.x = 0.0
	button_settle_label.text = "重 新 开 始"
	_refresh_ui()
	print("[3D] 结算：%s 倍率×%d -> %d 分（最高 %d）" % [result["label"], result["multiplier"], score, best])


# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	for i in cards.size():
		if _hit(cards[i], mb.position, 70.0):
			_replace(i)
			return

	if _hit(button_next, mb.position, 85.0):
		Sfx.play(self, "click", -8.0)
		if settled:
			_new_game()
		else:
			_next_round()
		return

	if _hit(button_settle, mb.position, 95.0):
		Sfx.play(self, "click", -8.0)
		_settle()


func _hit(node: Node3D, screen_pos: Vector2, radius: float) -> bool:
	if camera == null or node == null:
		return false
	# 不可见的按钮不参与命中判定：
	# 两个按钮挪到同一个位置后，若不做这一步，隐藏的「结束回合」会先吃掉点击
	if not node.visible:
		return false
	var projected := camera.unproject_position(node.global_position)
	return projected.distance_to(screen_pos) <= radius


# ---------------- 自检 ----------------

func verify_buttons() -> void:
	round = MAX_ROUNDS
	settled = false
	_refresh_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	var settle_pos := camera.unproject_position(button_settle.global_position)
	var hit_next := _hit(button_next, settle_pos, 85.0)
	var hit_settle := _hit(button_settle, settle_pos, 95.0)
	print("[TEST] 第 %d 轮：settle.visible=%s  next.visible=%s" % [round, button_settle.visible, button_next.visible])
	print("[TEST] 点在结算按钮上 -> next 命中=%s，settle 命中=%s" % [hit_next, hit_settle])
	if (not hit_next) and hit_settle:
		print("[TEST] PASS：结算按钮能正常接收点击")
	else:
		print("[TEST] FAIL：结算按钮的点击被其它控件拦截")


func _card(value: int, suit: int) -> Dictionary:
	return {"value": value, "suit": suit}


func _selftest() -> void:
	var cases := [
		[[_card(14, 3), _card(13, 3), _card(12, 3), _card(11, 3), _card(10, 3)], "同花顺", 50],
		[[_card(7, 0), _card(7, 1), _card(7, 2), _card(7, 3), _card(13, 0)], "四条", 25],
		[[_card(3, 0), _card(3, 1), _card(3, 2), _card(5, 0), _card(5, 1)], "葫芦", 9],
		[[_card(2, 0), _card(5, 0), _card(8, 0), _card(11, 0), _card(13, 0)], "同花", 6],
		[[_card(5, 0), _card(6, 1), _card(7, 2), _card(8, 3), _card(9, 0)], "顺子", 4],
		[[_card(4, 0), _card(4, 1), _card(4, 2), _card(9, 0), _card(2, 1)], "三条", 3],
		[[_card(8, 0), _card(8, 1), _card(11, 2), _card(11, 3), _card(3, 0)], "两对", 2],
		[[_card(12, 0), _card(12, 1), _card(3, 2), _card(5, 3), _card(9, 0)], "对子(J以上)", 1],
		[[_card(5, 0), _card(5, 1), _card(9, 2), _card(11, 3), _card(2, 0)], "一对小牌", 0],
		[[_card(14, 0), _card(13, 1), _card(9, 2), _card(5, 3), _card(3, 0)], "高牌", 0],
	]
	for c in cases:
		var info := Poker.evaluate(c[0])
		var ok: bool = info["label"] == c[1] and int(info["multiplier"]) == int(c[2])
		print("[3D] 牌型 %s -> %s ×%d %s" % [str(c[1]), info["label"], info["multiplier"], "OK" if ok else "FAIL"])

	print("[3D] 自检：手牌 %s，牌堆剩 %d" % [str(Poker.card_text(slots[0])), deck.size()])
	_replace(0)
	print("[3D] 换牌后点数=%d 已换=%d 牌堆=%d" % [points, replaces, deck.size()])
	_next_round()
	_next_round()
	print("[3D] 推满三轮后 round=%d 手牌未变=%s" % [round, str(slots.size())])
	_settle()
	print("[3D] 结算后 settled=%s 总分=%d" % [str(settled), total])
	get_tree().quit()


# ---------------- 加冕过场（AnimationPlayer） ----------------

## 测试用：直接构造一次破纪录
func force_record() -> void:
	best = 0
	round = MAX_ROUNDS
	slots = [
		{"suit": 3, "value": 14}, {"suit": 3, "value": 13}, {"suit": 3, "value": 12},
		{"suit": 3, "value": 11}, {"suit": 3, "value": 10},
	]
	for i in 5:
		_draw_card(i)
	card_used = [true, true, true, true, true]
	_settle()


func _play_cut(container: Node3D, label: String, then := Callable()) -> void:
	var ap: AnimationPlayer = container.get_node("Anim")
	ap.animation_finished.connect(func(_n: String) -> void:
		container.queue_free()
		if then.is_valid():
			then.call()
		else:
			hint_label.text = "%s过场结束 · 点「重 新 开 始」继续" % label
	)
	print("[3D] %s开始" % label)


func force_third_round() -> void:
	_next_round()
	_next_round()
