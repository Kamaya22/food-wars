class_name EffectResolver
extends RefCounted

static func apply(player: PlayerState, effect: Dictionary) -> String:
    if effect.has("stats"):
        player.stat_modifiers = Stats.add(player.stat_modifiers, effect["stats"])
        return "stats"
    if effect.has("rule"):
        match String(effect["rule"]):
            "delay_execution_seconds":
                player.exec_delay_left += float(effect.get("value", 0))
                return "delay"
            _:
                return "noop"
    return "noop"
