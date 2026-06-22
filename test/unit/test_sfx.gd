extends GutTest
## Sound-effects autoload. Exercises the Sfx singleton's stream
## construction and the play() gating/throttle logic. Playback itself produces no
## audible output under the headless dummy driver, so "did it play" is observed
## via _next_voice advancing (play() consumes the next voice only when it fires).

func before_each() -> void:
	Settings.sfx_enabled = true   # reset the gate before each case


func after_each() -> void:
	# _last_played is shared singleton state on the Sfx autoload; clear it so a
	# throttle timestamp seeded by one test can't surprise a later one.
	Sfx._last_played.clear()


func test_every_event_has_a_stream() -> void:
	for name in Sfx.NAMES:
		assert_true(Sfx._streams.get(name) is AudioStream,
			"event %s has a built AudioStream" % name)


func test_synth_produces_nonempty_wav() -> void:
	# Each placeholder synthesises a non-empty 16-bit PCM WAV (asset-independent).
	for name in Sfx.NAMES:
		var w: AudioStreamWAV = Sfx._synth(name)
		assert_not_null(w, "%s synth returned null — add a _synth arm for it" % name)
		if w == null:
			continue
		assert_eq(w.format, AudioStreamWAV.FORMAT_16_BITS, "%s synth is 16-bit PCM" % name)
		assert_gt(w.data.size(), 0, "%s synth has samples" % name)


func test_play_consumes_a_voice_when_enabled() -> void:
	var v0: int = Sfx._next_voice
	Sfx.play(&"select")   # "select" is never throttled
	assert_eq(Sfx._next_voice, (v0 + 1) % Sfx._voices.size(),
		"an enabled, un-throttled play advances to the next voice")


func test_play_is_silent_when_disabled() -> void:
	Settings.sfx_enabled = false
	var v0: int = Sfx._next_voice
	Sfx.play(&"select")
	assert_eq(Sfx._next_voice, v0, "no voice is consumed when SFX are disabled")


func test_throttled_repeat_is_suppressed() -> void:
	Sfx._last_played[&"hit"] = Time.get_ticks_msec()   # pretend "hit" just fired
	var v0: int = Sfx._next_voice
	Sfx.play(&"hit")
	assert_eq(Sfx._next_voice, v0, "a repeat within the throttle window is suppressed")


func test_throttled_event_fires_after_window() -> void:
	Sfx._last_played[&"hit"] = Time.get_ticks_msec() - 10000   # window long expired
	var v0: int = Sfx._next_voice
	Sfx.play(&"hit")
	assert_eq(Sfx._next_voice, (v0 + 1) % Sfx._voices.size(),
		"a throttled event fires again once its window has expired")


func test_unknown_name_plays_nothing() -> void:
	var v0: int = Sfx._next_voice
	Sfx.play(&"does_not_exist")
	assert_eq(Sfx._next_voice, v0, "an unknown sound name is a no-op")
