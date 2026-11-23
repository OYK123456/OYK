extends RefCounted
## 骨骼驱动小工具：把 T-pose 掰成自然站姿，再加呼吸和点头。
##
## 用法：
##   var rig := RigHelper.find_skeleton(character)
##   RigHelper.relax_arms(rig)
##   RigHelper.idle(rig, t)      # 每帧
##   RigHelper.nod(rig, amount)  # 0..1


static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := find_skeleton(c)
		if r != null:
			return r
	return null


static func _bone_idx(skel: Skeleton3D, name: String) -> int:
	return skel.find_bone(name)


## 在骨骼的静止姿态上叠加一个旋转（绕局部轴，角度制）
static func add_rot(skel: Skeleton3D, name: String, axis: Vector3, deg: float) -> void:
	var i := _bone_idx(skel, name)
	if i < 0:
		return
	var rest: Quaternion = skel.get_bone_rest(i).basis.get_rotation_quaternion()
	var extra := Quaternion(axis.normalized(), deg_to_rad(deg))
	skel.set_bone_pose_rotation(i, rest * extra)


## 把两只手臂从 T-pose 放下来
static func relax_arms(skel: Skeleton3D, deg := 62.0) -> void:
	add_rot(skel, "L_Upperarm", Vector3(0, 1, 0), -deg)
	add_rot(skel, "R_Upperarm", Vector3(0, 1, 0), deg)
	# 小臂稍微往里收一点，别绷直
	add_rot(skel, "L_Forearm", Vector3(0, 0, 1), -12.0)
	add_rot(skel, "R_Forearm", Vector3(0, 0, 1), 12.0)


## 站立待机：呼吸 + 轻微晃
static func idle(skel: Skeleton3D, t: float) -> void:
	var breath := sin(t * 1.3) * 2.0
	add_rot(skel, "Spine02", Vector3(1, 0, 0), breath)
	add_rot(skel, "Waist", Vector3(1, 0, 0), breath * 0.4)
	add_rot(skel, "Head", Vector3(0, 1, 0), sin(t * 0.7) * 3.0)
	add_rot(skel, "Head", Vector3(1, 0, 0), sin(t * 0.9) * 1.5)
	add_rot(skel, "NeckTwist01", Vector3(1, 0, 0), sin(t * 0.6) * 1.0)


## 点头：amount 0..1
static func nod(skel: Skeleton3D, amount: float) -> void:
	add_rot(skel, "Head", Vector3(1, 0, 0), 16.0 * amount)
	add_rot(skel, "NeckTwist01", Vector3(1, 0, 0), 6.0 * amount)
