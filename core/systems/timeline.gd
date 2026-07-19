class_name Timeline
extends RefCounted

static func advance(db: ContentDB, player: PlayerState, delta: float) -> Array:
    var completed: Array = []
    var remaining: float = delta
    # 1) consommer le délai en cours
    if player.exec_delay_left > 0.0:
        var d: float = min(player.exec_delay_left, remaining)
        player.exec_delay_left -= d
        remaining -= d
    # 2) faire avancer les actions
    while remaining > 0.0 and player.exec_index < player.timeline.size():
        var action: ActionRes = db.actions[player.timeline[player.exec_index]]
        var dur: float = float(action.base_duration_sec)
        var need: float = dur - player.exec_elapsed
        var step: float = min(need, remaining)
        player.exec_elapsed += step
        remaining -= step
        if player.exec_elapsed >= dur:
            completed.append(player.timeline[player.exec_index])
            player.exec_index += 1
            player.exec_elapsed = 0.0
    return completed

static func advance_all(db: ContentDB, state: GameState, delta: float) -> Array:
    var events: Array = []
    for id in state.player_order:
        var p: PlayerState = state.players[id]
        for action_id in advance(db, p, delta):
            events.append({"type": "action_completed", "player": id, "action_id": action_id})
            if not p.deck.is_empty():
                p.hand.append(p.deck.pop_front())
                events.append({"type": "card_drawn", "player": id})
    return events
