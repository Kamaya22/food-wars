class_name GameCore
extends RefCounted

static func _config_snapshot(config: MatchConfigRes) -> Dictionary:
    return {
        "ingredient_budget": config.ingredient_budget,
        "ingredients_max": config.ingredients_per_player_max,
        "timeline_max": config.timeline_actions_max,
        "deck_size": config.deck_size_max,
        "starting_hand_size": config.starting_hand_size,
        "planning_sec": config.phase_planning_sec,
        "execution_sec": config.phase_execution_sec,
        "judgment_sec": config.phase_judgment_sec,
        "event_window_sec": config.event_frequency_window_sec,
    }

static func start_match(db: ContentDB, config: MatchConfigRes, seed: int, player_ids: Array) -> GameState:
    var s := GameState.new()
    s.seed = seed
    s.phase = GameState.Phase.PLANNING
    s.player_order = player_ids.duplicate()
    s.config = _config_snapshot(config)
    s.phase_time_left = float(s.config["planning_sec"])
    s.event_timer_left = float(s.config["event_window_sec"])
    s.result = {}

    var rng := Rng.new(seed)
    var card_ids: Array = db.cards.keys()
    card_ids.sort()
    var deck_size: int = int(s.config["deck_size"])
    var hand_size: int = int(s.config["starting_hand_size"])

    for id in player_ids:
        var p := PlayerState.new()
        p.budget_left = int(s.config["ingredient_budget"])
        p.stat_modifiers = Stats.empty()
        if not card_ids.is_empty():
            for i in range(deck_size):
                p.deck.append(card_ids[rng.randi_range(0, card_ids.size() - 1)])
        for i in range(min(hand_size, p.deck.size())):
            p.hand.append(p.deck.pop_front())
        s.players[id] = p

    s.rng_state = rng.get_state()
    return s

static func _result(state: GameState, events: Array) -> Dictionary:
    return {"state": state, "events": events}

static func _reject(state: GameState, reason: String) -> Dictionary:
    return _result(state, [{"type": "intent_rejected", "reason": reason}])

static func apply_intent(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var shape := Intents.validate_shape(intent)
    if not shape.ok:
        return _reject(state, "forme: " + shape.error)
    if not state.players.has(player_id):
        return _reject(state, "joueur inconnu: " + player_id)
    var t: String = intent["type"]

    if state.phase == GameState.Phase.PLANNING:
        match t:
            Intents.ADD_INGREDIENT:
                return _plan_add_ingredient(db, state, player_id, intent)
            Intents.REMOVE_INGREDIENT:
                return _plan_remove_ingredient(db, state, player_id, intent)
            Intents.ADD_ACTION:
                return _plan_add_action(db, state, player_id, intent)
            Intents.REMOVE_ACTION:
                return _plan_remove_action(db, state, player_id, intent)
            Intents.SET_READY:
                state.players[player_id].ready = bool(intent["ready"])
                var ev := [{"type": "ready_changed", "player": player_id, "ready": state.players[player_id].ready}]
                ev.append_array(PhaseMachine.maybe_end_planning(db, state))
                return _result(state, ev)
            Intents.PLAY_CARD:
                return _play_card(db, state, player_id, intent)
            _:
                return _reject(state, "intent non géré en planning: " + t)
    elif state.phase == GameState.Phase.EXECUTION:
        if t == Intents.PLAY_CARD:
            return _play_card(db, state, player_id, intent)
        return _reject(state, "intent non autorisé en exécution: " + t)
    return _reject(state, "aucun intent autorisé dans la phase courante")

static func _plan_add_ingredient(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var id: String = intent["ingredient_id"]
    if not db.ingredients.has(id):
        return _reject(state, "ingrédient inconnu: " + id)
    if p.ingredients.size() >= int(state.config["ingredients_max"]):
        return _reject(state, "limite d'ingrédients atteinte")
    var cost: int = db.ingredients[id].cost
    if cost > p.budget_left:
        return _reject(state, "budget insuffisant")
    p.ingredients.append(id)
    p.budget_left -= cost
    return _result(state, [{"type": "ingredient_added", "player": player_id, "ingredient_id": id}])

static func _plan_remove_ingredient(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var idx: int = intent["index"]
    if idx < 0 or idx >= p.ingredients.size():
        return _reject(state, "index d'ingrédient invalide")
    var id: String = p.ingredients[idx]
    p.ingredients.remove_at(idx)
    p.budget_left += db.ingredients[id].cost
    return _result(state, [{"type": "ingredient_removed", "player": player_id, "ingredient_id": id}])

static func _plan_add_action(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var id: String = intent["action_id"]
    if not db.actions.has(id):
        return _reject(state, "action inconnue: " + id)
    if p.timeline.size() >= int(state.config["timeline_max"]):
        return _reject(state, "limite d'actions atteinte")
    p.timeline.append(id)
    return _result(state, [{"type": "action_added", "player": player_id, "action_id": id}])

static func _plan_remove_action(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var idx: int = intent["index"]
    if idx < 0 or idx >= p.timeline.size():
        return _reject(state, "index d'action invalide")
    var id: String = p.timeline[idx]
    p.timeline.remove_at(idx)
    return _result(state, [{"type": "action_removed", "player": player_id, "action_id": id}])

# TEMPORARY STUB (Task 6 provides the real implementation): jouer une carte
# n'est pas encore implémenté. Ce stub permet à apply_intent de compiler et
# de rejeter proprement PLAY_CARD tant que la Task 6 n'est pas faite.
static func _play_card(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    return _reject(state, "cartes non implémentées")
