class_name PhaseMachine
extends RefCounted

static func _all_ready(state: GameState) -> bool:
    for id in state.player_order:
        if not state.players[id].ready:
            return false
    return true

static func maybe_end_planning(db: ContentDB, state: GameState) -> Array:
    if state.phase != GameState.Phase.PLANNING:
        return []
    if state.phase_time_left <= 0.0 or _all_ready(state):
        enter_execution(state)
        return [{"type": "phase_changed", "from": GameState.Phase.PLANNING, "to": GameState.Phase.EXECUTION}]
    return []

static func enter_execution(state: GameState) -> void:
    for id in state.player_order:
        var p: PlayerState = state.players[id]
        p.exec_index = 0
        p.exec_elapsed = 0.0
        p.exec_delay_left = 0.0
    state.phase = GameState.Phase.EXECUTION
    state.phase_time_left = float(state.config["execution_sec"])
    state.event_timer_left = float(state.config["event_window_sec"])

static func enter_judgment(db: ContentDB, state: GameState) -> Array:
    var ids: Array = state.player_order
    var dishes: Dictionary = {}
    for id in ids:
        dishes[id] = Dish.compute(db, state.players[id])
    var criteria: Array = db.criteria.values()
    var scores: Dictionary = {}
    var winner := ""
    if ids.size() == 2:
        var verdict := JudgmentEngine.judge(dishes[ids[0]], dishes[ids[1]], criteria)
        scores[ids[0]] = verdict["score_a"]
        scores[ids[1]] = verdict["score_b"]
        if verdict["winner"] == "a":
            winner = ids[0]
        elif verdict["winner"] == "b":
            winner = ids[1]
    else:
        for id in ids:
            scores[id] = JudgmentEngine.score_dish(dishes[id], criteria)
    state.result = {"scores": scores, "winner": winner}
    var from_phase := state.phase
    state.phase = GameState.Phase.JUDGMENT
    state.phase_time_left = float(state.config["judgment_sec"])
    return [
        {"type": "phase_changed", "from": from_phase, "to": GameState.Phase.JUDGMENT},
        {"type": "judged", "result": state.result},
    ]

static func advance_timers(db: ContentDB, state: GameState, delta: float) -> Array:
    match state.phase:
        GameState.Phase.PLANNING:
            state.phase_time_left -= delta
            return maybe_end_planning(db, state)
        GameState.Phase.EXECUTION:
            state.phase_time_left -= delta
            if state.phase_time_left <= 0.0:
                return enter_judgment(db, state)
            return []
        GameState.Phase.JUDGMENT:
            state.phase_time_left -= delta
            if state.phase_time_left <= 0.0:
                state.phase = GameState.Phase.FINISHED
                return [
                    {"type": "phase_changed", "from": GameState.Phase.JUDGMENT, "to": GameState.Phase.FINISHED},
                    {"type": "match_finished", "result": state.result},
                ]
            return []
        _:
            return []
