extends RefCounted
## 共用的过场构件：惩戒 / 加冕
##
## 声音和画面共用同一组时间常量，改一个数两边一起变。
## 这是从「loop 与特效同步」那条学来的：不要给声音和动画各留一份时间表。
##
## 用法：
##   var cut := CutsceneKit.punishment(self, "Cam")
##   var ap := cut.get_node("Anim")
##   ap.animation_finished.connect(func(_n): cut.queue_free())

# 惩戒时间轴
const PUNISH_HOLD := 0.35      # 印章悬停：这段留白，一点声音都没有
const PUNISH_IMPACT := 1.15    # 砸到桌面
const PUNISH_LEN := 4.6

# 加冕时间轴
const VICTORY_POP := 0.55      # 金牌弹起
const VICTORY_LEN := 3.8


static func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func _audio(root: Node3D, path: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var stream = load(path)
	if stream != null:
		p.stream = stream
	p.volume_db = volume_db
	root.add_child(p)
	return p


## 定点播放：到点时对象还在才响
static func _schedule(root: Node3D, at: float, player: AudioStreamPlayer) -> void:
	if at <= 0.01:
		player.play()
		return
	var timer := root.get_tree().create_timer(at)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(player) and player.is_inside_tree():
			player.play()
	)


static func _finish_setup(root: Node3D, host: Node3D, anim: Animation) -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	root.add_child(ap)
	ap.root_node = ap.get_path_to(host)
	var lib := AnimationLibrary.new()
	lib.add_animation("anim", anim)
	ap.add_animation_library("", lib)
	return ap


## 惩戒：静场 → 印章落下 → 砸桌 → 冲击波
static func punishment(host: Node3D, cam_path: String) -> Node3D:
	var root := Node3D.new()
	root.name = "PunishmentCut"
	host.add_child(root)

	var stamp := Node3D.new()
	stamp.name = "Stamp"
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.35, 0.44, 1.35)
	mi.mesh = box
	mi.position = Vector3(0, -0.22, 0)
	mi.material_override = _mat(Color(0.72, 0.16, 0.12), 0.45, 0.15)
	stamp.add_child(mi)

	var lbl := Label3D.new()
	lbl.text = "罚"
	lbl.font_size = 256
	lbl.pixel_size = 0.0042
	lbl.position = Vector3(0, 0.24, 0)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.modulate = Color(1.0, 0.86, 0.34)
	stamp.add_child(lbl)
	stamp.position = Vector3(0, 4.4, 0.15)
	root.add_child(stamp)

	var dust := MeshInstance3D.new()
	dust.name = "Dust"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.72
	dust.mesh = ring
	dust.position = Vector3(0, 0.68, 0.15)
	dust.scale = Vector3(0.05, 0.05, 0.05)
	dust.material_override = _mat(Color(1.0, 0.85, 0.45), 0.2, 0.3)
	root.add_child(dust)

	var anim := Animation.new()
	anim.length = PUNISH_LEN

	# 印章：悬停（静场）→ 落 → 停 → 抬起
	var t1 := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t1, "PunishmentCut/Stamp:position")
	anim.track_insert_key(t1, 0.0, Vector3(0, 4.4, 0.15))
	anim.track_insert_key(t1, PUNISH_HOLD, Vector3(0, 4.4, 0.15))
	anim.track_insert_key(t1, PUNISH_IMPACT, Vector3(0, 0.98, 0.15))
	anim.track_insert_key(t1, PUNISH_IMPACT + 1.5, Vector3(0, 0.98, 0.15))
	anim.track_insert_key(t1, PUNISH_LEN - 0.5, Vector3(0, 4.4, 0.15))
	anim.track_set_interpolation_type(t1, Animation.INTERPOLATION_CUBIC)

	# 相机抖动：和砸击同一时刻
	var cam: Node3D = host.get_node_or_null(cam_path)
	var base := cam.position if cam != null else Vector3.ZERO
	var t2 := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t2, cam_path + ":position")
	anim.track_insert_key(t2, 0.0, base)
	anim.track_insert_key(t2, PUNISH_IMPACT, base)
	anim.track_insert_key(t2, PUNISH_IMPACT + 0.05, base + Vector3(0.10, 0.06, 0.0))
	anim.track_insert_key(t2, PUNISH_IMPACT + 0.11, base + Vector3(-0.12, -0.05, 0.06))
	anim.track_insert_key(t2, PUNISH_IMPACT + 0.17, base + Vector3(0.07, 0.03, -0.03))
	anim.track_insert_key(t2, PUNISH_IMPACT + 0.25, base + Vector3(-0.03, 0.0, 0.0))
	anim.track_insert_key(t2, PUNISH_IMPACT + 0.40, base)

	# 冲击波：砸下去的同一帧开始扩散
	var t3 := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t3, "PunishmentCut/Dust:scale")
	anim.track_insert_key(t3, 0.0, Vector3(0.05, 0.05, 0.05))
	anim.track_insert_key(t3, PUNISH_IMPACT - 0.01, Vector3(0.05, 0.05, 0.05))
	anim.track_insert_key(t3, PUNISH_IMPACT + 0.13, Vector3(2.4, 0.6, 2.4))
	anim.track_insert_key(t3, PUNISH_IMPACT + 0.85, Vector3(3.2, 0.2, 3.2))

	# 声音：前 0.35s 完全静音 → 风声 → 砸击
	var fall := _audio(root, "res://assets/sfx/sfx_fall.wav", -9.0)
	var hit := _audio(root, "res://assets/sfx/sfx_hit.wav", -1.0)
	_schedule(root, PUNISH_HOLD, fall)
	_schedule(root, PUNISH_IMPACT, hit)

	var ap := _finish_setup(root, host, anim)
	ap.play("anim")
	return root


