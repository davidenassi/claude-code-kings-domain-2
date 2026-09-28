class_name KDLog
extends RefCounted
## Categorised logging. Levels are filtered globally; errors always go to push_error
## so headless checks can detect them in the output.

enum Level { DEBUG, INFO, WARN, ERROR }

static var min_level: int = Level.INFO
static var muted_categories: Dictionary = {}


static func debug(category: String, message: String) -> void:
	_emit(Level.DEBUG, category, message)


static func info(category: String, message: String) -> void:
	_emit(Level.INFO, category, message)


static func warn(category: String, message: String) -> void:
	_emit(Level.WARN, category, message)


static func error(category: String, message: String) -> void:
	_emit(Level.ERROR, category, message)


static func _emit(level: int, category: String, message: String) -> void:
	if level < min_level and level != Level.ERROR:
		return
	if muted_categories.has(category) and level < Level.WARN:
		return
	var line := "[KD:%s] %s" % [category, message]
	match level:
		Level.ERROR:
			push_error(line)
		Level.WARN:
			push_warning(line)
		_:
			print(line)

