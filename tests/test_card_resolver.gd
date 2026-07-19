extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _fresh() -> GameState:
    return GameCore.start_match(_db, _db.match_config, 5, ["p0", "p1"])

func _events_of(res: Dictionary, type: String) -> Array:
    var out := []
    for e in res.events:
        if e.type == type: out.append(e)
    return out

func test_global_card_targets_self_and_applies():
    var s := _fresh()
    s.players["p0"].stat_modifiers = Stats.empty()
    s.players["p0"].hand = ["card_boost_umami"]  # global/self, {stats:{umami:2}}
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.PLAY_CARD, "card_id": "card_boost_umami"})
    assert_eq(_events_of(res, "card_played").size(), 1)
    assert_eq(int(s.players["p0"].stat_modifiers["umami"]), 2)
    assert_false(s.players["p0"].hand.has("card_boost_umami"))

func test_card_not_in_hand_rejected():
    var s := _fresh()
    s.players["p0"].hand = []
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.PLAY_CARD, "card_id": "card_boost_umami"})
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_contextual_card_rejected_in_planning():
    var s := _fresh()
    s.players["p0"].hand = ["card_saboter"]  # contextual, linked_action=cuire, target opponent
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.PLAY_CARD, "card_id": "card_saboter"})
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_contextual_card_applies_when_linked_action_runs_on_target():
    var s := _fresh()
    s.phase = GameState.Phase.EXECUTION
    s.players["p0"].hand = ["card_saboter"]     # target opponent, linked cuire, {stats:{acide:2}}
    s.players["p1"].stat_modifiers = Stats.empty()
    s.players["p1"].timeline = ["cuire"]
    s.players["p1"].exec_index = 0              # "cuire" est l'action courante de p1
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.PLAY_CARD, "card_id": "card_saboter"})
    assert_eq(_events_of(res, "card_played").size(), 1)
    assert_eq(int(s.players["p1"].stat_modifiers["acide"]), 2)

func test_target_id_helper():
    var s := _fresh()
    assert_eq(CardResolver.target_id(s, "p0", _db.cards["card_saboter"]), "p1")
    assert_eq(CardResolver.target_id(s, "p0", _db.cards["card_boost_umami"]), "p0")
