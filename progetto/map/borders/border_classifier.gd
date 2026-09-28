class_name BorderClassifier
extends RefCounted
## Decides how a border between two provinces is drawn from the current political state.

const PROVINCE := 0   ## same owner (or both free): thin province line only
const REALM := 1      ## different owners: realm border with the owners' colours


static func classify(world: WorldState, a: int, b: int) -> int:
	var pa := world.province(a)
	var pb := world.province(b)
	if pa == null or pb == null:
		return PROVINCE
	return PROVINCE if pa.owner == pb.owner else REALM

