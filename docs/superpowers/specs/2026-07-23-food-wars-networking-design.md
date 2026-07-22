# Food Wars — Plan 3 : Réseau (couche moteur) — Design

**Date** : 2026-07-23
**Statut** : validé, prêt pour writing-plans
**Portée** : couche réseau côté Godot uniquement, 100 % testable en headless (GUT). Le `WebSocketTransport` réel et le serveur relais sont **explicitement reportés** à un plan ultérieur.

Ce design raffine la §4 (« Réseau : relais, protocole, migration ») de
`2026-07-19-food-wars-architecture-design.md`. Les décisions verrouillées là-bas
(topologie relais, autorité hôte, `ITransport`/`NetSession`, protocole de messages,
réconciliation par snapshot + optimistic UI léger, chemin de migration) sont
reprises telles quelles ; ce document en fixe la **portée du Plan 3** et les
interfaces précises.

---

## 1. Portée & arborescence

Le Plan 3 construit **uniquement la couche réseau côté Godot**, entièrement
testable sans lancer Godot ni ouvrir de socket. Le Cœur (`GameCore`, `GameState`,
`PlayerState`, systèmes) est **consommé sans modification** — aucun fichier de
`core/` n'est touché.

Nouveaux fichiers sous `net/` :

```
net/
├─ i_transport.gd          # interface : send(peer_id, msg) ; signals message_received / peer_connected / peer_disconnected
├─ in_memory_transport.gd  # faux relais pour les tests — deux sessions câblées en mémoire
├─ protocol.gd             # (dé)sérialisation des messages : INTENT / STATE_SNAPSHOT / EVENTS / ROOM
├─ net_session.gd          # logique de session hôte & invité ; seul point de contact Présentation/Cœur
└─ reconciler.gd           # magasin de view-model côté client (dernière PlayerView + rollback d'intents en attente)
```

**Reporté (hors Plan 3)** :
- `websocket_transport.gd` (implémentation `WebSocketPeer` réelle).
- Serveur relais (process hors moteur Godot).
- Fenêtre de reconnexion ~30 s + resynchronisation à la reconnexion.

---

## 2. Composants & interfaces

### `ITransport` (interface abstraite)

Contrat unique que `WebSocketTransport`/`DedicatedTransport` implémenteront plus
tard à l'identique.

```
send(peer_id: String, msg: Dictionary) -> void
signal message_received(from_peer: String, msg: Dictionary)
signal peer_connected(peer_id: String)
signal peer_disconnected(peer_id: String)
```

La Présentation et le Cœur ne parlent **jamais** à `WebSocketPeer` directement,
seulement à `NetSession`, qui parle à `ITransport`.

### `InMemoryTransport` (implémentation de test)

Deux instances partagent une table de routage : un `send` sur l'une déclenche
`message_received` sur l'autre, de façon **synchrone et déterministe**. Pas
d'horloge, pas de socket. C'est le « faux relais » exigé par la stratégie de test
de l'architecture. Sait simuler `peer_connected`/`peer_disconnected` pour les
tests de panne.

### `Protocol` (fonctions pures)

`encode(msg) -> Dictionary` / `decode(dict) -> msg`, une paire par type de
message. Aucun état moteur, round-trippable.

| Message | Contenu | Émis par |
|---|---|---|
| `ROOM` | `{role, seed, opponent_id}` | (relais — simulé côté test) |
| `INTENT` | `{seq, type, payload}` | invité (et hôte pour lui-même) |
| `STATE_SNAPSHOT` | `PlayerView` filtrée + `tick_id` | hôte |
| `EVENTS` | tableau d'effets à jouer (anim/son) | hôte |

`PlayerView` = sortie de `GameCore.get_view(db, state, viewer_id)` :
`{phase, phase_time_left, result, you, opponents}`.
`INTENT.payload` = une Intention validée par `Intents.validate_shape`.

### `NetSession` (deux rôles)

**Hôte** — détient le `GameState` autoritaire (unique). API :
- `send_intent(intent)` : applique l'intent local de l'hôte lui-même.
- réception d'un `INTENT` : `GameCore.apply_intent(db, state, player_id, intent)`
  → `{state, events}` → diffusion.
- `tick(delta)` : `GameCore.tick(db, state, delta)` → `{state, events}` →
  diffusion. Appelé par le `_process` de la Présentation (Plan 4) ou manuellement
  dans les tests.
- diffusion : pour chaque joueur, `get_view(db, state, viewer_id)` →
  `STATE_SNAPSHOT` filtré (+ `tick_id`) + `EVENTS`.

**Invité** — pas de Cœur actif. API :
- `send_intent(intent)` : `Protocol.encode` → `ITransport.send` vers l'hôte ;
  enregistre l'intent en attente auprès du `Reconciler`.
