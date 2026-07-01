extends SceneTree
## Throwaway capture: render the control-bar Formation drop-up with its two new
## shielded stances (Shield Wall, Testudo) and save a PNG for the PR description.
## Not part of the game or CI; run once locally, then delete. See demos/README.md
## "Producing the PNG".
##
##   godot --rendering-driver opengl3 --script tools/demo/_shot_formation_menu.gd

const HUD = preload("res://scripts/HUD.gd")


func _initialize() -> void:
	var win := get_root()
	win.gui_embed_subwindows = true          # draw the popup into this window so it's captured
	win.size = Vector2i(360, 320)
	win.transparent_bg = false

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.13, 0.10)        # a grassy-dark field stand-in
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)

	var hud: HUD = HUD.new()
	win.add_child(hud)
	# Build just the control bar and show it (Battle normally does this on selection).
	hud._build_ctrl_bar()
	hud._ctrl_bar.visible = true

	# Defer the popup so the control bar finishes its first layout pass first.
	_open_menu_then_capture.call_deferred(win, hud)


func _open_menu_then_capture(win: Window, hud) -> void:
	var btn: MenuButton = hud._ctrl_formation_btn
	var popup: PopupMenu = btn.get_popup()
	popup.position = Vector2i(90, 40)
	popup.size = Vector2i(150, 150)
	popup.popup()
	# Let a few frames render so the bar and popup are fully drawn.
	for _i in range(6):
		await process_frame
	var img: Image = win.get_texture().get_image()
	img.save_png("res://demos/shots/formation-menu.png")
	print("saved demos/shots/formation-menu.png  (%dx%d)" % [img.get_width(), img.get_height()])
	quit()
