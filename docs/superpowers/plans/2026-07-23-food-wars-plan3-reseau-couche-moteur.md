# Plan 3 — Réseau (couche moteur) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construire la couche réseau côté Godot (session, transport abstrait, protocole, réconciliation) entièrement testable en headless, sans socket réel ni serveur relais.

**Architecture:** Autorité hôte : l'hôte détient l'unique `GameState` et applique le Cœur (`GameCore`) inchangé ; les invités sont de purs consommateurs de vue. Tout passe par `NetSession`, qui parle à une interface `ITransport` (implémentée en test par `InMemoryTransport`, faux relais synchrone). Les messages sont des `Dictionary` construits/lus par `Protocol` ; le `Reconciler` côté client garde la dernière `PlayerView` autoritaire et gère le rollback optimiste.

**Tech Stack:** Godot 4 / GDScript, GUT (Godot Unit Test) pour les tests headless.

**Spec de référence :** `docs/superpowers/specs/2026-07-23-food-wars-networking-design.md`

## Global Constraints

- **Aucune modification de `core/`.** Le Cœur est consommé uniquement via `GameCore.start_match / apply_intent / tick / get_view` et `GameState.to_dict / from_dict`.
- `apply_intent(db, state, player_id, intent)` et `tick(db, state, delta)` renvoient `{state: GameState, events: Array}`. Un intent invalide renvoie l'état **inchangé** + un event `{type: "intent_rejected", reason: String}`.
- `get_view(db, state, viewer_id)` renvoie `{phase, phase_time_left, result, you, opponents}` ; le filtrage anti-triche (main adverse masquée) y est déjà fait.
- **Déterminisme :** itération triée sur `player_order` pour la diffusion ; aucune horloge murale — les tests pilotent `host_tick(delta)` explicitement.
- `net/` ne dépend jamais de la Présentation (Plan 4) : le `Reconciler` expose un view-model, il ne dessine rien.
- Accès aux champs de `Dictionary` par point (`res.state`, `shape.ok`) — idiome déjà utilisé dans `core/`.
- Chaque fichier `.gd` a un `.gd.uid` généré par Godot au premier import/exécution ; committer les deux (comme les commits des Plans 1 & 2).
- Suite complète : `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` (remplacer `godot` par le chemin du binaire Godot 4 si besoin). Fichier unique : ajouter `-gtest=res://tests/<fichier>.gd`.

---

## File Structure

**À créer :**
- `net/protocol.gd` — constantes de types de messages + constructeurs/lecteurs de messages (fonctions statiques pures).
- `net/i_transport.gd` — interface `ITransport` : `send()` + signaux `message_received` / `peer_connected` / `peer_disconnected`.
- `net/in_memory_transport.gd` — `InMemoryTransport extends ITransport` : faux relais synchrone en mémoire pour les tests.
- `net/reconciler.gd` — magasin de view-model côté client (dernière `PlayerView` + rollback des intents en attente).
- `net/net_session.gd` — `NetSession` : logique hôte & invité ; seul point de contact Présentation/Cœur.

**Tests à créer :**
- `tests/test_protocol.gd`
- `tests/test_in_memory_transport.gd`
- `tests/test_reconciler.gd`
- `tests/test_net_session.gd`
- `tests/test_integration_net_match.gd` (test phare)

**Ordre des tâches (dépendances) :** Protocol → ITransport/InMemoryTransport → Reconciler → NetSession → Intégration.

---

## Task 1 : Protocol (constructeurs & lecteurs de messages)

**Files:**
- Create: `net/protocol.gd`
- Test: `tests/test_protocol.gd`

