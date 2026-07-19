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
