extends KDTestCase


func test_same_seed_same_sequence() -> void:
	var a := KDRng.new(12345)
	var b := KDRng.new(12345)
	for i in 20:
		assert_eq(a.stream(&"economy").randi(), b.stream(&"economy").randi())


func test_streams_are_independent() -> void:
	var a := KDRng.new(99)
	var b := KDRng.new(99)
	# consuming another stream in `a` must not shift the ai stream
	for i in 50:
		a.stream(&"events").randf()
	for i in 10:
		assert_eq(a.stream(&"ai").randi(), b.stream(&"ai").randi())


func test_serialization_continues_sequence() -> void:
	var a := KDRng.new(2026)
	for i in 17:
		a.stream(&"war").randi()
	var copy := KDRng.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	for i in 10:
		assert_eq(copy.stream(&"war").randi(), a.stream(&"war").randi(), "continuation %d" % i)
	assert_eq(copy.campaign_seed, a.campaign_seed)


func test_hash01_range_and_stability() -> void:
	for i in 100:
		var v := KDRng.hash01(i * 7, i * 13, 5)
		assert_true(v >= 0.0 and v < 1.0)
		assert_eq(v, KDRng.hash01(i * 7, i * 13, 5))

