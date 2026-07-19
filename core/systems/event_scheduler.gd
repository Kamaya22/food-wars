class_name EventScheduler
extends RefCounted

static func _phase_window(phase: int) -> String:
    match phase:
        GameState.Phase.PLANNING: return "planning"
        GameState.Phase.EXECUTION: return "execution"
        GameState.Phase.JUDGMENT: return "judgment"
        _: return ""

static func tick(db: ContentDB, state: GameState, delta: float) -> Array:
    var events: Array = []
    if state.phase != GameState.Phase.PLANNING and state.phase != GameState.Phase.EXECUTION:
        return events
    var window := _phase_window(state.phase)
    var candidates: Array = []
    var ids: Array = db.events.keys()
    ids.sort()
    for id in ids:
        if db.events[id].trigger_window == window:
            candidates.append(id)

    var rng := Rng.new(0)
    rng.set_state(state.rng_state)
    state.event_timer_left -= delta
    var w := float(state.config["event_window_sec"])
    while w > 0.0 and state.event_timer_left <= 0.0:
        if not candidates.is_empty():
            var pick: String = candidates[rng.randi_range(0, candidates.size() - 1)]
            var ev: EventRes = db.events[pick]
            for pid in state.player_order:
                EffectResolver.apply(state.players[pid], ev.effect)
            events.append({"type": "event_fired", "event_id": pick, "description": ev.display_name})
        state.event_timer_left += w
    state.rng_state = rng.get_state()
    return events
