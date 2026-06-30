class_name UnitManeuver
## Pure, deterministic helpers for the classic drill maneuvers a move order can
## trigger. Stateless so the choice logic is unit-testable without a SceneTree.
##
## The first maneuver is the SIDE-STEP: a small lateral shift is executed by
## holding facing and shuffling sideways, rather than centre-pivoting the whole line
## to face the destination and back. About-face, file-march pivots, and flank
## wheeling (circumductio) are tracked as follow-ups and will add their own
## classifiers here.

# A move counts as a side-step when its lateral offset (perpendicular to the
# unit's current facing) dominates its forward offset AND the whole move is
# short -- roughly one unit-width. Beyond that distance a lateral move is large
# enough to warrant a file-march pivot (future work) instead of a shuffle.
const SIDESTEP_MAX_DISTANCE := 40.0
# The lateral component must be at least this multiple of the forward component
# for the move to read as a sideways shift rather than a forward/diagonal advance.
const SIDESTEP_LATERAL_RATIO := 2.0


## Whether a move order from `facing` along `move_vec` should be executed as a
## side-step (hold facing, translate) rather than a turn-and-march. `facing` is
## the unit's current heading; `move_vec` is destination minus current position.
static func is_sidestep(facing: Vector2, move_vec: Vector2) -> bool:
	var dist := move_vec.length()
	if facing.length() < 0.01 or dist < 0.01:
		return false
	if dist > SIDESTEP_MAX_DISTANCE:
		return false
	var fwd := facing.normalized()
	var perp := Vector2(-fwd.y, fwd.x)
	var forward := absf(move_vec.dot(fwd))
	var lateral := absf(move_vec.dot(perp))
	return lateral >= forward * SIDESTEP_LATERAL_RATIO
