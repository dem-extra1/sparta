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
	var replay_path := OS.get_environment("SPARTA_DEMO_REPLAY")
	if replay_path != "":
		if Replay.start_playback(replay_path):
			print("[demo] Playing back replay: %s" % replay_path)
		else:
			push_warning("[demo] Could not load replay '%s'; recording a fresh battle instead."
				% replay_path)
	else:
		print("[demo] SPARTA_DEMO_REPLAY unset; recording a fresh battle.")
	# Defer the swap so this bootstrap scene finishes _ready before it's replaced.
	# Movie Maker keeps recording across the scene change.
	call_deferred("_enter_battle")


func _enter_battle() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)