- réception `STATE_SNAPSHOT`/`EVENTS` : transmet au `Reconciler`.

`tick_id` : compteur monotone côté hôte, incrémenté à chaque diffusion (après
`apply_intent` et après `tick`).

### `Reconciler` (côté client, sans UI)

Magasin de view-model auquel l'UI du Plan 4 se liera.

```
apply_snapshot(view: Dictionary, tick_id: int) -> void   # accepté seulement si tick_id plus récent ; sinon ignoré
current_view() -> Dictionary                             # dernière PlayerView autoritaire (ou {} avant le 1er snapshot)
add_pending_intent(seq: int) -> void                     # suit un intent local envoyé
# à la réception d'un snapshot correcteur : purge des intents en attente non confirmés -> resync
```

Rôle : garder la dernière `PlayerView` autoritaire (le plus grand `tick_id`
gagne), jeter les snapshots périmés/désordonnés, suivre les intents locaux en
attente et les annuler quand l'autorité corrige. Aucune prédiction complexe.

---

## 3. Flux de données (boucle réseau)

1. UI invité (futur) → `NetSession.send_intent(intent)` → `Protocol.encode` →
   `ITransport.send` → hôte. Le `Reconciler` de l'invité enregistre `seq` en
   attente.
2. `NetSession` hôte reçoit `INTENT` →
   `GameCore.apply_intent(db, state, player_id, intent)` → `{state, events}`.
3. Hôte, pour chaque joueur : `get_view(db, state, viewer_id)` → envoie à **ce**
   joueur son `STATE_SNAPSHOT` filtré (+ `tick_id`) et ses `EVENTS`. Le filtrage
   anti-triche vit déjà dans `get_view` (main adverse masquée).
4. Chaque `Reconciler` client → `apply_snapshot` met à jour `current_view()`.
5. L'hôte pilote aussi `tick(delta)` sur sa boucle et diffuse les
   snapshots/events résultants de la même façon.

Seul l'hôte exécute le Cœur ; les invités sont de purs consommateurs de vue.

---

## 4. Gestion des pannes

- `ITransport` émet `peer_disconnected` ; `NetSession` le remonte en signaux
  `session_paused` / `session_aborted`. Déconnexion **hôte** = `session_aborted`
  (faiblesse assumée du client-hôte, résolue par la future migration serveur).
  **Le minuteur de reconnexion ~30 s et la resynchronisation à la reconnexion
  sont reportés** au plan du transport réel (nécessitent horloge murale + socket).
- **Intent invalide** : `apply_intent` renvoie déjà un event
  `{type: "intent_rejected", reason}` et l'état **inchangé**. L'hôte détecte cet
  event et renvoie au client fautif un `STATE_SNAPSHOT` **correcteur**, pour que
  son optimistic UI se resynchronise. Le `Reconciler` purge l'intent en attente
  correspondant.
- Snapshots périmés/désordonnés : jetés par comparaison de `tick_id` dans le
  `Reconciler`.

---

## 5. Tests (GUT, headless)

- **Protocol** : round-trip encode/decode pour chaque type de message, y compris
  dictionnaires d'intent/vue imbriqués.
- **Reconciler** : le plus récent gagne ; périmé jeté ; ajout/purge d'intent en
  attente ; rollback sur snapshot correcteur.
- **InMemoryTransport** : `send` route vers le pair ; les signaux
  connect/disconnect se déclenchent.
- **Intégration** (test phare) : `NetSession` hôte + invité câblées via un même
  `InMemoryTransport`, partie déterministe de bout en bout — l'invité envoie des
  intents, l'hôte applique + diffuse, les deux réconciliateurs convergent, un
  intent invalide est corrigé, la partie atteint `FINISHED` avec un résultat
  autoritaire identique. Miroir de `test_integration_match.gd` mais à travers la
  couture réseau.

L'essentiel se teste **sans lancer Godot ni le réseau** — cohérent avec les
Plans 1 & 2.

---

## Contraintes globales

- Aucune modification de `core/`. Le Cœur est consommé via
  `start_match` / `apply_intent` / `tick` / `get_view` / `GameState.to_dict` /
  `from_dict` uniquement.
- Déterminisme : itération triée sur `player_order` pour la diffusion ; aucun
  usage d'horloge murale (les tests pilotent `tick(delta)` explicitement).
- `net/` ne dépend jamais de la Présentation (Plan 4) : le `Reconciler` expose un
  view-model, il ne dessine rien.

## Suite

- **Plan 3-bis / transport réel** — `WebSocketTransport` (`WebSocketPeer`),
  serveur relais (matchmaking + routage, hors moteur), fenêtre de reconnexion
  30 s + resync, smoke test runtime à deux clients.
- **Plan 4** — Présentation : scènes Godot, UI, input → Intentions, view models
  liés à `Reconciler.current_view()`, optimistic UI.
