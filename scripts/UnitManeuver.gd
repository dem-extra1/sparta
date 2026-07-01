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

# A move counts as "to the rear" when its destination lies behind the unit -- more
# than this angle off the current facing. At 135° the rear quadrant (the back 90°
# arc) triggers an about-face (conversio) instead of a 180° centre pivot: the block
# reverses man-for-man where it stands, then marches to the destination facing it.
const REAR_MOVE_MIN_ANGLE_DEG := 135.0


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


## Whether a move order from `facing` along `move_vec` heads into the unit's rear
## sector -- the destination lies more than REAR_MOVE_MIN_ANGLE_DEG behind the
## current heading. Such a move about-faces (conversio) then marches, rather than
## pivoting the whole block 180° about its centre. `facing` is the current heading;
## `move_vec` is destination minus current position. Degenerate inputs (no facing,
## a zero-length move) are not rear moves.
static func is_rear_move(facing: Vector2, move_vec: Vector2) -> bool:
	if facing.length() < 0.01 or move_vec.length() < 0.01:
		return false
	var angle := rad_to_deg(absf(facing.angle_to(move_vec)))
	return angle >= REAR_MOVE_MIN_ANGLE_DEG
