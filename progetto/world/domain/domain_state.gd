class_name DomainState
extends RefCounted
## The player's homeland (Rebirth, Phase 1): a finite valley with its own space. Settlements, buildings, people,
## trees and rocks live in LOCAL metres (0..size_m); provinces, realms and armies live in the metres of the
## continent. This is the one place that knows how the two spaces correspond.
##
## Two sources:
## - `continent_crop`: the valley is a window cut out of the official map, aligned to ALIGN_M so that the local
##   grids fall exactly on the continent's (same rasters, same trees). Saves of the single-map era migrate here.
## - `homeland`: a generated homeland (Phase 2) with its own high-resolution geography, standing for the home
##   province on the global map.

const SOURCE_CROP := "continent_crop"
const SOURCE_HOMELAND := "homeland"
## Size of the valley in metres (see KINGSDOMAIN_REBIRTH_AUDIT.md §3.4): the whole of it fits the screen at about
## 4–6 m/px, a capital with its fields and woods fits inside it, the continent never does.
const DEFAULT_SIZE := Vector2(8064.0, 6144.0)
## Least common multiple of the tree grid (12 m) and of the raster cells (64 m): a crop whose origin is a
## multiple of it keeps every cell of every grid in place.
const ALIGN_M := 192.0

var source: String = SOURCE_CROP
## Id of the homeland template (data/domains/<id>), empty for a crop.
var homeland: String = ""
## Province of the continent the valley belongs to.
var home_province: int = -1
var size_m: Vector2 = DEFAULT_SIZE
## Continent metres of the local (0, 0) corner (crop: exact; homeland: the corner of the box it stands for).
var origin_global: Vector2 = Vector2.ZERO
## Continent metres per local metre: 1 for a crop; a homeland is drawn on the continent inside its province.
var global_scale: float = 1.0
## Where the capital stands on the global map when there is no settlement yet (the province's centre).
var anchor_global: Vector2 = Vector2.ZERO


func rect() -> Rect2:
	return Rect2(Vector2.ZERO, size_m)


func center() -> Vector2:
	return size_m * 0.5


func is_crop() -> bool:
	return source == SOURCE_CROP


## Local metres -> continent metres.
func to_global(local_pos: Vector2) -> Vector2:
	return origin_global + local_pos * global_scale


## Continent metres -> local metres (may fall outside the valley).
func to_local(global_pos: Vector2) -> Vector2:
	return (global_pos - origin_global) / global_scale


func contains_local(local_pos: Vector2) -> bool:
	return rect().has_point(local_pos)


func contains_global(global_pos: Vector2) -> bool:
	return contains_local(to_local(global_pos))


## A stable text that changes whenever the static geography of the valley would change (cache key of DomainData).
func key() -> String:
	return "%s|%s|%d|%.0f,%.0f|%.0f,%.0f|%.4f" % [source, homeland, home_province, origin_global.x, origin_global.y,
		size_m.x, size_m.y, global_scale]


## The valley cut out of the continent around a point, aligned to ALIGN_M and kept inside the map.
static func crop_around(global_center: Vector2, province_id: int, world_size: Vector2, size: Vector2 = DEFAULT_SIZE) -> DomainState:
	var d := DomainState.new()
	d.source = SOURCE_CROP
	d.home_province = province_id
	d.size_m = size
	var o := global_center - size * 0.5
	o = (o / ALIGN_M).round() * ALIGN_M
	o.x = clampf(o.x, 0.0, maxf(0.0, floorf((world_size.x - size.x) / ALIGN_M) * ALIGN_M))
	o.y = clampf(o.y, 0.0, maxf(0.0, floorf((world_size.y - size.y) / ALIGN_M) * ALIGN_M))
	d.origin_global = o
	d.global_scale = 1.0
	d.anchor_global = global_center
	return d


## A generated homeland (Phase 2) standing for a province of the continent. On the map of the world the whole
## valley is drawn inside its province: its centre on the province's centre, shrunk so it stays within it.
static func for_homeland(homeland_id: String, province_id: int, size: Vector2, province_center: Vector2,
		province_radius_m: float) -> DomainState:
	var d := DomainState.new()
	d.source = SOURCE_HOMELAND
	d.homeland = homeland_id
	d.home_province = province_id
	d.size_m = size
	d.global_scale = clampf(province_radius_m * 1.4 / maxf(size.x, size.y), 0.05, 0.6)
	d.anchor_global = province_center
	d.origin_global = province_center - size * 0.5 * d.global_scale
	return d


func to_dict() -> Dictionary:
	return {
		"source": source,
		"homeland": homeland,
		"home_province": home_province,
		"size": [size_m.x, size_m.y],
		"origin_global": [origin_global.x, origin_global.y],
		"global_scale": global_scale,
		"anchor_global": [anchor_global.x, anchor_global.y],
	}


static func from_dict(d: Dictionary) -> DomainState:
	var s := DomainState.new()
	s.source = String(d.get("source", SOURCE_CROP))
	s.homeland = String(d.get("homeland", ""))
	s.home_province = int(d.get("home_province", -1))
	var sz: Array = d.get("size", [DEFAULT_SIZE.x, DEFAULT_SIZE.y])
	s.size_m = Vector2(float(sz[0]), float(sz[1]))
	var o: Array = d.get("origin_global", [0, 0])
	s.origin_global = Vector2(float(o[0]), float(o[1]))
	s.global_scale = float(d.get("global_scale", 1.0))
	var a: Array = d.get("anchor_global", [0, 0])
	s.anchor_global = Vector2(float(a[0]), float(a[1]))
	return s
