class_name CommandResult
extends RefCounted

var success: bool = true
var reason: String = ""
var data: Dictionary = {}


static func ok(p_data: Dictionary = {}) -> CommandResult:
	var r := CommandResult.new()
	r.success = true
	r.data = p_data
	return r


static func fail(p_reason: String) -> CommandResult:
	var r := CommandResult.new()
	r.success = false
	r.reason = p_reason
	return r

