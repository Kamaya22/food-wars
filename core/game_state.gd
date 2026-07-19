class_name GameState
extends RefCounted

enum Phase { PLANNING, EXECUTION, JUDGMENT, FINISHED }

var seed: int = 0
var rng_state: int = 0
var phase: int = Phase.PLANNING
var phase_time_left: float = 0.0
var event_timer_left: float = 0.0
var player_order: Array = []
var players: Dictionary = {}
var config: Dictionary = {}
var result: Dictionary = {}

func to_dict() -> Dictionary:
    var pl: Dictionary = {}
    for id in players:
        pl[id] = players[id].to_dict()
    return {
        "seed": seed,
        "rng_state": rng_state,
        "phase": phase,
        "phase_time_left": phase_time_left,
        "event_timer_left": event_timer_left,
        "player_order": player_order.duplicate(),
        "players": pl,
        "config": config.duplicate(),
        "result": result.duplicate(),
    }

static func from_dict(d: Dictionary) -> GameState:
    var s := GameState.new()
    s.seed = int(d.get("seed", 0))
    s.rng_state = int(d.get("rng_state", 0))
    s.phase = int(d.get("phase", Phase.PLANNING))
    s.phase_time_left = float(d.get("phase_time_left", 0.0))
    s.event_timer_left = float(d.get("event_timer_left", 0.0))
    s.player_order = (d.get("player_order", []) as Array).duplicate()
    s.config = (d.get("config", {}) as Dictionary).duplicate()
    s.result = (d.get("result", {}) as Dictionary).duplicate()
    var pl: Dictionary = d.get("players", {})
    for id in pl:
        s.players[id] = PlayerState.from_dict(pl[id])
    return s
