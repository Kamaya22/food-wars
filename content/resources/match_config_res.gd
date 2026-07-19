class_name MatchConfigRes
extends Resource

var ingredient_budget: int
var ingredients_per_player_min: int
var ingredients_per_player_max: int
var timeline_actions_min: int
var timeline_actions_max: int
var deck_size_min: int
var deck_size_max: int
var starting_hand_size: int
var phase_planning_sec: int
var phase_execution_sec: int
var phase_judgment_sec: int
var event_frequency_window_sec: int

static func from_dict(d: Dictionary) -> MatchConfigRes:
    var r := MatchConfigRes.new()
    r.ingredient_budget = int(d.get("ingredient_budget", 0))
    var ipp: Dictionary = d.get("ingredients_per_player", {})
    r.ingredients_per_player_min = int(ipp.get("min", 0))
    r.ingredients_per_player_max = int(ipp.get("max", 0))
    var ta: Dictionary = d.get("timeline_actions", {})
    r.timeline_actions_min = int(ta.get("min", 0))
    r.timeline_actions_max = int(ta.get("max", 0))
    var ds: Dictionary = d.get("deck_size", {})
    r.deck_size_min = int(ds.get("min", 0))
    r.deck_size_max = int(ds.get("max", 0))
    r.starting_hand_size = int(d.get("starting_hand_size", 0))
    var pd: Dictionary = d.get("phase_durations", {})
    r.phase_planning_sec = int(pd.get("planning", 0))
    r.phase_execution_sec = int(pd.get("execution", 0))
    r.phase_judgment_sec = int(pd.get("judgment", 0))
    r.event_frequency_window_sec = int(d.get("event_frequency_window_sec", 0))
    return r
