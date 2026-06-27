extends Node
## Headless entry point for recording gameplay demos in CI (see demos/README.md).
##
## Set as the main scene under Godot's Movie Maker mode (`--write-movie`). It arms
## deterministic replay playback from the file named in the SPARTA_DEMO_REPLAY
## environment variable, then switches to the battle scene — so the recorded movie
## shows that exact, reproducible battle.
##
## This is tooling, not gameplay: nothing in the live game references it and it
## changes no simulation code. If SPARTA_DEMO_REPLAY is unset or the file can't be
## loaded, it falls back to recording a fresh (randomly seeded) battle.

const BATTLE_SCENE := "res://scenes/Battle.tscn"


func _ready() -> void:
	# A recording should carry the game's sound. Movie Maker mixes whatever the
	# AudioServer plays into the movie's audio track, but SFX default to off
	# (Settings.sfx_enabled), so a fresh run — CI has no settings.cfg — would capture
	# silence. Turn SFX on for the recording, session-only so running the recorder
	# locally never rewrites a developer's saved preference. Sfx is presentation-only
	# (its own RNG), so this never affects replay determinism — it only adds the
	# audio that gets captured.
	Settings.set_sfx_enabled_session(true)

	var replay_path := OS.get_environment("SPARTA_DEMO_REPLAY")
	if replay_path != "":
		if Replay.start_playback(replay_path):
			# Reproduce the recorded camera framing (pan/zoom) in the clip; a replay with
			# no presentation track still plays with the default static camera.
			Replay.drive_camera = true
			# Show the order overlay (move/attack/waypoint markers) so the clip reveals
			# what was commanded, not just the resulting moves. In-app Watch Replay leaves
			# this off (orders stay on the Space-held survey).
			Replay.show_demo_orders = true
			print("[demo] Playing back replay: %s" % replay_path)
		else:
			push_warning("[demo] Could not load replay '%s'; recording a fresh battle instead."
				% replay_path)
	else:
		print("[demo] SPARTA_DEMO_REPLAY unset; recording a fresh battle.")
	# Defer the swap so this bootstrap scene finishes _ready before it's replaced.
	# Movie Maker keeps recording across the scene change.
	_enter_battle.call_deferred()


func _enter_battle() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)