**Interfaces:**
- Consumes: rien (fonctions pures sur `Dictionary`).
- Produces:
  - Constantes `Protocol.KIND_ROOM`, `KIND_INTENT`, `KIND_SNAPSHOT`, `KIND_EVENTS` (String).
  - `Protocol.build_room(role: int, seed_value: int, opponent_id: String) -> Dictionary`
  - `Protocol.build_intent(seq: int, intent: Dictionary) -> Dictionary`
  - `Protocol.build_snapshot(view: Dictionary, tick_id: int, ack_seq: int) -> Dictionary`
  - `Protocol.build_events(events: Array) -> Dictionary`
  - `Protocol.kind_of(msg: Dictionary) -> String`
  - `Protocol.read_room(msg) -> Dictionary` → `{role:int, seed:int, opponent_id:String}`
  - `Protocol.read_intent(msg) -> Dictionary` → `{seq:int, intent:Dictionary}`
  - `Protocol.read_snapshot(msg) -> Dictionary` → `{view:Dictionary, tick_id:int, ack_seq:int}`
  - `Protocol.read_events(msg) -> Array`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `tests/test_protocol.gd`:

```gdscript
extends GutTest

func test_intent_round_trip():
    var intent := {"type": "add_ingredient", "ingredient_id": "boeuf"}
    var msg := Protocol.build_intent(7, intent)
    assert_eq(Protocol.kind_of(msg), Protocol.KIND_INTENT)
    var r := Protocol.read_intent(msg)
    assert_eq(r.seq, 7)
    assert_eq(r.intent, intent)

func test_snapshot_round_trip():
    var view := {"phase": 1, "you": {"budget_left": 4}}
    var msg := Protocol.build_snapshot(view, 12, 3)
    assert_eq(Protocol.kind_of(msg), Protocol.KIND_SNAPSHOT)
    var r := Protocol.read_snapshot(msg)
    assert_eq(r.view, view)
    assert_eq(r.tick_id, 12)
    assert_eq(r.ack_seq, 3)

func test_events_round_trip():
    var events := [{"type": "ready_changed", "player": "p0"}]
    var msg := Protocol.build_events(events)
    assert_eq(Protocol.kind_of(msg), Protocol.KIND_EVENTS)
    assert_eq(Protocol.read_events(msg), events)

func test_room_round_trip():
    var msg := Protocol.build_room(0, 2024, "p1")
    assert_eq(Protocol.kind_of(msg), Protocol.KIND_ROOM)
    var r := Protocol.read_room(msg)
    assert_eq(r.role, 0)
    assert_eq(r.seed, 2024)
    assert_eq(r.opponent_id, "p1")

func test_kind_of_unknown_message_is_empty():
    assert_eq(Protocol.kind_of({}), "")
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_protocol.gd -gexit`
Expected: FAIL — `Identifier "Protocol" not declared` (la classe n'existe pas encore).

- [ ] **Step 3: Implémenter `net/protocol.gd`**

```gdscript
class_name Protocol
extends RefCounted

const KIND_ROOM := "room"
const KIND_INTENT := "intent"
const KIND_SNAPSHOT := "snapshot"
const KIND_EVENTS := "events"

static func build_room(role: int, seed_value: int, opponent_id: String) -> Dictionary:
    return {"kind": KIND_ROOM, "role": role, "seed": seed_value, "opponent_id": opponent_id}

static func build_intent(seq: int, intent: Dictionary) -> Dictionary:
    return {"kind": KIND_INTENT, "seq": seq, "intent": intent}

static func build_snapshot(view: Dictionary, tick_id: int, ack_seq: int) -> Dictionary:
    return {"kind": KIND_SNAPSHOT, "view": view, "tick_id": tick_id, "ack_seq": ack_seq}

static func build_events(events: Array) -> Dictionary:
    return {"kind": KIND_EVENTS, "events": events}

static func kind_of(msg: Dictionary) -> String:
    return String(msg.get("kind", ""))

static func read_room(msg: Dictionary) -> Dictionary:
    return {
        "role": int(msg.get("role", 0)),
        "seed": int(msg.get("seed", 0)),
        "opponent_id": String(msg.get("opponent_id", "")),
    }

static func read_intent(msg: Dictionary) -> Dictionary:
    return {"seq": int(msg.get("seq", 0)), "intent": msg.get("intent", {})}

static func read_snapshot(msg: Dictionary) -> Dictionary:
    return {
        "view": msg.get("view", {}),
        "tick_id": int(msg.get("tick_id", 0)),
        "ack_seq": int(msg.get("ack_seq", 0)),
    }

static func read_events(msg: Dictionary) -> Array:
    return msg.get("events", [])
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_protocol.gd -gexit`
Expected: PASS — 5 tests, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add net/protocol.gd net/protocol.gd.uid tests/test_protocol.gd tests/test_protocol.gd.uid
git commit -m "feat(net): Protocol — constructeurs & lecteurs de messages"
```

---

## Task 2 : ITransport + InMemoryTransport

**Files:**
- Create: `net/i_transport.gd`, `net/in_memory_transport.gd`
- Test: `tests/test_in_memory_transport.gd`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `ITransport` (RefCounted) : `func send(peer_id: String, msg: Dictionary) -> void` (abstraite) ; signaux `message_received(from_peer: String, msg: Dictionary)`, `peer_connected(peer_id: String)`, `peer_disconnected(peer_id: String)`.
  - `InMemoryTransport extends ITransport` avec :
    - `var local_id: String`
    - `static func pair(host_id: String, guest_id: String) -> Array` → `[InMemoryTransport, InMemoryTransport]` (index 0 = hôte, 1 = invité), déjà reliés.
    - `func send(peer_id, msg)` route synchronement vers le pair (émet `message_received` sur la cible).
    - `func announce_connected() -> void` : émet `peer_connected` pour chaque pair connu (usage test).
    - `func drop() -> void` : émet `peer_disconnected(local_id)` sur les pairs et coupe le lien (simulation de déconnexion).

- [ ] **Step 1: Écrire les tests qui échouent**

Create `tests/test_in_memory_transport.gd`:

```gdscript
extends GutTest

var _rx: Array

func before_each():
    _rx = []

func _on_message(from_peer: String, msg: Dictionary):
    _rx.append({"from": from_peer, "msg": msg})

func test_send_routes_to_peer():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    var guest: InMemoryTransport = pair[1]
    guest.message_received.connect(_on_message)
    host.send("p1", {"kind": "hello"})
    assert_eq(_rx.size(), 1)
    assert_eq(_rx[0].from, "p0")
    assert_eq(_rx[0].msg, {"kind": "hello"})

func test_send_to_unknown_peer_is_noop():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    host.send("ghost", {"kind": "hello"})  # ne doit pas planter
    assert_true(true)

func test_drop_emits_peer_disconnected_on_other_side():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    var guest: InMemoryTransport = pair[1]
    var gone: Array = []
    host.peer_disconnected.connect(func(pid): gone.append(pid))
    guest.drop()
    assert_eq(gone, ["p1"])

func test_announce_connected_fires_for_each_peer():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    var seen: Array = []
    host.peer_connected.connect(func(pid): seen.append(pid))
    host.announce_connected()
    assert_eq(seen, ["p1"])
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_in_memory_transport.gd -gexit`
Expected: FAIL — `Identifier "InMemoryTransport" not declared`.

- [ ] **Step 3: Implémenter `net/i_transport.gd`**

```gdscript
class_name ITransport
extends RefCounted

signal message_received(from_peer: String, msg: Dictionary)
signal peer_connected(peer_id: String)
signal peer_disconnected(peer_id: String)

# Interface : les implémentations concrètes doivent surcharger send().
func send(_peer_id: String, _msg: Dictionary) -> void:
    push_error("ITransport.send() non implémenté")
```

- [ ] **Step 4: Implémenter `net/in_memory_transport.gd`**

```gdscript
class_name InMemoryTransport
extends ITransport

var local_id: String = ""
var _peers: Dictionary = {}   # peer_id -> InMemoryTransport

# Crée deux transports déjà reliés. Index 0 = hôte, 1 = invité.
static func pair(host_id: String, guest_id: String) -> Array:
    var a := InMemoryTransport.new()
    a.local_id = host_id
    var b := InMemoryTransport.new()
    b.local_id = guest_id
    a._peers[guest_id] = b
    b._peers[host_id] = a
    return [a, b]

func send(peer_id: String, msg: Dictionary) -> void:
    var target: InMemoryTransport = _peers.get(peer_id, null)
    if target == null:
        return
    target.message_received.emit(local_id, msg)

func announce_connected() -> void:
    for pid in _peers.keys():
        peer_connected.emit(pid)

func drop() -> void:
    for pid in _peers.keys():
        var other: InMemoryTransport = _peers[pid]
        other.peer_disconnected.emit(local_id)
        other._peers.erase(local_id)
    _peers.clear()
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_in_memory_transport.gd -gexit`
Expected: PASS — 4 tests, 0 échec.

- [ ] **Step 6: Commit**

```bash
git add net/i_transport.gd net/i_transport.gd.uid net/in_memory_transport.gd net/in_memory_transport.gd.uid tests/test_in_memory_transport.gd tests/test_in_memory_transport.gd.uid
git commit -m "feat(net): ITransport + InMemoryTransport (faux relais synchrone)"
```

---

## Task 3 : Reconciler (magasin de view-model côté client)

**Files:**
- Create: `net/reconciler.gd`
- Test: `tests/test_reconciler.gd`

**Interfaces:**
- Consumes: rien.
- Produces: `Reconciler` (RefCounted) :
  - `func apply_snapshot(view: Dictionary, tick_id: int, ack_seq: int) -> bool` — accepte seulement si `tick_id` strictement plus récent que le dernier ; met à jour la vue, purge les intents en attente de `seq <= ack_seq` ; renvoie `true` si accepté, `false` si périmé.
  - `func current_view() -> Dictionary`
  - `func current_tick_id() -> int` (−1 avant tout snapshot)
  - `func add_pending_intent(seq: int) -> void`
  - `func pending_count() -> int`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `tests/test_reconciler.gd`:

```gdscript
extends GutTest

func test_first_snapshot_is_accepted():
    var r := Reconciler.new()
    assert_eq(r.current_tick_id(), -1)
    assert_true(r.apply_snapshot({"phase": 0}, 1, 0))
    assert_eq(r.current_view(), {"phase": 0})
    assert_eq(r.current_tick_id(), 1)

func test_newer_tick_wins():
    var r := Reconciler.new()
    r.apply_snapshot({"v": 1}, 1, 0)
    assert_true(r.apply_snapshot({"v": 2}, 2, 0))
    assert_eq(r.current_view(), {"v": 2})

func test_stale_or_equal_tick_is_ignored():
    var r := Reconciler.new()
    r.apply_snapshot({"v": 2}, 2, 0)
    assert_false(r.apply_snapshot({"v": 1}, 1, 0), "tick plus ancien ignoré")
    assert_false(r.apply_snapshot({"v": 9}, 2, 0), "tick égal ignoré")
    assert_eq(r.current_view(), {"v": 2})

func test_ack_clears_pending_intents_up_to_seq():
    var r := Reconciler.new()
    r.add_pending_intent(1)
    r.add_pending_intent(2)
    r.add_pending_intent(3)
    assert_eq(r.pending_count(), 3)
    r.apply_snapshot({}, 1, 2)   # ack_seq=2 → purge 1 et 2
    assert_eq(r.pending_count(), 1)

func test_rejected_intent_rolls_back_via_ack():
    # Un intent rejeté est quand même "acké" (l'hôte l'a traité) → il quitte la file d'attente.
    var r := Reconciler.new()
    r.add_pending_intent(5)
    r.apply_snapshot({"authoritative": true}, 1, 5)
    assert_eq(r.pending_count(), 0)
    assert_eq(r.current_view(), {"authoritative": true})

func test_stale_snapshot_does_not_clear_pending():
    var r := Reconciler.new()
    r.apply_snapshot({}, 5, 0)
    r.add_pending_intent(1)
    r.apply_snapshot({}, 3, 1)   # périmé → aucun effet
    assert_eq(r.pending_count(), 1)
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_reconciler.gd -gexit`
Expected: FAIL — `Identifier "Reconciler" not declared`.

- [ ] **Step 3: Implémenter `net/reconciler.gd`**

```gdscript
class_name Reconciler
extends RefCounted

var _view: Dictionary = {}
var _tick_id: int = -1
var _pending: Dictionary = {}   # seq (int) -> true

func apply_snapshot(view: Dictionary, tick_id: int, ack_seq: int) -> bool:
    if tick_id <= _tick_id:
        return false
    _view = view
    _tick_id = tick_id
    for seq in _pending.keys():
        if seq <= ack_seq:
            _pending.erase(seq)
    return true

func current_view() -> Dictionary:
    return _view

func current_tick_id() -> int:
    return _tick_id

func add_pending_intent(seq: int) -> void:
    _pending[seq] = true

func pending_count() -> int:
    return _pending.size()
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_reconciler.gd -gexit`
Expected: PASS — 6 tests, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add net/reconciler.gd net/reconciler.gd.uid tests/test_reconciler.gd tests/test_reconciler.gd.uid
git commit -m "feat(net): Reconciler — view-model client + rollback optimiste"
```

---

## Task 4 : NetSession (hôte + invité)

**Files:**
- Create: `net/net_session.gd`
- Test: `tests/test_net_session.gd`

**Interfaces:**
- Consumes:
  - `GameCore.start_match / apply_intent / tick / get_view` (renvoient `{state, events}` pour apply/tick).
  - `Protocol.*` (Task 1), `ITransport` (Task 2), `Reconciler` (Task 3).
- Produces: `NetSession` (RefCounted) :
  - `enum Role { HOST, GUEST }`
  - `static func create_host(db: ContentDB, state: GameState, transport: ITransport, host_id: String, peer_ids: Array) -> NetSession`
  - `static func create_guest(db: ContentDB, transport: ITransport, guest_id: String, host_id: String) -> NetSession`
  - HÔTE : `func host_apply_local(intent: Dictionary) -> void` ; `func host_tick(delta: float) -> void` ; `func host_view() -> Dictionary` ; `func host_state() -> GameState`.
  - INVITÉ : `func send_intent(intent: Dictionary) -> int` (renvoie le `seq`) ; `var reconciler: Reconciler` ; `var last_events: Array`.
  - Signaux : `session_paused(peer_id: String)` (hôte, invité déconnecté) ; `session_aborted(reason: String)` (invité, hôte déconnecté).

- [ ] **Step 1: Écrire les tests qui échouent**

Create `tests/test_net_session.gd`:

```gdscript
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
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_net_session.gd -gexit`
Expected: FAIL — `Identifier "NetSession" not declared`.

- [ ] **Step 3: Implémenter `net/net_session.gd`**

```gdscript
class_name NetSession
extends RefCounted

enum Role { HOST, GUEST }

signal session_paused(peer_id: String)
signal session_aborted(reason: String)

var role: int = Role.HOST
var local_id: String = ""
var reconciler: Reconciler = null      # invité uniquement
var last_events: Array = []            # invité uniquement

var _db: ContentDB = null
var _transport: ITransport = null

# --- état HÔTE ---
var _state: GameState = null
var _peers: Array = []                 # ids des autres joueurs (invités)
var _tick_id: int = 0
var _last_seq: Dictionary = {}         # peer_id -> dernier seq d'intent traité

# --- état INVITÉ ---
var _host_id: String = ""
var _seq: int = 0

static func create_host(db: ContentDB, state: GameState, transport: ITransport, host_id: String, peer_ids: Array) -> NetSession:
    var s := NetSession.new()
    s.role = Role.HOST
    s._db = db
    s._transport = transport
    s.local_id = host_id
    s._state = state
    s._peers = peer_ids.duplicate()
    for pid in s._peers:
        s._last_seq[pid] = 0
    transport.message_received.connect(s._on_host_message)
    transport.peer_disconnected.connect(s._on_peer_disconnected)
    return s

static func create_guest(db: ContentDB, transport: ITransport, guest_id: String, host_id: String) -> NetSession:
    var s := NetSession.new()
    s.role = Role.GUEST
    s._db = db
    s._transport = transport
    s.local_id = guest_id
    s._host_id = host_id
    s.reconciler = Reconciler.new()
    transport.message_received.connect(s._on_guest_message)
    transport.peer_disconnected.connect(s._on_peer_disconnected)
    return s

func transport() -> ITransport:
    return _transport

# --- API HÔTE ---
func host_apply_local(intent: Dictionary) -> void:
    var res := GameCore.apply_intent(_db, _state, local_id, intent)
    _broadcast(res.events)

func host_tick(delta: float) -> void:
    var res := GameCore.tick(_db, _state, delta)
    _broadcast(res.events)

func host_view() -> Dictionary:
    return GameCore.get_view(_db, _state, local_id)

func host_view_for(viewer_id: String) -> Dictionary:
    return GameCore.get_view(_db, _state, viewer_id)

func host_state() -> GameState:
    return _state

func _on_host_message(from_peer: String, msg: Dictionary) -> void:
    if Protocol.kind_of(msg) != Protocol.KIND_INTENT:
        return
    var r := Protocol.read_intent(msg)
    _last_seq[from_peer] = r.seq
    var res := GameCore.apply_intent(_db, _state, from_peer, r.intent)
    _broadcast(res.events)

func _broadcast(events: Array) -> void:
    _tick_id += 1
    for pid in _peers:
        _transport.send(pid, Protocol.build_events(events))
        var view := GameCore.get_view(_db, _state, pid)
        _transport.send(pid, Protocol.build_snapshot(view, _tick_id, int(_last_seq.get(pid, 0))))

# --- API INVITÉ ---
func send_intent(intent: Dictionary) -> int:
    _seq += 1
    reconciler.add_pending_intent(_seq)
    _transport.send(_host_id, Protocol.build_intent(_seq, intent))
    return _seq

func _on_guest_message(_from_peer: String, msg: Dictionary) -> void:
    match Protocol.kind_of(msg):
        Protocol.KIND_SNAPSHOT:
            var r := Protocol.read_snapshot(msg)
            reconciler.apply_snapshot(r.view, r.tick_id, r.ack_seq)
        Protocol.KIND_EVENTS:
            last_events = Protocol.read_events(msg)

# --- pannes ---
func _on_peer_disconnected(peer_id: String) -> void:
    if role == Role.GUEST and peer_id == _host_id:
        session_aborted.emit("host_disconnected")
    elif role == Role.HOST:
        session_paused.emit(peer_id)
```

Note d'implémentation : `_broadcast` envoie d'abord `EVENTS` puis `SNAPSHOT` — le transport en mémoire étant synchrone, l'invité met à jour `last_events` avant sa vue, puis la vue.

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_net_session.gd -gexit`
Expected: PASS — 7 tests, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add net/net_session.gd net/net_session.gd.uid tests/test_net_session.gd tests/test_net_session.gd.uid
git commit -m "feat(net): NetSession — hôte autoritaire + invité, diffusion filtrée"
```

---

## Task 5 : Test d'intégration — match complet à travers la couture réseau

**Files:**
- Test: `tests/test_integration_net_match.gd`

**Interfaces:**
- Consumes: `NetSession` (Task 4), `InMemoryTransport` (Task 2), `MatchContent` (fixture existante), `GameCore`, `Intents`, `GameState`.
- Produces: rien (test phare).

- [ ] **Step 1: Écrire le test qui échoue**

Create `tests/test_integration_net_match.gd`. Ce test rejoue le script de `test_integration_match.gd` mais route les intents de `p1` par l'invité et ceux de `p0` par l'hôte, puis tick jusqu'à la fin.

```gdscript
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
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_integration_net_match.gd -gexit`
Expected: FAIL initialement — s'il échoue, lire l'erreur ; toutes les classes existent (Tasks 1-4), donc l'échec attendu est un désaccord d'assertion seulement si une hypothèse est fausse. But: obtenir PASS. Si `assert_eq(guest.reconciler.current_view(), host.host_view_for("p1"))` échoue, vérifier que la dernière diffusion correspond bien au dernier `host_tick` (ordre EVENTS puis SNAPSHOT).

- [ ] **Step 3: Corriger si nécessaire, puis lancer jusqu'au vert**

Aucune nouvelle implémentation attendue (les Tasks 1-4 suffisent). Si un test échoue, appliquer la sous-compétence `superpowers:systematic-debugging` avant toute modification. Ne modifier **jamais** `core/` ; corriger dans `net/` uniquement.

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_integration_net_match.gd -gexit`
Expected: PASS — 2 tests, 0 échec.

- [ ] **Step 4: Lancer la suite complète (non-régression)**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: toutes les suites passent (Plans 1, 2 et 3), 0 échec.

- [ ] **Step 5: Commit**

```bash
git add tests/test_integration_net_match.gd tests/test_integration_net_match.gd.uid
git commit -m "test(net): match déterministe de bout en bout à travers la couture réseau"
```

---

## Self-Review

**Couverture spec (`2026-07-23-food-wars-networking-design.md`) :**
- §1 Arborescence `net/` (protocol, i_transport, in_memory_transport, reconciler, net_session) → Tasks 1-4 ✅ ; Cœur non modifié → Global Constraints + Task 4 (consommation seule) ✅.
- §2 `ITransport` (send + 3 signaux) → Task 2 ✅ ; `InMemoryTransport` faux relais synchrone → Task 2 ✅ ; `Protocol` build/read ROOM/INTENT/SNAPSHOT/EVENTS → Task 1 ✅ ; `NetSession` hôte (apply_intent + diffusion get_view + tick_id) / invité (send_intent + reconciler) → Task 4 ✅ ; `Reconciler` (view-model, tick_id le plus récent gagne, pending + rollback) → Task 3 ✅.
- §3 Flux réseau (invité→hôte→apply→diffusion filtrée par joueur→réconciliation ; seul l'hôte exécute le Cœur ; tick_id monotone) → Tasks 4, 5 ✅.
- §4 Pannes : `peer_disconnected` → `session_paused`/`session_aborted` → Task 4 ✅ ; intent invalide → snapshot correcteur + rollback via ack_seq → Tasks 3, 4, 5 ✅ ; snapshots périmés jetés par tick_id → Task 3 ✅ ; fenêtre 30 s reportée → hors périmètre (respecté : non implémentée) ✅.
- §5 Tests : Protocol round-trip (Task 1), Reconciler (Task 3), InMemoryTransport (Task 2), intégration hôte+invité de bout en bout + anti-triche (Task 5) ✅.

**Scan placeholders :** aucun TODO/TBD ; chaque étape de code est complète et exécutable.

**Cohérence des types :** noms et signatures identiques entre blocs `Produces`, code et tests — `build_snapshot(view, tick_id, ack_seq)` / `read_snapshot → {view, tick_id, ack_seq}` ; `Reconciler.apply_snapshot(view, tick_id, ack_seq) -> bool` ; `NetSession.create_host(db, state, transport, host_id, peer_ids)` / `create_guest(db, transport, guest_id, host_id)` ; `host_apply_local` / `host_tick` / `host_view` / `host_view_for` / `host_state` ; `send_intent -> int` ; `transport()` ; signaux `session_paused(peer_id)` / `session_aborted(reason)`. Le retour `{state, events}` de `apply_intent`/`tick` est consommé via `res.events` (accès par point, idiome `core/`).

**Décision ack_seq :** l'hôte enregistre `_last_seq[peer]` à la réception de chaque `INTENT` (accepté **ou** rejeté) et l'inclut dans le snapshot ; le `Reconciler` purge les intents en attente `seq <= ack_seq`. Cela réalise le rollback optimiste (§4) sans distinguer confirmation et correction : l'état autoritaire gagne toujours.
