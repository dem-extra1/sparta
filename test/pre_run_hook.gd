extends GutHookScript

# GUT pre-run hook: instrument the game scripts for line coverage before the
# suite runs. Paired with test/post_run_hook.gd, which writes the lcov report.
# See test/README.md and addons/coverage/ (jamie-pate/godot-code-coverage).

const Coverage = preload("res://addons/coverage/Coverage.gd")

# Paths skipped when instrumenting. Uses String.match() glob syntax.
const EXCLUDE_PATHS := [
	# Never instrument the test framework, the coverage tool, or the tests and
	# hooks themselves -- reloading a script while it is running crashes Godot.
	"res://addons/*",
	"res://test/*",
	# Autoload singletons (project.godot [autoload]) are already instantiated
	# before this hook runs, so reloading their scripts to instrument them is
	# unreliable and the tool cannot capture their _ready() coverage anyway.
	# Exclude them so the run stays stable; see test/README.md.
	"res://scripts/Settings.gd",
	"res://scripts/Replay.gd",
	"res://scripts/Sfx.gd",
]

func run():
	var coverage = Coverage.new(gut.get_tree(), EXCLUDE_PATHS)
	coverage.instrument_scripts("res://scripts")
