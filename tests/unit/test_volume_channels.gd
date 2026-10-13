extends GutTest
## Volume channels (card #104): each setting has its own bus, and percent maps to dB sanely.


func test_every_channel_names_a_key_and_a_bus() -> void:
	var keys: Dictionary = {}
	for channel: String in PlayerSettings.CHANNELS:
		var c: Dictionary = PlayerSettings.CHANNELS[channel]
		assert_false(String(c.key).is_empty(), "%s has a settings key" % channel)
		assert_false(String(c.bus).is_empty(), "%s has a bus" % channel)
		assert_false(keys.has(c.key), "%s's key is its own" % channel)
		keys[c.key] = true
	assert_eq(String(PlayerSettings.CHANNELS.master.bus), "Master")
	assert_eq(String(PlayerSettings.CHANNELS.master.key), PlayerSettings.KEY_VOLUME, "old saved volume still works")


func test_percent_to_db() -> void:
	assert_almost_eq(PlayerSettings.percent_to_db(100), 0.0, 0.001)
	assert_almost_eq(PlayerSettings.percent_to_db(50), -6.02, 0.01)
	assert_true(PlayerSettings.percent_to_db(0) < -30.0, "0 % is very quiet (and the bus is muted)")
	assert_almost_eq(PlayerSettings.percent_to_db(250), 0.0, 0.001, "never louder than full")


func test_unknown_channel_is_ignored() -> void:
	assert_eq(PlayerSettings.channel_percent("nonsense"), PlayerSettings.DEFAULT_VOLUME_PERCENT)
