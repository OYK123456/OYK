extends SceneTree

const Poker = preload("res://scripts/poker.gd")

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# 1) 洗牌后牌是否还完整（52 张、无重复）
	var dup_found := 0
	for trial in 200:
		var deck := Poker.build_deck()
		Poker.shuffle_deck(deck, rng)
		var seen := {}
		for c in deck:
			var key := "%d-%d" % [int(c["suit"]), int(c["value"])]
			if seen.has(key):
				dup_found += 1
			seen[key] = true
		if deck.size() != 52:
			dup_found += 1
	print("[随机] 200 次洗牌，重复/张数错误次数 = ", dup_found)

	# 2) 首张牌的点数分布（52 张里每个点数 4 张，应各占 4/52）
	var N := 26000
	var counts := {}
	for v in range(2, 15):
		counts[v] = 0
	for i in N:
		var deck := Poker.build_deck()
		Poker.shuffle_deck(deck, rng)
		var v := int(deck[0]["value"])
		counts[v] = int(counts[v]) + 1

	var expected := float(N) / 13.0
	var chi := 0.0
	var min_c := N
	var max_c := 0
	for v in range(2, 15):
		var c: int = counts[v]
		min_c = mini(min_c, c)
		max_c = maxi(max_c, c)
		chi += pow(float(c) - expected, 2) / expected
	print("[随机] 首张点数：期望 %.0f，实际区间 %d–%d，卡方 %.1f（12 自由度，临界值 26.2 @0.01）" % [expected, min_c, max_c, chi])

	# 3) 连续两次洗牌是否不同
	var a := Poker.build_deck()
	Poker.shuffle_deck(a, rng)
	var b := Poker.build_deck()
	Poker.shuffle_deck(b, rng)
	var same := 0
	for i in a.size():
		if int(a[i]["value"]) == int(b[i]["value"]) and int(a[i]["suit"]) == int(b[i]["suit"]):
			same += 1
	print("[随机] 两次洗牌同位置的牌数 = ", same, " / 52（接近 1 才正常，等于 52 说明没洗）")

	# 4) 种子：两次 randomize 出来的种子是否不同
	var r1 := RandomNumberGenerator.new()
	r1.randomize()
	var r2 := RandomNumberGenerator.new()
	r2.randomize()
	print("[随机] 两次 randomize 的种子：", r1.seed, " / ", r2.seed, " 相同=", r1.seed == r2.seed)
	quit()