## 加冕：静一拍 → 金牌弹起（和弦）→ 粒子
static func victory(host: Node3D, cam_path: String) -> Node3D:
	var root := Node3D.new()
	root.name = "VictoryCut"
	host.add_child(root)

	var crown := Node3D.new()
	crown.name = "Crown"
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.15, 0.06, 0.72)
	plate.mesh = box
	plate.material_override = _mat(Color(0.95, 0.78, 0.28), 0.18, 0.85)
	crown.add_child(plate)

	var lbl := Label3D.new()
	lbl.text = "新 纪 录"
	lbl.font_size = 120
	lbl.pixel_size = 0.004
	lbl.position = Vector3(0, 0.045, 0)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.modulate = Color(0.25, 0.14, 0.02)
	crown.add_child(lbl)
	crown.position = Vector3(0, 0.75, 0.15)
	crown.scale = Vector3(0.15, 0.15, 0.15)
	root.add_child(crown)

	var burst := CPUParticles3D.new()
	burst.name = "Burst"
	burst.amount = 90
	burst.lifetime = 1.6
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.5
	burst.direction = Vector3(0, 1, 0)
	burst.spread = 70.0
	burst.initial_velocity_min = 2.5
	burst.initial_velocity_max = 5.0
	burst.gravity = Vector3(0, -7, 0)
	burst.scale_amount_min = 0.3
	burst.scale_amount_max = 0.8
	var chip := BoxMesh.new()
	chip.size = Vector3(0.05, 0.05, 0.02)
	burst.mesh = chip
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(1.0, 0.85, 0.35)
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.75, 0.25)
	burst.material_override = pmat
	burst.position = Vector3(0, 0.95, 0.15)
	root.add_child(burst)

	var anim := Animation.new()
	anim.length = VICTORY_LEN

	var t1 := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t1, "VictoryCut/Crown:position")
	anim.track_insert_key(t1, 0.0, Vector3(0, 0.75, 0.15))
	anim.track_insert_key(t1, VICTORY_POP, Vector3(0, 1.72, 0.15))
	anim.track_insert_key(t1, VICTORY_POP + 0.17, Vector3(0, 1.62, 0.15))
	anim.track_insert_key(t1, VICTORY_POP + 0.37, Vector3(0, 1.68, 0.15))
	anim.track_insert_key(t1, VICTORY_LEN - 0.6, Vector3(0, 1.68, 0.15))

	var t2 := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t2, "VictoryCut/Crown:scale")
	anim.track_insert_key(t2, 0.0, Vector3(0.15, 0.15, 0.15))
	anim.track_insert_key(t2, VICTORY_POP, Vector3(0.86, 0.86, 0.86))
	anim.track_insert_key(t2, VICTORY_POP + 0.17, Vector3(0.96, 0.86, 0.96))
	anim.track_insert_key(t2, VICTORY_POP + 0.37, Vector3(0.86, 0.86, 0.86))

	var t3 := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t3, "VictoryCut/Crown:rotation")
	anim.track_insert_key(t3, 0.0, Vector3.ZERO)
	anim.track_insert_key(t3, VICTORY_LEN, Vector3(0, deg_to_rad(50), 0))

	var cam: Node3D = host.get_node_or_null(cam_path)
	if cam != null:
		var base := cam.position
		var t4 := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t4, cam_path + ":position")
		anim.track_insert_key(t4, 0.0, base)
		anim.track_insert_key(t4, VICTORY_POP + 0.8, base * 0.86 + Vector3(0, 0.10, 0))
		anim.track_insert_key(t4, VICTORY_LEN - 0.2, base * 0.90 + Vector3(0, 0.06, 0))

	# 声音：弹起那一下才是和弦，前面留白
	var chime := _audio(root, "res://assets/sfx/sfx_victory.wav", -3.0)
	_schedule(root, VICTORY_POP, chime)

	var ap := _finish_setup(root, host, anim)
	burst.emitting = true
	ap.play("anim")
	return root

