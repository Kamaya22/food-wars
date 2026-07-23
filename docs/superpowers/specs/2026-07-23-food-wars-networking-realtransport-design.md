# Food Wars — Plan 3-bis : Transport réseau réel (relais + WebSocket) — Design

**Date** : 2026-07-23
**Statut** : validé, prêt pour writing-plans
**Portée** : rendre le jeu en réseau *réel* — un serveur relais exécutable + un `WebSocketTransport` Godot — en se branchant sur l'abstraction `ITransport` livrée au Plan 3.

Ce design prolonge la §4 de `2026-07-19-food-wars-architecture-design.md` (relais
WebSocket, migration) et lève les éléments explicitement reportés par
`2026-07-23-food-wars-networking-design.md` (transport réel, serveur relais,
fenêtre de reconnexion 30 s).

## Décisions verrouillées (brainstorming)

- **Stack relais** : Node.js + `ws` (routeur minimal, sans logique de jeu).
- **Matchmaking** : par **code de room** (un joueur crée → code court ; l'autre
  rejoint par code ; le créateur est l'hôte).
- **Reconnexion** : **fenêtre 30 s complète + resync** (l'invité peut revenir ;
  l'hôte rediffuse un snapshot complet). La déconnexion **hôte** reste fatale.
- **Tests** : relais **automatisé** (tests JS déterministes, sockets factices) ;
  `WebSocketTransport` + E2E complet **manuel** (checklist documentée), conforme
  à l'architecture §7 « Manuel / E2E ». Les morceaux de logique Godot testables
  en headless restent couverts par GUT.

---

## 1. Portée & couture de polling du transport

Plan 3-bis rend le jeu en réseau réel : un serveur relais exécutable + un vrai
`WebSocketTransport`, insérés dans l'abstraction du Plan 3.

**Le seul changement inévitable au code Godot du Plan 3** : `ITransport` /
`InMemoryTransport` sont synchrones et `RefCounted`, mais un vrai `WebSocketPeer`
doit être **sondé (`poll`) à chaque frame**. On ajoute donc `poll(delta)` à
`ITransport` (no-op pour `InMemoryTransport` ; draine le socket pour
`WebSocketTransport`). Le propriétaire de la boucle de frame (l'UI du Plan 4, ou
le harnais de test manuel) appelle `session.poll(delta)` à chaque frame.

Cela garde `ITransport` en `RefCounted` (pas d'héritage `Node`) et préserve la
couture de migration. **Tous les autres changements du Plan 3 sont purement
additifs** (nouveaux signaux, nouvelles méthodes) : rien d'existant ne casse, la
suite headless (113 tests) reste verte.

---

## 2. Serveur relais (`relay/server.js`, Node + ws)

Un routeur de messages sans aucune règle de jeu. État en mémoire :
`rooms: Map<code, {host, guest, seed, timer}>`.

### Protocole de contrôle

Messages de contrôle = JSON avec un champ `t`. Les messages **de jeu** (dicts du
`Protocol` Godot) ont un champ `kind` et sont **transférés opaquement** — le
relais ne les inspecte jamais.

| Client → Relais | Relais → Client(s) |
|---|---|
| `{t:"create"}` | `{t:"created", code}` (le créateur = hôte, en attente) |
| `{t:"join", code}` | succès → les deux reçoivent `{t:"room_ready", role, seed, opponent_id}` ; code invalide/plein/inconnu → `{t:"error", reason}` |
| *(tout message `kind`)* | transféré verbatim à l'autre membre de la room |

- **role** : `"host"` ou `"guest"`. **opponent_id** : l'identifiant de l'autre
  joueur (le relais attribue des ids, ex. `"host"`/`"guest"`). **seed** : le
  relais génère la graine du match et la donne aux deux (conforme au message ROOM
  de l'architecture §4). L'hôte s'en sert pour `GameCore.start_match`.
- **Code de room** : court, lisible (ex. 4 caractères alphanumériques sans
  ambiguïté). En cas de collision, régénérer.

### Reconnexion (30 s)

- À la **fermeture d'un socket**, la room est conservée avec un minuteur 30 s ;
  le pair restant reçoit `{t:"peer_left"}`.
- Si l'**invité** manquant **rejoint** (même code) dans la fenêtre → ré-attaché ;
  l'hôte reçoit `{t:"peer_rejoined"}` (l'hôte resynchronise alors). 
- Si la fenêtre **expire** → `{t:"room_closed"}` au pair restant, room supprimée.
- La déconnexion **hôte** est **terminale** → l'invité reçoit `{t:"host_left"}`
  et la room est fermée (l'invité ne peut pas continuer sans autorité).

Le relais n'exécute jamais de logique de jeu : il ne connaît que rooms, codes,
routage et minuteurs.

---

## 3. `WebSocketTransport` Godot (`net/websocket_transport.gd`)

Implémente `ITransport` par-dessus un unique `WebSocketPeer` vers le relais.

- **Connexion & handshake** : se connecte à l'URL du relais ; pilote le handshake
  create/join ; à réception de `room_ready`, émet un signal
  `room_ready(role: int, seed: int, opponent_id: String)` pour que l'application
  construise la bonne `NetSession` (hôte → `start_match` + `create_host` ;
  invité → `create_guest`), puis émet `peer_connected(opponent_id)`.
- **`send(peer_id, msg)`** : `Protocol.serialize(msg)` (JSON) puis écriture sur le
  socket ; le relais route vers le pair (`peer_id` informatif — un seul socket).
- **`poll(delta)`** : `WebSocketPeer.poll()`, draine les paquets, parse via
  `Protocol.deserialize`, émet `message_received(opponent_id, msg)` pour les
  messages de jeu ; traduit les événements de contrôle du relais en signaux.
- **Signaux de reconnexion** : `peer_left → peer_suspended` ;
  `peer_rejoined → peer_resumed` ; `host_left`/`room_closed → peer_disconnected`
  (terminal).
- **Rôle** : `role`, `seed`, `opponent_id` sont accessibles à l'application via le
  signal `room_ready`. Ces champs et le handshake sont spécifiques à
  `WebSocketTransport` (pas dans `ITransport` générique — `InMemoryTransport`
  n'a pas de rooms).

---

## 4. Changements Godot additifs (`ITransport`, `Protocol`, `NetSession`)

Tous rétro-compatibles avec le Plan 3.

- **`ITransport`** : ajouter `func poll(_delta: float) -> void` (no-op par
  défaut) et deux signaux `peer_suspended(peer_id: String)` /
  `peer_resumed(peer_id: String)`. Les signaux existants
  (`message_received`, `peer_connected`, `peer_disconnected`) sont inchangés.
- **`Protocol`** : ajouter `serialize(msg: Dictionary) -> String` (JSON) et
  `deserialize(text: String) -> Dictionary`. Les lecteurs existants castent déjà
  via `int()`, donc la coercition numérique de JSON est absorbée. (Le Plan 3
  reportait JSON ; c'est requis pour le fil maintenant.)
- **`NetSession`** :
  - `poll(delta)` : passe-plat vers `_transport.poll(delta)`.
  - `host_resync()` : rediffuse les vues filtrées courantes (réutilise
    `_broadcast`, ce qui incrémente `tick_id` pour que le `Reconciler` de
    l'invité de retour accepte le snapshot).
  - Mapping des signaux : `peer_suspended → session_paused` ;
    `peer_resumed → session_resumed` (nouveau signal) **+** `host_resync()` côté
    hôte ; `peer_disconnected → session_aborted`.
  - `InMemoryTransport` reçoit des helpers de test pour émettre
    `peer_suspended`/`peer_resumed` (afin de tester le mapping en headless).

---

## 5. Stratégie de tests

- **Relais (automatisé, JS, déterministe)** : `relay/server.test.js` avec des
  sockets factices en mémoire (pas de réseau réel) — création/jointure de room,
  codes invalides/dupliqués/pleins, transfert hôte↔invité, drop invité →
  `peer_left` → 30 s → `room_closed`, rejoin invité dans la fenêtre →
  `peer_rejoined`, drop hôte → `host_left`. Rapide et déterministe.
- **Côté Godot, morceaux testables en headless (GUT, restent dans la suite
  toujours-verte)** : round-trip `Protocol.serialize/deserialize` ;
  `NetSession.host_resync()` rediffuse bien ; le mapping des signaux
  suspend/resume/abort via les helpers d'`InMemoryTransport`. Pas de socket réel.
- **`WebSocketTransport` + E2E complet (manuel, documenté)** : une checklist
  `docs/MANUAL-E2E.md` — lancer le relais, ouvrir deux clients Godot, créer/
  rejoindre par code, jouer un match, exercer déconnexion → reconnexion. Conforme
  à l'architecture §7 ; le vrai code socket `WebSocketPeer` est vérifié ici, pas
  en GUT.

---

## Arborescence

**À créer :**
- `net/websocket_transport.gd` — client WS réel + handshake relais.
- `relay/server.js` — relais Node/ws (rooms, codes, routage, reconnexion 30 s).
- `relay/server.test.js` — tests unitaires du relais (sockets factices).
- `relay/package.json` — dépendance `ws` + script de test.
- `relay/README.md` — comment lancer le relais.
- `docs/MANUAL-E2E.md` — checklist de smoke-test manuel.

**À modifier (additif) :**
- `net/i_transport.gd` — `poll(delta)` + signaux `peer_suspended`/`peer_resumed`.
- `net/protocol.gd` — `serialize`/`deserialize`.
- `net/net_session.gd` — `poll`, `host_resync`, mapping resume/pause/abort +
  signal `session_resumed`.
- `net/in_memory_transport.gd` — helpers de test pour suspend/resume.

**Tests Godot à créer/étendre :**
- étendre `tests/test_protocol.gd` — round-trip JSON serialize/deserialize.
- étendre `tests/test_net_session.gd` — `host_resync`, mapping suspend/resume.

---

## Contraintes globales

- **Aucune modification de `core/`.** Le Cœur reste consommé tel quel.
- Les changements Godot du Plan 3 sont **additifs** : les 113 tests headless
  existants restent verts.
- Le relais ne contient **aucune logique de jeu** : rooms, codes, routage,
  minuteurs uniquement. Il transfère les messages `kind` sans les inspecter.
- Déterminisme du Cœur inchangé : le relais génère la seed une fois et la donne
  aux deux ; l'hôte reste l'unique autorité.
- `ITransport` demeure `RefCounted` (pas de `Node`) ; le polling est piloté par
  l'appelant via `session.poll(delta)`.
- Anti-triche préservée : le filtrage vit toujours dans `get_view` ; le relais ne
  voit que des messages opaques.

## Suite

- **Plan 4** — Présentation : scènes/UI, écran créer/rejoindre (code de room),
  input → Intentions, view-models liés à `Reconciler.current_view()`, appel de
  `session.poll(delta)` dans `_process`, optimistic UI léger.
- **Hors périmètre** (architecture §9) : hébergement du relais, matchmaking
  avancé (classement, files d'attente), persistance de compte.
