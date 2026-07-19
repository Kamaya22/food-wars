class_name Dish
extends RefCounted

static func compute(db: ContentDB, player: PlayerState) -> Dictionary:
    var ings: Array = []
    for id in player.ingredients:
        if db.ingredients.has(id):
            ings.append(db.ingredients[id])
    var applied: Array = []
    var upto: int = clampi(player.exec_index, 0, player.timeline.size())
    for i in range(upto):
        var aid: String = player.timeline[i]
        if db.actions.has(aid):
            applied.append(db.actions[aid])
    var base := StatEngine.compute_dish(ings, applied)
    var combined := Stats.add(base, player.stat_modifiers)
    return Stats.clamp_stats(combined, StatEngine.STAT_MIN, StatEngine.STAT_MAX)
