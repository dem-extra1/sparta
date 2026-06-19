extends Node
## Sound-effects player (autoload singleton: "Sfx").
##
## Presentation-only: playing a sound never touches the deterministic simulation
## or the seeded Replay RNG, so Sfx.play() is safe to call from sim code
## (Unit/Battle) without affecting replay determinism. Repeats of the same event
## are throttled by wall-clock time so dozens of simultaneous combat hits don't
## stack into a roar.
##
## Sounds are procedural placeholders synthesised at startup — no audio assets are
## bundled (this prototype's CI sandbox can't fetch any). If a file exists at
## res://assets/sfx/<name>.{wav,ogg} it is used INSTEAD of the synth, so curated
## open-access (CC0) audio can be dropped in later with no code change. See the
## "improve sound effects" follow-up issue and assets/sfx/README.md.

const ASSET_DIR := "res://assets/sfx"
const VOICES := 8            # concurrent AudioStreamPlayers (overlapping sounds)
const MIX_RATE := 22050

# Every event Sfx knows how to play.
const NAMES: Array[StringName] = [
	&"hit", &"shoot", &"rout", &"death", &"select", &"order", &"victory", &"defeat",
]

# Per-event minimum gap (seconds) between plays, so rapid repeats (e.g. a melee
# line trading blows every tick) don't pile up. 0 = never throttled.
const THROTTLE := {
	&"hit": 0.06,
	&"shoot": 0.08,
	&"rout": 0.20,
	&"death": 0.12,
	&"select": 0.0,
	&"order": 0.0,
	&"victory": 0.0,
	&"defeat": 0.0,
}

var _streams: Dictionary = {}        # StringName -> AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last_played: Dictionary = {}    # StringName -> msec
# Presentation-only RNG for playback pitch jitter. Deliberately NOT Replay.rng —
# touching the seeded sim stream here would desync replays.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # sounds keep firing while paused
	for _i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_build_sounds()
	_rng.randomize()


## Play the named sound (one of NAMES). No-op if SFX are disabled, the name is
## unknown, or the same event played within its throttle window. pitch_jitter
## randomises pitch ±fraction so repeats don't sound mechanically identical.
func play(name: StringName, pitch_jitter: float = 0.06) -> void:
	if not Settings.sfx_enabled:
		return
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var now: int = Time.get_ticks_msec()
	var gap_ms: float = float(THROTTLE.get(name, 0.0)) * 1000.0
	if gap_ms > 0.0 and now - int(_last_played.get(name, -1000000)) < gap_ms:
		return
	_last_played[name] = now
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	voice.play()


# --- sound construction ----------------------------------------------------

func _build_sounds() -> void:
	# Deterministic synthesis: seed the noise so the placeholder set sounds the
	# same every run (playback pitch jitter is randomised separately, after this).
	_rng.seed = 1
	for name in NAMES:
		var asset := _load_asset(name)
		_streams[name] = asset if asset != null else _synth(name)


## Prefer a real audio file under assets/sfx/ if present (the drop-in upgrade
## path), falling back to the synthesised placeholder otherwise.
func _load_asset(name: StringName) -> AudioStream:
	for ext in ["wav", "ogg"]:
		var path: String = "%s/%s.%s" % [ASSET_DIR, name, ext]
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is AudioStream:
				return res
	return null


## Build a placeholder sound for an event from one or more decaying "blips".
func _synth(name: StringName) -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	match name:
		&"hit":   # melee thud: low body + a noise transient
			buf = _blip(buf, 0.0, 0.12, 180.0, 90.0, "sine", 0.7)
			buf = _blip(buf, 0.0, 0.04, 0.0, 0.0, "noise", 0.25)
		&"shoot":   # arrow: bright down-sweep + airy noise
			buf = _blip(buf, 0.0, 0.10, 1300.0, 420.0, "saw", 0.4)
			buf = _blip(buf, 0.0, 0.04, 0.0, 0.0, "noise", 0.3)
		&"rout":   # falling whistle
			buf = _blip(buf, 0.0, 0.30, 520.0, 160.0, "square", 0.35)
		&"death":   # low descending knell
			buf = _blip(buf, 0.0, 0.28, 220.0, 70.0, "sine", 0.6)
		&"select":   # short crisp click
			buf = _blip(buf, 0.0, 0.05, 900.0, 900.0, "square", 0.3)
		&"order":   # short up-blip (acknowledge)
			buf = _blip(buf, 0.0, 0.06, 600.0, 760.0, "square", 0.3)
		&"victory":   # rising C-E-G arpeggio
			buf = _blip(buf, 0.00, 0.16, 523.0, 523.0, "square", 0.4)
			buf = _blip(buf, 0.12, 0.16, 659.0, 659.0, "square", 0.4)
			buf = _blip(buf, 0.24, 0.30, 784.0, 784.0, "square", 0.4)
		&"defeat":   # falling G-Eb-Bb arpeggio
			buf = _blip(buf, 0.00, 0.20, 392.0, 392.0, "saw", 0.4)
			buf = _blip(buf, 0.18, 0.20, 311.0, 311.0, "saw", 0.4)
			buf = _blip(buf, 0.36, 0.40, 233.0, 233.0, "saw", 0.4)
		_:
			push_warning("Sfx._synth: no waveform defined for event '%s'" % name)
	return _make_wav(buf)


## Add one decaying tone/noise burst into buf (grown as needed) and return it.
## Callers reassign (buf = _blip(buf, ...)) so the result is correct regardless of
## GDScript's packed-array copy-on-write. Frequency sweeps linearly f0 -> f1 across
## the blip; amplitude decays over its length.
func _blip(buf: PackedFloat32Array, start_s: float, dur: float,
		f0: float, f1: float, kind: String, amp: float) -> PackedFloat32Array:
	var n: int = int(dur * MIX_RATE)
	var start_i: int = int(start_s * MIX_RATE)
	if buf.size() < start_i + n:
		buf.resize(start_i + n)
	var phase: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var freq: float = lerpf(f0, f1, t)
		phase += TAU * freq / float(MIX_RATE)
		var w: float
		match kind:
			"sine": w = sin(phase)
			"square": w = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw": w = fmod(phase / TAU, 1.0) * 2.0 - 1.0
			"noise": w = _rng.randf_range(-1.0, 1.0)
			_:
				push_warning("Sfx._blip: unknown waveform kind '%s'; using sine" % kind)
				w = sin(phase)
		buf[start_i + i] += w * pow(1.0 - t, 2.0) * amp   # squared decay envelope
	return buf


## Pack mono float samples (-1..1) into a 16-bit PCM AudioStreamWAV.
func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	return wav
