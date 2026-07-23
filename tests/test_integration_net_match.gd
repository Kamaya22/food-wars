extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _make() -> Dictionary:
    var state := GameCore.start_match(_db, _db.match_config, 2024, ["p0", "p1"])
    var pair := InMemoryTransport.pair("p0", "p1")
    var host := NetSession.create_host(_db, state, pair[0], "p0", ["p1"])
    var guest := NetSession.create_guest(_db, pair[1], "p1", "p0")
    return {"host": host, "guest": guest}

func test_full_networked_match_converges_and_produces_winner():
    var w := _make()
    var host: NetSession = w.host
    var guest: NetSession = w.guest

    # --- PLANNING : p0 via l'hôte, p1 via l'invité ---
    host.host_apply_local({"type": Intents.ADD_INGREDIENT, "ingredient_id": "boeuf"})
    host.host_apply_local({"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    host.host_apply_local({"type": Intents.ADD_ACTION, "action_id": "cuire"})
    host.host_apply_local({"type": Intents.ADD_ACTION, "action_id": "assaisonner"})
    guest.send_intent({"type": Intents.ADD_INGREDIENT, "ingredient_id": "citron"})
    guest.send_intent({"type": Intents.ADD_INGREDIENT, "ingredient_id": "sucre"})
    guest.send_intent({"type": Intents.ADD_ACTION, "action_id": "mixer"})

    # Un intent invalide de l'invité doit être corrigé (rollback), sans casser l'état.
    guest.send_intent({"type": "type_bidon"})
    assert_eq(guest.reconciler.pending_count(), 0, "intent invalide acké/rollback")

    host.host_apply_local({"type": Intents.SET_READY, "ready": true})
    guest.send_intent({"type": Intents.SET_READY, "ready": true})
    assert_eq(host.host_state().phase, GameState.Phase.EXECUTION, "les deux prêts → exécution")

    # --- EXECUTION + JUDGMENT : l'hôte pilote le temps ---
    var guard := 0
    while host.host_state().phase != GameState.Phase.FINISHED and guard < 100000:
        host.host_tick(1.0)
        guard += 1
    assert_eq(host.host_state().phase, GameState.Phase.FINISHED, "le match se termine")

    # --- Autorité : résultat attendu (p0 boeuf/tomate cuit+assaisonné bat p1) ---
    var result: Dictionary = host.host_state().result
    assert_true(result.has("winner"))
    assert_eq(result["winner"], "p0", "scores=%s" % str(result.get("scores", {})))

    # --- Convergence : la vue réconciliée de l'invité == vue autoritaire filtrée pour p1 ---
    assert_eq(guest.reconciler.current_view(), host.host_view_for("p1"),
        "l'invité converge sur l'état autoritaire")
    assert_eq(guest.reconciler.current_view().phase, GameState.Phase.FINISHED)

func test_guest_view_never_contains_opponent_hand():
    var w := _make()
    var host: NetSession = w.host
    var guest: NetSession = w.guest
    host.host_apply_local({"type": Intents.SET_READY, "ready": false})  # force une diffusion
    var opp: Dictionary = guest.reconciler.current_view().opponents["p0"]
    assert_false(opp.has("hand"), "la main de l'hôte ne doit jamais fuir vers l'invité")
