# Plan 3-bis — Transport réseau réel (relais + WebSocket) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre le jeu jouable en réseau réel : un serveur relais Node/ws (rooms par code, routage, reconnexion 30 s) + un `WebSocketTransport` Godot, branchés sur l'abstraction `ITransport` du Plan 3, sans toucher au Cœur.

**Architecture:** Le relais ne connaît aucune règle : il apparie deux sockets dans une room (le créateur = hôte), génère la seed, et transfère opaquement les messages `kind`. Côté Godot, `WebSocketTransport implements ITransport` par-dessus un `WebSocketPeer` sondé via un nouveau `poll(delta)` ajouté à `ITransport`. Tous les changements Godot du Plan 3 sont additifs (la suite headless reste verte). La logique de dispatch (Godot) et de routage (relais) est isolée du vrai I/O socket pour rester testable de façon déterministe ; seul le chemin socket réel est vérifié manuellement.

**Tech Stack:** Godot 4.5 / GDScript (GUT) ; Node.js ≥ 18 (`node --test` intégré) + `ws` (uniquement pour exécuter le serveur, pas pour les tests).

**Spec de référence :** `docs/superpowers/specs/2026-07-23-food-wars-networking-realtransport-design.md`

## Global Constraints

- **Aucune modification de `core/`.** Cœur consommé tel quel via `GameCore.*` / `GameState.*`.
- Les changements Godot du Plan 3 sont **additifs** : les 113 tests headless existants restent verts (sauf UNE réécriture de test intentionnelle, Task 3, documentée ci-dessous).
- Le relais ne contient **aucune logique de jeu** : rooms, codes, routage, minuteurs. Il transfère les messages `kind` sans les inspecter.
- `ITransport` demeure `RefCounted` (jamais `Node`). Le polling est piloté par l'appelant via `session.poll(delta)`.
- Anti-triche préservée : le filtrage reste dans `get_view` ; le relais ne voit que des messages opaques.
- `peer_disconnected` devient **TERMINAL** (→ `session_aborted`). La pause transitoire est portée par le **nouveau** signal `peer_suspended` ; le retour par `peer_resumed`.
- **Sémantique des ids** : le relais attribue `"host"` / `"guest"`. Les rôles : `role` string `"host"`/`"guest"` sur le fil ; côté Godot `ROLE_HOST=0`, `ROLE_GUEST=1`.
- `relay/relay.js` est **pur** (n'importe pas `ws`) → `relay/relay.test.js` tourne sans installation. Seul `relay/server.js` importe `ws`.
- Binaire Godot : `godot` (4.5.1). Après ajout d'un script `class_name`, `godot --headless --import` AVANT GUT. Bruit `NavigationServer*Manager` de GUT = non fatal, juger sur « Passing Tests » / « All tests passed! ». Indentation 4 espaces. Versionner les `.uid`.
- Node : `node --version` ≥ 18. Tests relais : `node --test relay/relay.test.js` (aucun `npm install` requis).

---

## File Structure

**À créer :**
- `net/websocket_transport.gd` — `WebSocketTransport extends ITransport` : socket réel + handshake relais + dispatch.
- `relay/relay.js` — classe `Relay` pure (rooms, codes, routage, reconnexion). Aucune dépendance `ws`.
- `relay/server.js` — adaptateur `ws` : câble chaque socket à `Relay`.
- `relay/relay.test.js` — tests `node:test` de `Relay` (conns/timers factices).
- `relay/package.json` — dép `ws`, scripts `start`/`test`.
- `relay/README.md` — comment lancer le relais.
- `scripts/net_smoke.gd` — harnais headless manuel (host/guest scriptés) pour l'E2E réel.
- `docs/MANUAL-E2E.md` — checklist de smoke-test manuel.

**À modifier (additif) :**
- `net/i_transport.gd` — `poll(delta)` + signaux `peer_suspended`/`peer_resumed`.
- `net/protocol.gd` — `serialize`/`deserialize`.
- `net/net_session.gd` — `poll`, `host_resync`, signal `session_resumed`, mapping suspend/resume + `peer_disconnected` terminal.
- `net/in_memory_transport.gd` — helpers de test `emit_suspended`/`emit_resumed`.
- `tests/test_protocol.gd`, `tests/test_in_memory_transport.gd`, `tests/test_net_session.gd` — nouveaux cas (+ 1 réécriture).

**Ordre & dépendances :** T1 (Protocol JSON) → T2 (ITransport/InMemory) → T3 (NetSession) ; T4 (relais core) → T5 (relais reconnexion) — indépendants de T1-3 ; T6 (WebSocketTransport) dépend de T1-3 ; T7 (doc E2E) dépend de tout.

---

## Task 1 : Protocol — sérialisation JSON

**Files:**
- Modify: `net/protocol.gd`
- Test: `tests/test_protocol.gd` (étendre)

**Interfaces:**
- Consumes: rien.
- Produces: `Protocol.serialize(msg: Dictionary) -> String` ; `Protocol.deserialize(text: String) -> Dictionary` (retourne `{}` si le texte n'est pas un objet JSON valide).

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à la fin de `tests/test_protocol.gd` :

```gdscript
func test_serialize_deserialize_intent_round_trip():
    var intent := {"type": "add_ingredient", "ingredient_id": "boeuf"}
    var msg := Protocol.build_intent(7, intent)
    var text := Protocol.serialize(msg)
    assert_eq(typeof(text), TYPE_STRING)
    var back := Protocol.deserialize(text)
    assert_eq(Protocol.kind_of(back), Protocol.KIND_INTENT)
    var r := Protocol.read_intent(back)
    assert_eq(r.seq, 7)
    assert_eq(r.intent, intent)

func test_serialize_deserialize_snapshot_preserves_ints():
    # JSON coerce les nombres en float ; read_snapshot recaste via int().
    var view := {"phase": 1, "you": {"name": "p0"}}
    var msg := Protocol.build_snapshot(view, 12, 3)
    var back := Protocol.deserialize(Protocol.serialize(msg))
    var r := Protocol.read_snapshot(back)
    assert_eq(r.tick_id, 12)
    assert_eq(r.ack_seq, 3)
    assert_eq(String(r.view.get("you", {}).get("name", "")), "p0")

func test_deserialize_invalid_text_returns_empty():
    assert_eq(Protocol.deserialize("pas du json"), {})
    assert_eq(Protocol.deserialize("[1,2,3]"), {}, "un tableau JSON n'est pas un message")
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_protocol.gd -gexit`
Expected: FAIL — `Invalid call. Nonexistent function 'serialize' in base 'Protocol'`.

- [ ] **Step 3: Implémenter dans `net/protocol.gd`**

Ajouter à la fin du fichier :

```gdscript
static func serialize(msg: Dictionary) -> String:
    return JSON.stringify(msg)

static func deserialize(text: String) -> Dictionary:
    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_protocol.gd -gexit`
Expected: PASS — 8 tests (5 existants + 3 nouveaux), 0 échec.

- [ ] **Step 5: Commit**

```bash
git add net/protocol.gd tests/test_protocol.gd
git commit -m "feat(net): Protocol.serialize/deserialize (JSON) pour le transport réel"
```

---

## Task 2 : ITransport — poll + signaux suspend/resume ; InMemoryTransport helpers

**Files:**
- Modify: `net/i_transport.gd`, `net/in_memory_transport.gd`
- Test: `tests/test_in_memory_transport.gd` (étendre)

**Interfaces:**
- Consumes: rien.
- Produces:
  - `ITransport` : signaux `peer_suspended(peer_id: String)`, `peer_resumed(peer_id: String)` ; `func poll(_delta: float) -> void` (no-op par défaut).
  - `InMemoryTransport` : `func emit_suspended(peer_id: String) -> void` ; `func emit_resumed(peer_id: String) -> void` (helpers de test).

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à la fin de `tests/test_in_memory_transport.gd` :

```gdscript
func test_poll_is_noop():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    host.message_received.connect(_on_message)
    host.poll(0.016)   # ne doit rien émettre ni planter
    assert_eq(_rx.size(), 0)

func test_emit_suspended_and_resumed():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    var suspended: Array = []
    var resumed: Array = []
    host.peer_suspended.connect(func(pid): suspended.append(pid))
    host.peer_resumed.connect(func(pid): resumed.append(pid))
    host.emit_suspended("p1")
    host.emit_resumed("p1")
    assert_eq(suspended, ["p1"])
    assert_eq(resumed, ["p1"])
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_in_memory_transport.gd -gexit`
Expected: FAIL — `Invalid call. Nonexistent function 'emit_suspended'` (et signaux inconnus).

- [ ] **Step 3: Modifier `net/i_transport.gd`**

Remplacer le contenu par :

```gdscript
class_name ITransport
extends RefCounted

signal message_received(from_peer: String, msg: Dictionary)
signal peer_connected(peer_id: String)
signal peer_disconnected(peer_id: String)
signal peer_suspended(peer_id: String)
signal peer_resumed(peer_id: String)

# Interface : les implémentations concrètes doivent surcharger send().
func send(_peer_id: String, _msg: Dictionary) -> void:
    push_error("ITransport.send() non implémenté")

# Sonde le transport (draine le socket). No-op par défaut ; l'appelant l'invoque
# à chaque frame via NetSession.poll(delta).
func poll(_delta: float) -> void:
    pass
```

- [ ] **Step 4: Modifier `net/in_memory_transport.gd`**

Ajouter à la fin du fichier :

```gdscript
# Helpers de test : simulent une suspension/reprise de pair (fenêtre de reconnexion).
func emit_suspended(peer_id: String) -> void:
    peer_suspended.emit(peer_id)

func emit_resumed(peer_id: String) -> void:
    peer_resumed.emit(peer_id)
```

- [ ] **Step 5: Lancer les tests (fichier + non-régression transport)**

Run: `godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_in_memory_transport.gd -gexit`
Expected: PASS — 6 tests (4 existants + 2 nouveaux), 0 échec.

- [ ] **Step 6: Commit**

```bash
git add net/i_transport.gd net/in_memory_transport.gd tests/test_in_memory_transport.gd
git commit -m "feat(net): ITransport.poll + signaux peer_suspended/peer_resumed + helpers InMemory"
```

---

## Task 3 : NetSession — poll, host_resync, session_resumed, mapping (peer_disconnected terminal)

**Files:**
- Modify: `net/net_session.gd`
- Test: `tests/test_net_session.gd` (étendre + **réécrire 1 cas existant**)

**Interfaces:**
- Consumes: `ITransport` (poll + signaux suspend/resume, Task 2) ; `InMemoryTransport.emit_suspended/emit_resumed` (Task 2) ; `GameCore.get_view` ; `_broadcast` (interne existant).
- Produces: `NetSession.poll(delta: float) -> void` ; `NetSession.host_resync() -> void` ; signal `session_resumed(peer_id: String)`.

**⚠️ Changement de comportement intentionnel (dicté par la spec §4) :** `peer_disconnected` devient **terminal**. Côté hôte, il n'émet plus `session_paused` mais `session_aborted("peer_lost")`. La pause transitoire passe désormais par `peer_suspended`. Le test existant `test_host_emits_paused_on_guest_drop` est **réécrit** en conséquence (drop → aborted) et un nouveau cas couvre `emit_suspended` → paused.

- [ ] **Step 1: Écrire/réécrire les tests**

Dans `tests/test_net_session.gd`, **remplacer** le cas existant :

```gdscript
func test_host_emits_paused_on_guest_drop():
    var w := _wire()
    var host: NetSession = w.host
    var paused: Array = []
    host.session_paused.connect(func(pid): paused.append(pid))
    (w.guest.transport() as InMemoryTransport).drop()
    assert_eq(paused, ["p1"])
```

par :

```gdscript
func test_host_emits_aborted_on_peer_disconnect():
    # peer_disconnected est désormais TERMINAL côté hôte.
    var w := _wire()
    var host: NetSession = w.host
    var aborted: Array = []
    host.session_aborted.connect(func(reason): aborted.append(reason))
    (w.guest.transport() as InMemoryTransport).drop()
    assert_eq(aborted, ["peer_lost"])

func test_host_emits_paused_on_peer_suspended():
    var w := _wire()
    var host: NetSession = w.host
    var paused: Array = []
    host.session_paused.connect(func(pid): paused.append(pid))
    (w.host.transport() as InMemoryTransport).emit_suspended("p1")
    assert_eq(paused, ["p1"])

func test_host_resync_rebroadcasts_current_view():
    var w := _wire()
    var host: NetSession = w.host
    var guest: NetSession = w.guest
    host.host_apply_local({"type": Intents.ADD_INGREDIENT, "ingredient_id": "boeuf"})
    var before := guest.reconciler.current_tick_id()
    host.host_resync()
    assert_gt(guest.reconciler.current_tick_id(), before, "resync diffuse un nouveau snapshot")
    assert_eq(guest.reconciler.current_view(), host.host_view_for("p1"))

func test_host_resume_triggers_resync_and_signal():
    var w := _wire()
    var host: NetSession = w.host
    var guest: NetSession = w.guest
    var resumed: Array = []
    host.session_resumed.connect(func(pid): resumed.append(pid))
    var before := guest.reconciler.current_tick_id()
    (w.host.transport() as InMemoryTransport).emit_resumed("p1")
    assert_eq(resumed, ["p1"])
    assert_gt(guest.reconciler.current_tick_id(), before, "la reprise resynchronise l'invité")

func test_poll_delegates_to_transport():
    var w := _wire()
    var host: NetSession = w.host
    host.poll(0.016)   # passe-plat vers un transport no-op : ne doit pas planter
    assert_true(true)
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_net_session.gd -gexit`
Expected: FAIL — `Nonexistent function 'host_resync'` / signal `session_resumed` inconnu / `test_host_emits_aborted_on_peer_disconnect` échoue (mapping pas encore terminal).

- [ ] **Step 3: Modifier `net/net_session.gd`**

3a. Ajouter le signal après les signaux existants (sous la ligne `signal session_aborted(...)`) :

```gdscript
signal session_resumed(peer_id: String)
```

3b. Dans `create_host`, après `transport.peer_disconnected.connect(s._on_peer_disconnected)`, ajouter :

```gdscript
    transport.peer_suspended.connect(s._on_peer_suspended)
    transport.peer_resumed.connect(s._on_peer_resumed)
```

3c. Dans `create_guest`, après `transport.peer_disconnected.connect(s._on_peer_disconnected)`, ajouter les deux mêmes lignes :

```gdscript
    transport.peer_suspended.connect(s._on_peer_suspended)
    transport.peer_resumed.connect(s._on_peer_resumed)
```

3d. Ajouter la méthode `poll` juste après `func transport() -> ITransport:` :

```gdscript
func poll(delta: float) -> void:
    _transport.poll(delta)
```

3e. Ajouter `host_resync` dans la section API HÔTE (après `host_state`) :

```gdscript
func host_resync() -> void:
    # Rediffuse les vues filtrées courantes (tick_id avance → le Reconciler accepte).
    _broadcast([])
```

3f. **Remplacer** la fonction `_on_peer_disconnected` existante par le mapping terminal + les nouveaux handlers :

```gdscript
# --- pannes ---
func _on_peer_disconnected(peer_id: String) -> void:
    # TERMINAL : la pause transitoire est portée par peer_suspended.
    if role == Role.GUEST and peer_id == _host_id:
        session_aborted.emit("host_disconnected")
    elif role == Role.HOST:
        session_aborted.emit("peer_lost")

func _on_peer_suspended(peer_id: String) -> void:
    session_paused.emit(peer_id)

func _on_peer_resumed(peer_id: String) -> void:
    if role == Role.HOST:
        host_resync()
    session_resumed.emit(peer_id)
```

- [ ] **Step 4: Lancer le fichier puis la suite complète**

Run: `godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_net_session.gd -gexit`
Expected: PASS — 11 tests (6 conservés + 1 réécrit + 4 nouveaux), 0 échec.

Puis la non-régression complète :

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: « All tests passed! » (aucune régression des Plans 1-3 ; le seul changement de comportement est couvert par les tests réécrits).

- [ ] **Step 5: Commit**

```bash
git add net/net_session.gd tests/test_net_session.gd
git commit -m "feat(net): NetSession poll + host_resync + session_resumed ; peer_disconnected terminal"
```

---

## Task 4 : Relais — cœur (rooms, codes, routage) + serveur ws

**Files:**
- Create: `relay/relay.js`, `relay/server.js`, `relay/package.json`, `relay/README.md`
- Test: `relay/relay.test.js`

**Interfaces:**
- Consumes: rien (`relay.js` est pur).
- Produces (classe `Relay`, CommonJS `module.exports = { Relay }`) :
  - `new Relay({ reconnectMs?, setTimer?, clearTimer?, makeSeed?, makeCode? })`
  - `onConnect(conn)` — `conn` = `{ send(text: string), close() }`.
  - `onMessage(conn, text: string)`
  - `onClose(conn)`
  - Messages de contrôle émis (via `conn.send(JSON.stringify(...))`) : `{t:"created",code}`, `{t:"room_ready",role,seed,opponent_id}`, `{t:"error",reason}`. (Reconnexion : Task 5.)

- [ ] **Step 1: Écrire les tests qui échouent**

Create `relay/relay.test.js` :

```javascript
const { test } = require('node:test');
const assert = require('node:assert');
const { Relay } = require('./relay');

function fakeConn() {
    return {
        sent: [],
        closed: false,
        send(text) { this.sent.push(text); },
        close() { this.closed = true; },
        last() { return JSON.parse(this.sent[this.sent.length - 1]); },
    };
}

function newRelay() {
    // seed et code déterministes pour les tests
    let n = 0;
    return new Relay({ makeSeed: () => 4242, makeCode: () => 'WOK' + (n++) });
}

test('create renvoie un code et désigne l\'hôte', () => {
    const r = newRelay();
    const host = fakeConn();
    r.onConnect(host);
    r.onMessage(host, JSON.stringify({ t: 'create' }));
    const m = host.last();
    assert.strictEqual(m.t, 'created');
    assert.strictEqual(m.code, 'WOK0');
});

test('join sur code inconnu renvoie une erreur', () => {
    const r = newRelay();
    const guest = fakeConn();
    r.onConnect(guest);
    r.onMessage(guest, JSON.stringify({ t: 'join', code: 'ZZZZ' }));
    assert.strictEqual(guest.last().t, 'error');
    assert.strictEqual(guest.last().reason, 'unknown_code');
});

test('join valide envoie room_ready aux deux avec rôles et seed', () => {
    const r = newRelay();
    const host = fakeConn();
    const guest = fakeConn();
    r.onConnect(host); r.onMessage(host, JSON.stringify({ t: 'create' }));
    const code = host.last().code;
    r.onConnect(guest); r.onMessage(guest, JSON.stringify({ t: 'join', code }));
    const hm = host.last(), gm = guest.last();
    assert.strictEqual(hm.t, 'room_ready');
    assert.strictEqual(hm.role, 'host');
    assert.strictEqual(hm.opponent_id, 'guest');
    assert.strictEqual(gm.role, 'guest');
    assert.strictEqual(gm.opponent_id, 'host');
    assert.strictEqual(hm.seed, 4242);
    assert.strictEqual(gm.seed, 4242);
});

test('join d\'une room pleine renvoie une erreur', () => {
    const r = newRelay();
    const host = fakeConn(), g1 = fakeConn(), g2 = fakeConn();
    r.onConnect(host); r.onMessage(host, JSON.stringify({ t: 'create' }));
    const code = host.last().code;
    r.onConnect(g1); r.onMessage(g1, JSON.stringify({ t: 'join', code }));
    r.onConnect(g2); r.onMessage(g2, JSON.stringify({ t: 'join', code }));
    assert.strictEqual(g2.last().t, 'error');
    assert.strictEqual(g2.last().reason, 'room_full');
});

test('les messages de jeu (kind) sont transférés au pair, verbatim', () => {
    const r = newRelay();
    const host = fakeConn(), guest = fakeConn();
    r.onConnect(host); r.onMessage(host, JSON.stringify({ t: 'create' }));
    const code = host.last().code;
    r.onConnect(guest); r.onMessage(guest, JSON.stringify({ t: 'join', code }));
    const gameMsg = JSON.stringify({ kind: 'intent', seq: 1, intent: { type: 'x' } });
    r.onMessage(guest, gameMsg);           // invité -> hôte
    assert.strictEqual(host.sent[host.sent.length - 1], gameMsg);
    const snap = JSON.stringify({ kind: 'snapshot', view: {}, tick_id: 1, ack_seq: 1 });
    r.onMessage(host, snap);               // hôte -> invité
    assert.strictEqual(guest.sent[guest.sent.length - 1], snap);
});
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `node --test relay/relay.test.js`
Expected: FAIL — `Cannot find module './relay'`.

- [ ] **Step 3: Implémenter `relay/relay.js`**

```javascript
'use strict';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sans I,O,0,1

function defaultMakeCode() {
    let s = '';
    for (let i = 0; i < 4; i++) s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
    return s;
}

class Relay {
    constructor(opts = {}) {
        this.reconnectMs = opts.reconnectMs ?? 30000;
        this.setTimer = opts.setTimer ?? setTimeout;
        this.clearTimer = opts.clearTimer ?? clearTimeout;
        this.makeSeed = opts.makeSeed ?? (() => Math.floor(Math.random() * 2147483647));
        this.makeCode = opts.makeCode ?? defaultMakeCode;
        this.rooms = new Map(); // code -> { code, host, guest, seed, timer }
    }

    onConnect(conn) {
        conn._room = null;
        conn._role = null;
    }

    onMessage(conn, text) {
        let msg;
        try { msg = JSON.parse(text); } catch (_) { return; }
        if (msg && typeof msg.t === 'string') {
            this._control(conn, msg);
        } else {
            this._forward(conn, text);
        }
    }

    _control(conn, msg) {
        switch (msg.t) {
            case 'create': return this._create(conn);
            case 'join': return this._join(conn, String(msg.code || ''));
            default: return;
        }
    }

    _create(conn) {
        let code = this.makeCode();
        while (this.rooms.has(code)) code = this.makeCode();
        const room = { code, host: conn, guest: null, seed: this.makeSeed(), timer: null };
        this.rooms.set(code, room);
        conn._room = room;
        conn._role = 'host';
        this._send(conn, { t: 'created', code });
    }

    _join(conn, code) {
        const room = this.rooms.get(code);
        if (!room) return this._send(conn, { t: 'error', reason: 'unknown_code' });
        if (room.guest) return this._send(conn, { t: 'error', reason: 'room_full' });
        room.guest = conn;
        conn._room = room;
        conn._role = 'guest';
        this._send(room.host, { t: 'room_ready', role: 'host', seed: room.seed, opponent_id: 'guest' });
        this._send(conn, { t: 'room_ready', role: 'guest', seed: room.seed, opponent_id: 'host' });
    }

    _forward(conn, text) {
        const room = conn._room;
        if (!room) return;
        const peer = conn._role === 'host' ? room.guest : room.host;
        if (peer) peer.send(text);
    }

    _send(conn, obj) {
        conn.send(JSON.stringify(obj));
    }

    onClose(conn) {
        // Reconnexion : implémentée en Task 5.
    }
}

module.exports = { Relay };
```

- [ ] **Step 4: Implémenter `relay/server.js`**

```javascript
'use strict';

const { WebSocketServer } = require('ws');
const { Relay } = require('./relay');

const port = Number(process.env.PORT || 8080);
const relay = new Relay();
const wss = new WebSocketServer({ port });

wss.on('connection', (ws) => {
    const conn = { send: (t) => ws.send(t), close: () => ws.close() };
    relay.onConnect(conn);
    ws.on('message', (data) => relay.onMessage(conn, data.toString()));
    ws.on('close', () => relay.onClose(conn));
});

console.log(`Food Wars relay en écoute sur ws://localhost:${port}`);
```

- [ ] **Step 5: Créer `relay/package.json`**

```json
{
  "name": "food-wars-relay",
  "version": "1.0.0",
  "private": true,
  "type": "commonjs",
  "description": "Relais WebSocket de matchmaking pour Food Wars (aucune logique de jeu).",
  "scripts": {
    "start": "node server.js",
    "test": "node --test"
  },
  "dependencies": {
    "ws": "^8.18.0"
  }
}
```

- [ ] **Step 6: Créer `relay/README.md`**

```markdown
# Food Wars — Relais WebSocket

Routeur de matchmaking sans logique de jeu : apparie deux joueurs dans une room
par code, désigne l'hôte, génère la seed, transfère les messages opaques.

## Lancer

```bash
cd relay
npm install        # installe `ws` (requis seulement pour exécuter le serveur)
npm start          # écoute sur ws://localhost:8080 (PORT pour changer)
```

## Tester

```bash
cd relay
npm test           # node --test — aucune installation requise (relay.js est pur)
```

## Protocole

- Contrôle (JSON avec `t`) : `create` → `created{code}` ; `join{code}` →
  `room_ready{role,seed,opponent_id}` aux deux, ou `error{reason}`.
- Reconnexion : `peer_left` / `peer_rejoined` / `room_closed` / `host_left`.
- Tout autre message (champ `kind`) est transféré verbatim au pair.
```

- [ ] **Step 7: Lancer les tests pour vérifier qu'ils passent**

Run: `node --test relay/relay.test.js`
Expected: PASS — 5 tests, 0 échec.

- [ ] **Step 8: Commit**

```bash
git add relay/relay.js relay/server.js relay/package.json relay/README.md relay/relay.test.js
git commit -m "feat(relay): serveur relais Node/ws — rooms par code, routage opaque"
```

---

## Task 5 : Relais — reconnexion 30 s + resync

**Files:**
- Modify: `relay/relay.js`
- Test: `relay/relay.test.js` (étendre)

**Interfaces:**
- Consumes: `Relay` (Task 4), `setTimer`/`clearTimer` injectables.
- Produces (comportement ajouté à `onClose`/`_join`) :
  - Fermeture socket **invité** → hôte reçoit `{t:"peer_left"}` ; minuteur `reconnectMs` armé.
  - Expiration → pair restant reçoit `{t:"room_closed"}` ; room supprimée.
  - `join` avec le code d'une room dont l'invité est absent (fenêtre active) → ré-attache l'invité, hôte reçoit `{t:"peer_rejoined"}`, l'invité reçoit à nouveau `room_ready`, minuteur annulé.
  - Fermeture socket **hôte** → invité reçoit `{t:"host_left"}` ; room supprimée.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `relay/relay.test.js` (helper de timers factices en tête de fichier, puis les cas) :

```javascript
function fakeTimers() {
    const pending = [];
    return {
        setTimer: (cb, _ms) => { const h = { cb }; pending.push(h); return h; },
        clearTimer: (h) => { const i = pending.indexOf(h); if (i >= 0) pending.splice(i, 1); },
        fireAll() { const cbs = pending.splice(0); cbs.forEach((h) => h.cb()); },
        count() { return pending.length; },
    };
}

function pairedRelay(timers) {
    let n = 0;
    const r = new Relay({
        makeSeed: () => 4242, makeCode: () => 'WOK' + (n++),
        setTimer: timers.setTimer, clearTimer: timers.clearTimer, reconnectMs: 30000,
    });
    const host = fakeConn(), guest = fakeConn();
    r.onConnect(host); r.onMessage(host, JSON.stringify({ t: 'create' }));
    const code = host.last().code;
    r.onConnect(guest); r.onMessage(guest, JSON.stringify({ t: 'join', code }));
    return { r, host, guest, code };
}

test('déconnexion invité : l\'hôte reçoit peer_left et un minuteur est armé', () => {
    const timers = fakeTimers();
    const { r, host } = pairedRelay(timers);
    r.onClose(host._room.guest);
    assert.strictEqual(host.last().t, 'peer_left');
    assert.strictEqual(timers.count(), 1);
});

test('expiration de la fenêtre : le pair restant reçoit room_closed', () => {
    const timers = fakeTimers();
    const { r, host } = pairedRelay(timers);
    r.onClose(host._room.guest);
    timers.fireAll();
    assert.strictEqual(host.last().t, 'room_closed');
});

test('rejoin dans la fenêtre : hôte peer_rejoined, invité re-room_ready, minuteur annulé', () => {
    const timers = fakeTimers();
    const { r, host, code } = pairedRelay(timers);
    r.onClose(host._room.guest);
    const back = fakeConn();
    r.onConnect(back); r.onMessage(back, JSON.stringify({ t: 'join', code }));
    assert.strictEqual(host.last().t, 'peer_rejoined');
    assert.strictEqual(back.last().t, 'room_ready');
    assert.strictEqual(back.last().role, 'guest');
    assert.strictEqual(timers.count(), 0, 'le minuteur de reconnexion est annulé');
});

test('déconnexion hôte : l\'invité reçoit host_left et la room disparaît', () => {
    const timers = fakeTimers();
    const { r, host, guest, code } = pairedRelay(timers);
    r.onClose(host);
    assert.strictEqual(guest.last().t, 'host_left');
    assert.strictEqual(r.rooms.has(code), false);
});
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `node --test relay/relay.test.js`
Expected: FAIL — les 4 nouveaux cas échouent (`onClose` est un stub ; `peer_left`/`room_closed`/`peer_rejoined`/`host_left` absents).

- [ ] **Step 3: Implémenter la reconnexion dans `relay/relay.js`**

3a. **Remplacer** `onClose(conn)` par :

```javascript
    onClose(conn) {
        const room = conn._room;
        if (!room) return;
        if (conn._role === 'host') {
            // Déconnexion hôte = terminale.
            if (room.timer) { this.clearTimer(room.timer); room.timer = null; }
            if (room.guest) this._send(room.guest, { t: 'host_left' });
            this.rooms.delete(room.code);
            return;
        }
        // Déconnexion invité : fenêtre de reconnexion.
        room.guest = null;
        if (room.host) this._send(room.host, { t: 'peer_left' });
        room.timer = this.setTimer(() => {
            room.timer = null;
            if (room.host) this._send(room.host, { t: 'room_closed' });
            this.rooms.delete(room.code);
        }, this.reconnectMs);
    }
```

3b. **Remplacer** `_join(conn, code)` pour gérer le rejoin d'un invité absent (fenêtre active) :

```javascript
    _join(conn, code) {
        const room = this.rooms.get(code);
        if (!room) return this._send(conn, { t: 'error', reason: 'unknown_code' });
        if (room.guest) return this._send(conn, { t: 'error', reason: 'room_full' });
        // Nouvel invité OU reprise d'un invité déconnecté (room.guest === null).
        const isRejoin = room.timer !== null;
        if (isRejoin) { this.clearTimer(room.timer); room.timer = null; }
        room.guest = conn;
        conn._room = room;
        conn._role = 'guest';
        this._send(conn, { t: 'room_ready', role: 'guest', seed: room.seed, opponent_id: 'host' });
        if (isRejoin) {
            if (room.host) this._send(room.host, { t: 'peer_rejoined' });
        } else {
            this._send(room.host, { t: 'room_ready', role: 'host', seed: room.seed, opponent_id: 'guest' });
        }
    }
```

Note : `room.guest` reste `null` pendant la fenêtre (l'ancien socket est parti) ; c'est `room.timer !== null` qui distingue un rejoin d'un premier join. Le test « room pleine » reste valide car `room.guest` est non-null tant que l'invité est connecté.

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `node --test relay/relay.test.js`
Expected: PASS — 9 tests (5 de Task 4 + 4 nouveaux), 0 échec.

- [ ] **Step 5: Commit**

```bash
git add relay/relay.js relay/relay.test.js
git commit -m "feat(relay): reconnexion 30 s (peer_left/rejoined/room_closed) + host_left terminal"
```

---

## Task 6 : WebSocketTransport Godot (socket + handshake + dispatch)

**Files:**
- Create: `net/websocket_transport.gd`, `scripts/net_smoke.gd`
- Test: `tests/test_websocket_transport.gd`

**Interfaces:**
- Consumes: `ITransport` (base + signaux, Tasks 2) ; `Protocol.serialize/deserialize` (Task 1).
- Produces: `WebSocketTransport extends ITransport` :
  - Constantes `ROLE_HOST := 0`, `ROLE_GUEST := 1`.
  - Signaux (spécifiques) : `room_created(code: String)`, `room_ready(role: int, seed_value: int, opponent_id: String)`, `relay_error(reason: String)`.
  - Champs : `role: int`, `seed_value: int`, `opponent_id: String`.
  - `connect_create(url: String) -> void` ; `connect_join(url: String, code: String) -> void`.
  - `send(peer_id, msg)`, `poll(delta)` (surcharges).
  - `_dispatch(text: String) -> void` (traite un message reçu — testable sans socket).

**Note testabilité :** le vrai I/O `WebSocketPeer` (`connect_to_url`/`poll`/`send_text`/lecture de paquets) est mince et vérifié **manuellement** (Task 7). La logique de dispatch (`_dispatch`) est testée en headless en lui passant des chaînes JSON.

- [ ] **Step 1: Écrire les tests qui échouent**

Create `tests/test_websocket_transport.gd` :

```gdscript
extends GutTest

func _make() -> WebSocketTransport:
    return WebSocketTransport.new()

func test_dispatch_room_ready_sets_state_and_emits():
    var t := _make()
    var ready: Array = []
    var connected: Array = []
    t.room_ready.connect(func(role, seed_value, opp): ready.append([role, seed_value, opp]))
    t.peer_connected.connect(func(pid): connected.append(pid))
    t._dispatch('{"t":"room_ready","role":"host","seed":4242,"opponent_id":"guest"}')
    assert_eq(t.role, WebSocketTransport.ROLE_HOST)
    assert_eq(t.seed_value, 4242)
    assert_eq(t.opponent_id, "guest")
    assert_eq(ready, [[WebSocketTransport.ROLE_HOST, 4242, "guest"]])
    assert_eq(connected, ["guest"])

func test_dispatch_created_emits_room_code():
    var t := _make()
    var codes: Array = []
    t.room_created.connect(func(c): codes.append(c))
    t._dispatch('{"t":"created","code":"WOK7"}')
    assert_eq(codes, ["WOK7"])

func test_dispatch_game_message_emits_message_received_from_opponent():
    var t := _make()
    t._dispatch('{"t":"room_ready","role":"guest","seed":1,"opponent_id":"host"}')
    var rx: Array = []
    t.message_received.connect(func(from, msg): rx.append([from, msg]))
    t._dispatch('{"kind":"snapshot","view":{},"tick_id":5,"ack_seq":2}')
    assert_eq(rx.size(), 1)
    assert_eq(rx[0][0], "host", "from_peer = adversaire")
    assert_eq(Protocol.kind_of(rx[0][1]), Protocol.KIND_SNAPSHOT)

func test_dispatch_reconnect_control_maps_to_signals():
    var t := _make()
    t._dispatch('{"t":"room_ready","role":"host","seed":1,"opponent_id":"guest"}')
    var suspended: Array = []
    var resumed: Array = []
    var disconnected: Array = []
    t.peer_suspended.connect(func(pid): suspended.append(pid))
    t.peer_resumed.connect(func(pid): resumed.append(pid))
    t.peer_disconnected.connect(func(pid): disconnected.append(pid))
    t._dispatch('{"t":"peer_left"}')
    t._dispatch('{"t":"peer_rejoined"}')
    t._dispatch('{"t":"room_closed"}')
    assert_eq(suspended, ["guest"])
    assert_eq(resumed, ["guest"])
    assert_eq(disconnected, ["guest"])

func test_dispatch_error_emits_relay_error():
    var t := _make()
    var errs: Array = []
    t.relay_error.connect(func(reason): errs.append(reason))
    t._dispatch('{"t":"error","reason":"unknown_code"}')
    assert_eq(errs, ["unknown_code"])

func test_send_without_connection_is_noop():
    var t := _make()
    t.send("guest", {"kind": "intent"})   # pas de socket ouvert → ne doit pas planter
    assert_true(true)

func test_poll_without_connection_is_noop():
    var t := _make()
    t.poll(0.016)
    assert_true(true)
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_websocket_transport.gd -gexit`
Expected: FAIL — `Identifier "WebSocketTransport" not declared`.

- [ ] **Step 3: Implémenter `net/websocket_transport.gd`**

```gdscript
class_name WebSocketTransport
extends ITransport

signal room_created(code: String)
signal room_ready(role: int, seed_value: int, opponent_id: String)
signal relay_error(reason: String)

const ROLE_HOST := 0
const ROLE_GUEST := 1

var role: int = -1
var seed_value: int = 0
var opponent_id: String = ""

var _peer: WebSocketPeer = null
var _url: String = ""
var _pending_control: Dictionary = {}
var _control_sent: bool = false
var _ready: bool = false

func connect_create(url: String) -> void:
    _pending_control = {"t": "create"}
    _open(url)

func connect_join(url: String, code: String) -> void:
    _pending_control = {"t": "join", "code": code}
    _open(url)

func _open(url: String) -> void:
    _url = url
    _peer = WebSocketPeer.new()
    _peer.connect_to_url(_url)
    _control_sent = false
    _ready = false

func send(_peer_id: String, msg: Dictionary) -> void:
    if _peer == null:
        return
    _peer.send_text(Protocol.serialize(msg))

func poll(_delta: float) -> void:
    if _peer == null:
        return
    _peer.poll()
    var state := _peer.get_ready_state()
    if state == WebSocketPeer.STATE_OPEN:
        if not _control_sent and not _pending_control.is_empty():
            _peer.send_text(JSON.stringify(_pending_control))
            _control_sent = true
        while _peer.get_available_packet_count() > 0:
            _dispatch(_peer.get_packet().get_string_from_utf8())
    elif state == WebSocketPeer.STATE_CLOSED:
        if _ready and opponent_id != "":
            peer_disconnected.emit(opponent_id)
        _peer = null

# Traite un message texte reçu (contrôle relais OU message de jeu). Testable sans socket.
func _dispatch(text: String) -> void:
    var msg := Protocol.deserialize(text)
    if msg.is_empty():
        return
    if msg.has("t"):
        _dispatch_control(msg)
    else:
        message_received.emit(opponent_id, msg)

func _dispatch_control(msg: Dictionary) -> void:
    match String(msg.get("t", "")):
        "created":
            room_created.emit(String(msg.get("code", "")))
        "room_ready":
            role = ROLE_HOST if String(msg.get("role", "")) == "host" else ROLE_GUEST
            seed_value = int(msg.get("seed", 0))
            opponent_id = String(msg.get("opponent_id", ""))
            _ready = true
            room_ready.emit(role, seed_value, opponent_id)
            peer_connected.emit(opponent_id)
        "peer_left":
            peer_suspended.emit(opponent_id)
        "peer_rejoined":
            peer_resumed.emit(opponent_id)
        "host_left", "room_closed":
            peer_disconnected.emit(opponent_id)
        "error":
            relay_error.emit(String(msg.get("reason", "")))
```

- [ ] **Step 4: Créer le harnais manuel `scripts/net_smoke.gd`**

Harnais headless pour l'E2E réel (Task 7). Lancé en deux processus contre un relais qui tourne. L'hôte joue le script de planning + tick jusqu'à la fin ; l'invité se déclare prêt ; chacun imprime sa progression.

```gdscript
extends SceneTree

# Usage :
#   Hôte   : godot --headless -s scripts/net_smoke.gd -- host ws://localhost:8080
#   Invité : godot --headless -s scripts/net_smoke.gd -- join ws://localhost:8080 <CODE>

var _db: ContentDB
var _transport: WebSocketTransport
var _session: NetSession
var _mode: String = ""
var _did_plan: bool = false
var _elapsed: float = 0.0

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() < 2:
        print("args: host|join <url> [code]")
        quit(1)
        return
    _mode = args[0]
    var url: String = args[1]
    _db = MatchContent.db()
    _transport = WebSocketTransport.new()
    _transport.room_created.connect(_on_room_created)
    _transport.room_ready.connect(_on_room_ready)
    _transport.relay_error.connect(func(r): print("ERREUR RELAIS: ", r); quit(1))
    if _mode == "host":
        _transport.connect_create(url)
    else:
        _transport.connect_join(url, args[2])
    print("[%s] connexion à %s…" % [_mode, url])

func _on_room_created(code: String) -> void:
    print("[host] CODE DE ROOM = ", code, "  (lancez l'invité avec ce code)")

func _on_room_ready(role: int, seed_value: int, opponent_id: String) -> void:
    print("[%s] room prête (role=%d, seed=%d, adversaire=%s)" % [_mode, role, seed_value, opponent_id])
    if role == WebSocketTransport.ROLE_HOST:
        var state := GameCore.start_match(_db, _db.match_config, seed_value, ["host", "guest"])
        _session = NetSession.create_host(_db, state, _transport, "host", ["guest"])
    else:
        _session = NetSession.create_guest(_db, _transport, "guest", "host")

func _process(delta: float) -> bool:
    if _transport != null:
        _transport.poll(delta)
    if _session == null:
        return false
    if _mode == "host":
        _host_step(delta)
    else:
        _guest_step()
    return false

func _host_step(delta: float) -> void:
    if not _did_plan:
        _did_plan = true
        _session.host_apply_local({"type": Intents.ADD_INGREDIENT, "ingredient_id": "boeuf"})
        _session.host_apply_local({"type": Intents.ADD_ACTION, "action_id": "cuire"})
        _session.host_apply_local({"type": Intents.SET_READY, "ready": true})
    if _session.host_state().phase == GameState.Phase.EXECUTION:
        _session.host_tick(delta)
    if _session.host_state().phase == GameState.Phase.FINISHED:
        print("[host] MATCH TERMINÉ — résultat: ", _session.host_state().result)
        quit(0)

var _guest_ready: bool = false
func _guest_step() -> void:
    if not _guest_ready:
        _guest_ready = true
        _session.send_intent({"type": Intents.SET_READY, "ready": true})
    var v := _session.reconciler.current_view()
    if not v.is_empty() and int(v.get("phase", 0)) == GameState.Phase.FINISHED:
        print("[guest] vue finale reçue — phase FINISHED, tick=", _session.reconciler.current_tick_id())
        quit(0)
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `godot --headless --import && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_websocket_transport.gd -gexit`
Expected: PASS — 7 tests, 0 échec.

Puis la non-régression complète :

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected: « All tests passed! ».

- [ ] **Step 6: Commit**

```bash
git add net/websocket_transport.gd scripts/net_smoke.gd tests/test_websocket_transport.gd
git commit -m "feat(net): WebSocketTransport (socket + handshake relais + dispatch) + harnais smoke"
```

---

## Task 7 : Checklist E2E manuelle

**Files:**
- Create: `docs/MANUAL-E2E.md`

**Interfaces:**
- Consumes: relais (Tasks 4-5), `scripts/net_smoke.gd` (Task 6).
- Produces: procédure de vérification manuelle du chemin socket réel.

- [ ] **Step 1: Créer `docs/MANUAL-E2E.md`**

```markdown
# Food Wars — Smoke-test E2E manuel (transport réseau réel)

Vérifie le chemin socket réel que GUT ne couvre pas (`WebSocketPeer` +
relais Node). À exécuter après tout changement de `relay/` ou
`net/websocket_transport.gd`.

## Pré-requis
- Node ≥ 18, Godot 4.5 (`godot`).
- Une fois : `cd relay && npm install`.

## 1. Démarrer le relais
```bash
cd relay && npm start
# -> "Food Wars relay en écoute sur ws://localhost:8080"
```

## 2. Lancer l'hôte (terminal 2)
```bash
godot --headless -s scripts/net_smoke.gd -- host ws://localhost:8080
# -> "[host] CODE DE ROOM = XXXX"
```
✅ Attendu : un code de room à 4 caractères s'affiche.

## 3. Lancer l'invité (terminal 3), avec le code
```bash
godot --headless -s scripts/net_smoke.gd -- join ws://localhost:8080 XXXX
```
✅ Attendu :
- les deux affichent « room prête » avec la **même** seed et les rôles host/guest ;
- l'hôte joue le match et affiche « MATCH TERMINÉ — résultat: {winner:…} » ;
- l'invité affiche « vue finale reçue — phase FINISHED » ;
- les deux processus se terminent (exit 0).

## 4. Reconnexion (manuel)
- Relancer hôte + invité ; pendant que l'hôte attend/joue, tuer le process invité
  (Ctrl-C) **avant** la fin.
✅ Attendu côté relais/hôte : l'hôte ne plante pas ; un `peer_left` est routé
  (pause). Relancer l'invité avec le **même** code dans les 30 s.
✅ Attendu : l'hôte reçoit `peer_rejoined` (resync), l'invité reçoit une nouvelle
  `room_ready` et resynchronise. Au-delà de 30 s : l'invité obtient `unknown_code`
  (room fermée).

## 5. Déconnexion hôte
- Tuer l'hôte pendant une partie.
✅ Attendu : l'invité reçoit `host_left` → `session_aborted("host_disconnected")`.

## En cas d'échec
Noter le terminal fautif et le message. Le dispatch (parsing/mapping) est couvert
par `tests/test_websocket_transport.gd` et `relay/relay.test.js` ; un échec ici
pointe donc vers le vrai I/O socket (`connect_to_url`/`poll`/`send_text`) ou le
câblage `ws` de `relay/server.js`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/MANUAL-E2E.md
git commit -m "docs: checklist de smoke-test E2E manuel du transport réseau réel"
```

---

## Self-Review

**Couverture spec (`2026-07-23-food-wars-networking-realtransport-design.md`) :**
- §1 couture de polling : `ITransport.poll` no-op + `WebSocketTransport.poll` + `NetSession.poll` passe-plat → Tasks 2, 3, 6 ✅ ; `ITransport` reste `RefCounted` ✅.
- §2 relais Node/ws : rooms par code, `create`/`join`/`room_ready`/`error`, seed générée par le relais, transfert opaque des messages `kind` → Task 4 ✅ ; reconnexion 30 s (`peer_left`/`peer_rejoined`/`room_closed`) + `host_left` terminal → Task 5 ✅.
- §3 `WebSocketTransport` : handshake create/join, `room_ready`/`room_created`, `send` JSON, `poll` draine + dispatch, mapping reconnexion → Task 6 ✅.
- §4 changements additifs : `Protocol.serialize/deserialize` (T1), `ITransport.poll`+signaux (T2), `NetSession.poll`/`host_resync`/`session_resumed`/mapping terminal (T3), helpers InMemory (T2) ✅.
- §5 tests : relais JS déterministe (T4-5), morceaux headless GUT — round-trip JSON (T1), `host_resync` + mapping (T3), dispatch WebSocketTransport (T6) — E2E manuel documenté (T7) ✅.

**Scan placeholders :** aucun TODO/TBD ; chaque étape de code est complète. Le stub `onClose` de la Task 4 est explicitement remplacé en Task 5 (séquence incrémentale d'un même fichier, signalée).

**Cohérence des types / noms :** `serialize/deserialize`, `poll(delta)`, `peer_suspended/peer_resumed`, `emit_suspended/emit_resumed`, `session_resumed`, `host_resync`, `room_created/room_ready(role:int,seed_value:int,opponent_id:String)/relay_error`, `ROLE_HOST=0/ROLE_GUEST=1`, ids `"host"/"guest"`, messages de contrôle `created/room_ready/error/peer_left/peer_rejoined/room_closed/host_left` — identiques entre spec, blocs `Produces`, code et tests. Le relais forwarde le **texte brut** (pas de re-sérialisation) → pas de dérive int/float sur le fil ; côté Godot les lecteurs recastent via `int()`.

**Changement de comportement assumé (Task 3) :** `peer_disconnected` terminal (hôte → `session_aborted("peer_lost")`) remplace l'ancien `session_paused`. Le test `test_host_emits_paused_on_guest_drop` est réécrit ; la pause est désormais couverte par `test_host_emits_paused_on_peer_suspended`. Aligné sur la spec §4.

**Réutilisation Plan 3 :** `Protocol`, `ITransport`, `InMemoryTransport`, `Reconciler`, `NetSession`, `GameCore`, `MatchContent` consommés ; changements strictement additifs sauf la réécriture de test ci-dessus.
