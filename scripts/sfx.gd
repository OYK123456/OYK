extends RefCounted
## 一次性音效播放：每次 new 一个 AudioStreamPlayer，播完自己销毁。
##
## 用法：
##   Sfx.play(self, "deal")
##   Sfx.play(self, "click", -6.0)

const SOUNDS := {
	"deal": "res://assets/sfx/sfx_deal.wav",
	"flip": "res://assets/sfx/sfx_flip.wav",
	"click": "res://assets/sfx/sfx_click.wav",
	"hover": "res://assets/sfx/sfx_hover.wav",
	"round": "res://assets/sfx/sfx_round.wav",
	"win": "res://assets/sfx/sfx_win.wav",
	"lose": "res://assets/sfx/sfx_lose.wav",
}

static func _stream(key: String) -> AudioStream:
	var path: String = SOUNDS.get(key, "")
	if path == "":
		return null
	return load(path)


static func play(host: Node, key: String, volume_db := -4.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var stream := _stream(key)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	host.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
