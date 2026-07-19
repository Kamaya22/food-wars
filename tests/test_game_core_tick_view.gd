extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _fresh() -> GameState:
    return GameCore.start_match(_db, _db.match_config, 5, ["p0", "p1"])

func test_tick_in_execution_advances_actions():
    var s := _fresh()
    PhaseMachine.enter_execution(s)
    s.players["p0"].timeline = ["assaisonner"]   # 15s
    s.phase_time_left = 999.0
    var res := GameCore.tick(_db, s, 20.0)
    var events: Array = res.events
    var completed := events.filter(func(e): return e.type == "action_completed")
    assert_eq(completed.size(), 1)
    assert_eq(s.players["p0"].exec_index, 1)

func test_tick_finished_is_noop():
    var s := _fresh()
    s.phase = GameState.Phase.FINISHED
    var res := GameCore.tick(_db, s, 10.0)
    assert_eq(res.events.size(), 0)

func test_view_hides_opponent_hand():
    var s := _fresh()
    s.players["p0"].hand = ["card_boost_umami"]
    s.players["p1"].hand = ["card_saboter", "card_boost_umami"]
    var view := GameCore.get_view(_db, s, "p0")
    assert_eq(view.you.hand, ["card_boost_umami"])          # ma main : ids visibles
    assert_true(view.opponents.has("p1"))
    var opp: Dictionary = view.opponents["p1"]
    assert_false(opp.has("hand"))                            # main adverse : pas d'ids
    assert_eq(opp.hand_count, 2)                             # seulement le compte
    assert_false(opp.has("deck"))
    assert_eq(opp.deck_count, s.players["p1"].deck.size())

func test_view_exposes_dish():
    var s := _fresh()
    s.players["p0"].ingredients = ["boeuf"]
    var view := GameCore.get_view(_db, s, "p0")
    assert_eq(int(view.you.dish["umami"]), 5)
