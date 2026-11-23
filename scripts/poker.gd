extends RefCounted
## 牌与牌型：严格照 Flutter 版 app1 的规则搬过来
##
## 一副 52 张；A=14 K=13 Q=12 J=11，其余按面值。
## 牌型倍率：同花顺50 / 四条25 / 葫芦9 / 同花6 / 顺子4 / 三条3 / 两对2 /
##          对子(J以上)1 / 一对小牌0 / 高牌0

const SUITS := ["♥", "♦", "♣", "♠"]      # 红心 方块 梅花 黑桃
const RED_SUITS := [0, 1]
const RANK_NAMES := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]


static func build_deck() -> Array:
	var deck := []
	for suit in 4:
		for value in range(2, 15):
			deck.append({"suit": suit, "value": value})
	return deck


static func shuffle_deck(deck: Array, rng: RandomNumberGenerator) -> void:
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp


static func rank_name(value: int) -> String:
	if value < 1 or value > 14:
		return "?"
	return RANK_NAMES[value - 1] if value >= 2 else "A"


static func card_text(card: Dictionary) -> String:
	return "%s\n%s" % [rank_name(int(card["value"])), SUITS[int(card["suit"])]]


static func is_red(card: Dictionary) -> bool:
	return int(card["suit"]) in RED_SUITS


## 评估 5 张牌，返回 {label, multiplier, rank}
static func evaluate(cards: Array) -> Dictionary:
	if cards.size() != 5:
		return {"label": "未满五张", "multiplier": 0, "rank": 0}

	var values := []
	var suits := {}
	for c in cards:
		values.append(int(c["value"]))
		suits[int(c["suit"])] = true
	values.sort()
	var is_flush := suits.size() == 1

	var freq := {}
	for v in values:
		freq[v] = int(freq.get(v, 0)) + 1

	var keys := freq.keys()
	keys.sort_custom(func(a, b):
		if freq[a] != freq[b]:
			return int(freq[a]) > int(freq[b])
		return int(a) > int(b))

	var pattern := []
	for k in keys:
		pattern.append(int(freq[k]))

	# 顺子（含 A-2-3-4-5）
	var is_straight := false
	if freq.size() == 5:
		var hi: int = values[4]
		var lo: int = values[0]
		if hi - lo == 4:
			is_straight = true
		elif hi == 14 and values[0] == 2 and values[1] == 3 and values[2] == 4 and values[3] == 5:
			is_straight = true

	if is_flush and is_straight:
		return {"label": "同花顺", "multiplier": 50, "rank": 8}
	if pattern[0] == 4:
		return {"label": "四条", "multiplier": 25, "rank": 7}
	if pattern[0] == 3 and pattern.size() > 1 and pattern[1] == 2:
		return {"label": "葫芦", "multiplier": 9, "rank": 6}
	if is_flush:
		return {"label": "同花", "multiplier": 6, "rank": 5}
	if is_straight:
		return {"label": "顺子", "multiplier": 4, "rank": 4}
	if pattern[0] == 3:
		return {"label": "三条", "multiplier": 3, "rank": 3}
	if pattern[0] == 2 and pattern.size() > 1 and pattern[1] == 2:
		return {"label": "两对", "multiplier": 2, "rank": 2}
	if pattern[0] == 2:
		# 对子只有 J 以上才算
		if int(keys[0]) >= 11:
			return {"label": "对子(J以上)", "multiplier": 1, "rank": 1}
		return {"label": "一对小牌", "multiplier": 0, "rank": 0}
	return {"label": "高牌", "multiplier": 0, "rank": 0}


## 结算 =（底注 + 点数之和）× 倍率
static func settle(cards: Array, base_points: int) -> Dictionary:
	var info := evaluate(cards)
	var total := 0
	for c in cards:
		total += int(c["value"])
	var score: int = (base_points + total) * int(info["multiplier"])
	return {"label": info["label"], "multiplier": info["multiplier"], "sum": total, "score": score}
