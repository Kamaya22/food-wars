class_name CardResolver
extends RefCounted

static func target_id(state: GameState, caster_id: String, card: CardRes) -> String:
    if card.target == CardRes.Target.SELF:
        return caster_id
    for id in state.player_order:
        if id != caster_id:
            return id
    return caster_id

static func _current_action(player: PlayerState) -> String:
    if player.exec_index >= 0 and player.exec_index < player.timeline.size():
        return player.timeline[player.exec_index]
    return ""

static func is_playable(state: GameState, caster_id: String, card: CardRes) -> Dictionary:
    if card.type == CardRes.Type.GLOBAL:
        if state.phase == GameState.Phase.PLANNING or state.phase == GameState.Phase.EXECUTION:
            return {"ok": true, "error": ""}
        return {"ok": false, "error": "carte globale hors phase jouable"}
    # CONTEXTUAL
    if state.phase != GameState.Phase.EXECUTION:
        return {"ok": false, "error": "carte contextuelle jouable seulement en exécution"}
    var tid := target_id(state, caster_id, card)
    if _current_action(state.players[tid]) != card.linked_action:
        return {"ok": false, "error": "action liée non en cours sur la cible"}
    return {"ok": true, "error": ""}

static func play(db: ContentDB, state: GameState, caster_id: String, card: CardRes) -> String:
    var tid := target_id(state, caster_id, card)
    EffectResolver.apply(state.players[tid], card.effect)
    return tid
