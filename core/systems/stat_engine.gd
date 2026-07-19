class_name StatEngine
extends RefCounted

const STAT_MIN: int = -50
const STAT_MAX: int = 50

static func apply_effect(stats: Dictionary, effect: Dictionary) -> Dictionary:
    var out := Stats.clamp_stats(stats, STAT_MIN, STAT_MAX)
    if effect.has("stats"):
        out = Stats.add(out, effect["stats"])
    return Stats.clamp_stats(out, STAT_MIN, STAT_MAX)

static func compute_dish(ingredients: Array, actions: Array) -> Dictionary:
    var s := Stats.empty()
    for ing in ingredients:
        s = Stats.add(s, ing.stats)
    for act in actions:
        s = apply_effect(s, act.effect)
    return Stats.clamp_stats(s, STAT_MIN, STAT_MAX)
