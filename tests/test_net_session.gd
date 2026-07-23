extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _wire() -> Dictionary:
    # Hôte "p0" + invité "p1" reliés par un transport en mémoire.
    var state := GameCore.start_match(_db, _db.match_config, 2024, ["p0", "p1"])
    var pair := InMemoryTransport.pair("p0", "p1")
    var host := NetSession.create_host(_db, state, pair[0], "p0", ["p1"])
    var guest := NetSession.create_guest(_db, pair[1], "p1", "p0")
    return {"state": state, "host": host, "guest": guest}

func test_guest_intent_reaches_host_and_snapshot_returns():
    var w := _wire()
    var guest: NetSession = w.guest
    var host: NetSession = w.host
    var seq := guest.send_intent({"type": Intents.ADD_INGREDIENT, "ingredient_id": "citron"})
    assert_eq(seq, 1)
    # Le transport est synchrone : l'invité a déjà reçu son snapshot autoritaire.
    assert_eq(guest.reconciler.current_view(), host.host_view_for("p1"))
    assert_eq(guest.reconciler.pending_count(), 0, "l'intent traité est acké → file vidée")

func test_host_local_intent_broadcasts_to_guest():
    var w := _wire()
    var host: NetSession = w.host
    var guest: NetSession = w.guest
    host.host_apply_local({"type": Intents.ADD_INGREDIENT, "ingredient_id": "boeuf"})
    var opp: Dictionary = guest.reconciler.current_view().opponents["p0"]
    assert_true("boeuf" in opp.ingredients, "l'invité voit l'ingrédient public de l'hôte")

func test_invalid_guest_intent_is_corrected():
    var w := _wire()
    var guest: NetSession = w.guest
    var host: NetSession = w.host
    guest.send_intent({"type": "type_bidon"})   # forme invalide → rejet côté hôte
    assert_eq(guest.reconciler.pending_count(), 0, "intent rejeté acké → rollback")
    assert_eq(guest.reconciler.current_view(), host.host_view_for("p1"),
        "la vue de l'invité reste l'état autoritaire (inchangé)")

func test_host_tick_broadcasts_snapshot():
    var w := _wire()
    var host: NetSession = w.host
    var guest: NetSession = w.guest
    var before := guest.reconciler.current_tick_id()
    host.host_tick(1.0)
    assert_gt(guest.reconciler.current_tick_id(), before, "un tick diffuse un nouveau snapshot")

func test_guest_receives_events():
    var w := _wire()
    var host: NetSession = w.host
    var guest: NetSession = w.guest
    host.host_apply_local({"type": Intents.SET_READY, "ready": true})
    assert_true(guest.last_events.size() >= 1, "les events sont transmis à l'invité")

func test_host_emits_paused_on_guest_drop():
    var w := _wire()
    var host: NetSession = w.host
    var paused: Array = []
    host.session_paused.connect(func(pid): paused.append(pid))
    (w.guest.transport() as InMemoryTransport).drop()
    assert_eq(paused, ["p1"])

func test_guest_emits_aborted_on_host_drop():
    var w := _wire()
    var guest: NetSession = w.guest
    var aborted: Array = []
    guest.session_aborted.connect(func(reason): aborted.append(reason))
    (w.host.transport() as InMemoryTransport).drop()
    assert_eq(aborted, ["host_disconnected"])
