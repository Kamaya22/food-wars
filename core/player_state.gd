class_name PlayerState
extends RefCounted

var budget_left: int = 0
var ingredients: Array = []
var timeline: Array = []
var hand: Array = []
var deck: Array = []
var ready: bool = false
var exec_index: int = 0
var exec_elapsed: float = 0.0
var exec_delay_left: float = 0.0
var stat_modifiers: Dictionary = {}

func to_dict() -> Dictionary:
    return {
        "budget_left": budget_left,
        "ingredients": ingredients.duplicate(),
        "timeline": timeline.duplicate(),
        "hand": hand.duplicate(),
        "deck": deck.duplicate(),
        "ready": ready,
        "exec_index": exec_index,
        "exec_elapsed": exec_elapsed,
        "exec_delay_left": exec_delay_left,
        "stat_modifiers": stat_modifiers.duplicate(),
    }

static func from_dict(d: Dictionary) -> PlayerState:
    var p := PlayerState.new()
    p.budget_left = int(d.get("budget_left", 0))
    p.ingredients = (d.get("ingredients", []) as Array).duplicate()
    p.timeline = (d.get("timeline", []) as Array).duplicate()
    p.hand = (d.get("hand", []) as Array).duplicate()
    p.deck = (d.get("deck", []) as Array).duplicate()
    p.ready = bool(d.get("ready", false))
    p.exec_index = int(d.get("exec_index", 0))
    p.exec_elapsed = float(d.get("exec_elapsed", 0.0))
    p.exec_delay_left = float(d.get("exec_delay_left", 0.0))
    p.stat_modifiers = (d.get("stat_modifiers", {}) as Dictionary).duplicate()
    return p
