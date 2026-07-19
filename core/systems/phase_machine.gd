class_name PhaseMachine
extends RefCounted

# TEMPORARY STUB (Task 9 provides the real implementation): la transition
# automatique planning -> exécution n'est pas encore gérée. Ce stub permet
# à GameCore.apply_intent (SET_READY) de compiler dès la Task 4.
static func maybe_end_planning(db: ContentDB, state: GameState) -> Array:
    return []
