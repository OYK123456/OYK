extends RefCounted
## 最高分持久化（存到 user://save.cfg）

const PATH := "user://save.cfg"


static func get_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return 0
	return int(cfg.get_value("score", "best", 0))


## 只有更高才写盘；返回是否刷新了纪录
static func set_best(value: int) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var current := int(cfg.get_value("score", "best", 0))
	if value <= current:
		return false
	cfg.set_value("score", "best", value)
	cfg.save(PATH)
	return true


static func clear() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", 0)
	cfg.save(PATH)
