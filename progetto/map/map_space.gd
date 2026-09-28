class_name MapSpace
extends RefCounted
## The two maps of the Rebirth and the ground each one is drawn on (see KINGSDOMAIN_REBIRTH_AUDIT.md §3):
## - LOCAL: the valley of the homeland, in its own metres (DomainData of the current campaign);
## - GLOBAL: the continent (WorldData).
## A renderer that can serve both maps carries an exported `space` and asks here for its data.

const GLOBAL := &"global"
const LOCAL := &"local"


## The ground of a map for the running campaign (null when the valley does not exist yet).
static func data(space: StringName) -> WorldData:
	if space == LOCAL:
		if Session.has_game():
			return DomainData.of(Session.current.world)
		return null
	return WorldData.get_instance()


static func is_local(space: StringName) -> bool:
	return space == LOCAL