## 结算分数特写：数字砸在屏幕中间，然后交给下一个过场
static func closeup(host: Node3D, cam_path: String, title: String, value: String,
		subtitle: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "ScoreCloseUp"
	host.add_child(root)

	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0, 4.6)
	panel.mesh = quad
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.02, 0.02, 0.03, 0.62)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel.material_override = pmat
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pmat.no_depth_test = true
	pmat.render_priority = 25
	panel.position = Vector3(0, 1.45, -0.15)
	root.add_child(panel)

	var num := Label3D.new()
	num.name = "Num"
	num.text = value
	num.font_size = 200
	num.pixel_size = 0.0045
	num.modulate = color
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.render_priority = 30
	num.position = Vector3(0, 1.55, 0.25)
	root.add_child(num)

	var t := Label3D.new()
	t.name = "Title"
	t.text = title
	t.font_size = 52
	t.pixel_size = 0.004
	t.modulate = Color(0.95, 0.92, 0.82)
	t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	t.no_depth_test = true
	t.render_priority = 30
	t.position = Vector3(0, 2.20, 0.25)
	root.add_child(t)

	var sub := Label3D.new()
	sub.name = "Sub"
	sub.text = subtitle
	sub.font_size = 44
	sub.pixel_size = 0.004
	sub.modulate = Color(0.86, 0.84, 0.76)
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.no_depth_test = true
	sub.render_priority = 30
	sub.position = Vector3(0, 0.80, 0.25)
	root.add_child(sub)

	var anim := Animation.new()
	anim.length = 1.7

	# 数字：从很小弹到正常，再轻轻放大离场
	var a1 := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(a1, "ScoreCloseUp/Num:scale")
	anim.track_insert_key(a1, 0.0, Vector3(0.25, 0.25, 0.25))
	anim.track_insert_key(a1, 0.22, Vector3(1.18, 1.18, 1.18))
	anim.track_insert_key(a1, 0.34, Vector3(1.0, 1.0, 1.0))
	anim.track_insert_key(a1, 1.35, Vector3(1.06, 1.06, 1.06))
	anim.track_insert_key(a1, 1.6, Vector3(1.35, 1.35, 1.35))

	# 数字：透明度
	var a2 := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(a2, "ScoreCloseUp/Num:modulate:a")
	anim.track_insert_key(a2, 0.0, 0.0)
	anim.track_insert_key(a2, 0.16, 1.0)
	anim.track_insert_key(a2, 1.35, 1.0)
	anim.track_insert_key(a2, 1.6, 0.0)

	var ap_panel := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(ap_panel, "ScoreCloseUp/Panel:modulate:a")
	anim.track_insert_key(ap_panel, 0.0, 0.0)
	anim.track_insert_key(ap_panel, 0.18, 1.0)
	anim.track_insert_key(ap_panel, 1.35, 1.0)
	anim.track_insert_key(ap_panel, 1.6, 0.0)

	# 标题 / 副标题淡入
	for name in ["Title", "Sub"]:
		var tr := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(tr, "ScoreCloseUp/%s:modulate:a" % name)
		anim.track_insert_key(tr, 0.0, 0.0)
		anim.track_insert_key(tr, 0.3, 0.0)
		anim.track_insert_key(tr, 0.5, 1.0)
		anim.track_insert_key(tr, 1.35, 1.0)
		anim.track_insert_key(tr, 1.6, 0.0)

	# 镜头轻推
	var cam: Node3D = host.get_node_or_null(cam_path)
	if cam != null:
		var base := cam.position
		var t4 := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t4, cam_path + ":position")
		anim.track_insert_key(t4, 0.0, base)
		anim.track_insert_key(t4, 0.5, base * 0.93 + Vector3(0, 0.05, 0))
		anim.track_insert_key(t4, 1.6, base * 0.96 + Vector3(0, 0.03, 0))

	# 一声提示音
	var chime := _audio(root, "res://assets/sfx/sfx_round.wav", -6.0)
	_schedule(root, 0.1, chime)

	var ap := _finish_setup(root, host, anim)
	ap.play("anim")
	return root

## 三人结算展示：三家分数并排亮出来
## entries = [{"name": "玩家 1", "score": 120, "tag": "平安", "color": Color(...)}]
static func score_board(host: Node3D, cam_path: String, entries: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "ScoreBoard"
	host.add_child(root)

	var anim := Animation.new()
	anim.length = 3.0
	var xs := [-1.55, 0.0, 1.55]

	for i in entries.size():
		var e: Dictionary = entries[i]
		var col: Color = e.get("color", Color(0.85, 0.82, 0.72))

		var panel := Node3D.new()
		panel.name = "P%d" % i
		panel.position = Vector3(xs[i], 1.80, 0.2)
		panel.scale = Vector3(0.1, 0.1, 0.1)
		root.add_child(panel)

		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.42, 1.62)
		quad.mesh = qm
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.albedo_color = Color(0.04, 0.04, 0.06, 0.78)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		pm.no_depth_test = true
		pm.render_priority = 26
		quad.material_override = pm
		panel.add_child(quad)

		var name_lbl := Label3D.new()
		name_lbl.text = str(e.get("name", ""))
		name_lbl.font_size = 44
		name_lbl.pixel_size = 0.0035
		name_lbl.modulate = Color(0.88, 0.86, 0.80)
		name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_lbl.no_depth_test = true
		name_lbl.render_priority = 30
		name_lbl.position = Vector3(0, 0.52, 0.02)
		panel.add_child(name_lbl)

		var score_lbl := Label3D.new()
		score_lbl.text = str(e.get("score", 0))
		score_lbl.font_size = 120
		score_lbl.pixel_size = 0.0035
		score_lbl.modulate = col
		score_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		score_lbl.no_depth_test = true
		score_lbl.render_priority = 30
		score_lbl.position = Vector3(0, 0.02, 0.02)
		panel.add_child(score_lbl)

		var tag_lbl := Label3D.new()
		tag_lbl.text = str(e.get("tag", ""))
		tag_lbl.font_size = 40
		tag_lbl.pixel_size = 0.0035
		tag_lbl.modulate = col
		tag_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag_lbl.no_depth_test = true
		tag_lbl.render_priority = 30
		tag_lbl.position = Vector3(0, -0.58, 0.02)
		panel.add_child(tag_lbl)

		# 依次弹出（一条 scale 轨道、一条 position 轨道，别写重）
		var at := 0.25 + float(i) * 0.32
		var t_scale := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t_scale, "ScoreBoard/P%d:scale" % i)
		anim.track_insert_key(t_scale, at, Vector3(0.1, 0.1, 0.1))
		anim.track_insert_key(t_scale, at + 0.18, Vector3(1.12, 1.12, 1.12))
		anim.track_insert_key(t_scale, at + 0.30, Vector3(1.0, 1.0, 1.0))
		anim.track_insert_key(t_scale, 2.7, Vector3(1.0, 1.0, 1.0))
		anim.track_insert_key(t_scale, 3.0, Vector3(1.2, 1.2, 1.2))

		var t_pos := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t_pos, "ScoreBoard/P%d:position" % i)
		anim.track_insert_key(t_pos, at, Vector3(xs[i], 1.45, 0.2))
		anim.track_insert_key(t_pos, at + 0.30, Vector3(xs[i], 2.05, 0.2))

	var chime := _audio(root, "res://assets/sfx/sfx_round.wav", -8.0)
	_schedule(root, 0.2, chime)

	var ap := _finish_setup(root, host, anim)
	ap.play("anim")
	return root
