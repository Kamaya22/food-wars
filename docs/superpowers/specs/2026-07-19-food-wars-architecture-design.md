# Food Wars — Architecture technique (Godot 4)

- **Date** : 2026-07-19
- **Statut** : Design validé, prêt pour le plan d'implémentation
- **Source des besoins** : [`docs/food_wars_requirements.yaml`](../../food_wars_requirements.yaml)
- **Moteur** : Godot 4 — **GDScript**

---

## 1. Contexte et décisions fondatrices

Food Wars est un jeu de cuisine-cartes compétitif **1v1**, sessions ~10 min, cible **web / Android / iOS**, fortement **orienté données** (ingrédients, actions, cartes, événements, critères de jugement = entités réutilisables par le moteur).

Quatre décisions structurent toute l'architecture :

| Pilier | Décision | Conséquence |
|---|---|---|
| Mode 1v1 | **Online temps réel** (jeu par phases, pas twitch) | Netcode à cadence modérée, tolérant à la latence — pas de tick 60 Hz. |
| Autorité | **Client-hôte**, avec discipline de code pour rendre la migration serveur peu coûteuse | Le cœur de logique doit être pur/headless et déplaçable tel quel côté serveur. |
| Contenu | **YAML/JSON versionné → Resources Godot** | Contenu abondant éditable hors moteur, équilibrage scriptable. |
| Langage | **GDScript** (export web mûr et léger ; C# web trop récent/lourd) | Cœur isolé dans des classes pures `RefCounted`. |
| Réseau | **Relais WebSocket** (Approche A) — ENet éliminé car incompatible export HTML5 | Identique sur toutes plateformes ; migration serveur quasi gratuite. |

**Principe directeur (non négociable)** : *la logique de jeu ne connaît ni le rendu, ni le réseau.* C'est ce qui garantit la contrainte de migration.

---

## 2. Architecture en couches

Quatre couches à responsabilité unique ; les dépendances vont toujours vers le bas.

```
┌─────────────────────────────────────────────────────────┐
│  PRÉSENTATION (Godot nodes, scènes, UI, anim, audio)      │
│  Affiche l'état, capture les gestes → émet des Intentions │
└───────────────┬─────────────────────▲────────────────────┘
                │ Intentions           │ Snapshots d'état
┌───────────────▼─────────────────────┴────────────────────┐
│  RÉSEAU / SESSION (transport abstrait, relais WebSocket)   │
│  Route Intentions → hôte ; diffuse État → clients          │
└───────────────┬─────────────────────▲────────────────────┘
                │ apply(Intent)        │ GameState
┌───────────────▼─────────────────────┴────────────────────┐
│  CŒUR DE LOGIQUE  ★ pur, headless, testable ★             │
│  Règles, machine à phases, résolution, jugement, RNG seedé │
└───────────────┬───────────────────────────────────────────┘
                │ lit au démarrage
┌───────────────▼───────────────────────────────────────────┐
│  CONTENU / DONNÉES (YAML/JSON → Resources typées)          │
└────────────────────────────────────────────────────────────┘
```

**Règles de dépendance (garantissent la migration) :**
- Le **Cœur** ne référence jamais de nœud/rendu Godot (`Node`, `Sprite`, `get_tree()`…). Uniquement des classes pures `RefCounted` + les Resources de contenu injectées.
- La **Présentation** ne modifie jamais l'état directement : elle émet des **Intentions** et réagit aux snapshots reçus.
- Le **Réseau** ne connaît pas les règles : il transporte des Intentions et des snapshots opaques. Remplaçable (relais → serveur dédié) sans toucher au Cœur ni à la Présentation.

**Récompense** : passer à un serveur autoritaire = déployer le module Cœur inchangé dans un Godot headless + reconfigurer la couche Réseau. Pas de réécriture.

---

## 3. Cœur de logique (headless, pur, déterministe)

Déterministe : mêmes entrées + même seed = même partie (validation d'état, replay, debug).

### Contrat public

```
GameCore
  ├─ start_match(config, seed) -> GameState
  ├─ apply_intent(state, player_id, intent) -> Result{state', events[]}
  ├─ tick(state, delta) -> Result{state', events[]}   # avance timers (phase, actions, fenêtre events)
  └─ get_view(state, player_id) -> PlayerView          # état filtré (cache l'info adverse)
```

- `apply_intent` est la **seule** façon de muter l'état. Une Intention est une donnée sérialisable `{seq, type, payload}`, jamais un appel de méthode direct → réseau trivial.
- `tick` avance le temps ; **seul l'hôte tick**, les clients affichent l'état reçu.
- `get_view` = anti-triche gratuit : chaque client ne reçoit que ce qu'il a le droit de voir.

### Machine à phases

```
       ┌──────────┐  timer / prêt   ┌───────────┐  timer   ┌──────────┐
  ───▶ │ PLANNING │ ───────────────▶│ EXECUTION │ ────────▶│ JUDGMENT │──▶ FIN
       └──────────┘                 └─────┬─────┘          └──────────┘
        pose ingrédients,            ┌────▼─────┐           scores via
        budget, main de départ       │ EVENTS   │           judgment_criteria
                                     │ (RNG seedé,│          + bonus originalité
                                     │ fenêtre 4min)         → vainqueur
                                     └──────────┘
```

Chaque phase = objet `Phase` avec `enter()` / `handle_intent()` / `tick()` / `exit()`, testable isolément. Les transitions sont décidées par le Cœur, pas par l'UI.

### Sous-composants (chacun testable seul)

| Composant | Rôle |
|---|---|
| `PhaseMachine` | Orchestration planning/execution/judgment + transitions |
| `Timeline` | Séquence d'actions du joueur + durées, avancement |
| `StatEngine` | Applique les effets d'actions/ingrédients sur les stats du plat |
| `CardResolver` | Résout l'effet d'une carte (globale/contextuelle) |
| `EventScheduler` | Tire les événements aléatoires (RNG seedé) sur la fenêtre |
| `JudgmentEngine` | Score final via `judgment_criteria` pondérés + originalité |
| `RNG` | Générateur seedé unique, injecté partout |

**RNG** : un seul générateur seedé, fixé au `start_match`, partagé par l'autorité. Aucun `randi()` global. Garantit hôte/serveur identiques et neutralise une classe de triche.

### Points ouverts du YAML → configuration, pas du code en dur

Tous les `open_questions` (taille de main, ratio cartes contextuelles/globales, formule d'originalité, diminishing returns, durées de sous-phases) vivent dans un `match_config` chargé au démarrage. Équilibrage sans retoucher le Cœur.

---

## 4. Réseau : relais, protocole, migration

### Topologie

```
   CLIENT A (HÔTE)                                  CLIENT B (invité)
   ┌─────────────────────┐                      ┌─────────────────────┐
   │ Présentation         │                      │ Présentation         │
   │ Cœur (AUTORITÉ) ★     │                      │  (pas de Cœur actif) │
   │ NetSession           │                      │ NetSession           │
   └──────────┬───────────┘                      └──────────┬───────────┘
              │ WebSocket                                    │ WebSocket
              └───────────────┐              ┌───────────────┘
                              ▼              ▼
                        ┌──────────────────────────┐
                        │  RELAIS WebSocket          │
                        │  matchmaking + routage     │
                        │  aucune logique de jeu     │
                        └──────────────────────────┘
```

Le relais apparie deux joueurs dans une *room*, désigne l'hôte, puis route les messages. Il ne connaît aucune règle → jamais un point de triche ni un goulot logique.

### Couche `NetSession` (transport abstrait — clé de la migration)

```
ITransport            # interface : send(msg) ; signal message_received ; peer_connected/disconnected
WebSocketTransport    # implémentation d'aujourd'hui
DedicatedTransport    # implémentation de demain (même interface)
```

La Présentation et le Cœur ne parlent qu'à `NetSession`, jamais à `WebSocketPeer` directement.

### Protocole de messages

| Sens | Message | Contenu | Émis par |
|---|---|---|---|
| Client → Hôte | `INTENT` | `{seq, type, payload}` | invité (et hôte pour lui-même) |
| Hôte → Clients | `STATE_SNAPSHOT` | `PlayerView` filtrée + `tick_id` | hôte |
| Hôte → Clients | `EVENTS` | effets à jouer (anim/son) | hôte |
| Bi-directionnel | `PING/PONG` | horloge, latence | les deux |
| Relais → Clients | `ROOM` | rôle (hôte/invité), seed, adversaire | relais |

### Boucle de jeu réseau

1. L'invité agit → la Présentation émet un `INTENT` → `NetSession` l'envoie à l'hôte via le relais.
2. L'hôte applique `apply_intent` sur le Cœur autoritaire → nouvel état + events.
3. L'hôte diffuse `STATE_SNAPSHOT` (vue filtrée par joueur) + `EVENTS`.
4. Chaque client **réconcilie** son affichage sur le snapshot (l'état autoritaire gagne toujours).

**Réconciliation** : simple par snapshot (pas de prédiction client complexe — le jeu par phases le permet). **Optimistic UI léger** pour masquer la latence sur les gestes : la carte glisse visuellement tout de suite, l'état réel n'est confirmé qu'au snapshot ; si l'hôte refuse l'intent, l'UI se resynchronise.

### Gestion des pannes

| Panne | Comportement |
|---|---|
| Déconnexion invité | Pause hôte + fenêtre de reconnexion (~30 s), sinon abandon. |
| Déconnexion **hôte** | Faiblesse assumée du client-hôte : partie perdue/annulée. *(Résolu par la migration serveur.)* |
| Perte de paquets | WebSocket = TCP → livraison ordonnée ; `seq`/`tick_id` détectent les retards. |
| Intent invalide/trichée | L'hôte (autorité) rejette et renvoie un snapshot correcteur. |

### Chemin de migration (le Cœur ne change pas d'une ligne)

1. Déployer le module **Cœur** dans un Godot headless côté serveur (déjà sans rendu par construction).
2. Le relais pointe vers ce process serveur qui héberge le Cœur au lieu de router vers un client-hôte.
3. Côté clients : `NetSession` pointe vers le serveur au lieu du client-hôte ; aucun client n'exécute plus le Cœur.
4. Bénéfices automatiques : fin de la déconnexion-hôte fatale, anti-triche fort.

La migration est un changement de configuration/déploiement, pas une réécriture.

---

## 5. Pipeline de contenu (YAML/JSON → Resources)

### Flux de chargement

```
content/source/*.yaml  ──▶  ContentLoader  ──▶  ContentDB (registre lecture seule)
(ingredients, actions,      (parse + valide     ├─ ingredients / actions / cards
 cards, events, criteria,    + typage +         ├─ events / criteria
 match_config)               résout les refs)    └─ match_config
```

- **Godot 4 n'a pas de parseur YAML natif.** On édite en **YAML** (lisible, commenté, comme le requirements actuel) et un script d'import génère le **JSON** (natif via `JSON.parse`) que le jeu charge. Simple et robuste.
- `ContentDB` = singleton en lecture seule chargé une fois au boot, **injecté** au Cœur (qui reste testable avec un DB factice — pas de lookup global).

### Schémas d'entités (Resources typées)

```
IngredientRes : id, name, cost:int,
                stats:{umami,sucre,acide,gras,amer,texture : int}, tags:[String]
ActionRes     : id, name, base_duration_sec:int, effect:EffectSpec
CardRes       : id, name, type:{GLOBAL|CONTEXTUAL}, target:{SELF|OPPONENT},
                linked_action:id?  (requis si CONTEXTUAL), effect:EffectSpec
EventRes      : id, name, trigger_window:{PLANNING|EXECUTION|JUDGMENT}, effect:EffectSpec
CriterionRes  : id, weight:float, note:String?
MatchConfigRes: ingredient_budget:int, ingredients_per_player:{min,max},
                timeline_actions:{min,max}, deck_size:{min,max},
                starting_hand_size:int,
                phase_durations:{planning,execution,judgment},
                event_frequency_window_min:int, originality_formula:…
```

**Les effets sont des données, pas du code.** Un `EffectSpec` décrit *quoi* modifier (`{stat: delta}`) ou une **règle nommée** (`{"stop_oven_seconds": 5}`) interprétée par le Cœur (`StatEngine`/`CardResolver`). Ajouter une carte = une ligne de YAML, zéro code. Les cas exotiques passent par une règle nommée → point d'extension unique et contrôlé.

### Validation à l'import (échouer tôt, bruyamment)

`ContentLoader` refuse un contenu incohérent **avant** le démarrage :
- `cost` ≥ 0, poids numériques, stats dans les bornes.
- Intégrité référentielle : une carte `CONTEXTUAL` pointe un `linked_action` existant ; un event cible une phase valide.
- Bornes croisées avec `MatchConfig` (ex. `deck_size.min` ≤ cartes définies).
- Unicité des `id`.

Erreur de contenu = message clair au chargement, jamais un crash en pleine partie.

---

## 6. Arborescence du projet

```
food_wars/
├─ core/                      ★ CŒUR PUR — aucun import de rendu
│  ├─ game_core.gd            # start_match/apply_intent/tick/get_view
│  ├─ game_state.gd           # état sérialisable
│  ├─ phases/                 # planning.gd, execution.gd, judgment.gd, phase_machine.gd
│  ├─ systems/                # stat_engine, card_resolver, event_scheduler, timeline, judgment_engine
│  ├─ intents.gd              # types d'Intentions + validation de forme
│  └─ rng.gd                  # générateur seedé injectable
├─ content/                   # DONNÉES
│  ├─ source/*.yaml           # édité à la main
│  ├─ compiled/*.json         # généré à l'import (chargé par le jeu)
│  ├─ resources/*.gd          # IngredientRes, ActionRes, CardRes, EventRes, …
│  ├─ content_loader.gd       # parse + valide + résout les refs
│  └─ content_db.gd           # registre lecture seule (injecté au Cœur)
├─ net/                       # RÉSEAU
│  ├─ net_session.gd          # façade unique pour la Présentation
│  ├─ i_transport.gd          # interface
│  ├─ websocket_transport.gd  # implémentation d'aujourd'hui
│  ├─ protocol.gd             # (dé)sérialisation des messages
│  └─ reconciler.gd           # applique les snapshots à l'affichage
├─ presentation/              # PRÉSENTATION (Godot nodes/scènes)
│  ├─ scenes/                 # match.tscn, board.tscn, card.tscn, hand.tscn
│  ├─ ui/                     # HUD, timers de phase, jauges de stats
│  ├─ view_models/            # mappe PlayerView → affichage
│  └─ input/                  # capture gestes → émet des Intentions
├─ relay/                     # serveur relais (hors moteur Godot)
│  └─ server.(js|go)          # matchmaking + routage, sans logique de jeu
├─ tests/
└─ project.godot
```

---

## 7. Stratégie de tests

Le cœur étant pur et déterministe, l'essentiel se teste **sans lancer Godot ni le réseau**.

| Niveau | Cible | Ce qu'on teste | Outil |
|---|---|---|---|
| **Unitaire** | `core/systems/*`, `content_loader` | StatEngine, JudgmentEngine, résolution de cartes, validation de contenu | GUT |
| **Simulation** | `game_core` complet | Partie entière jouée par un script d'Intentions + seed fixe → état final déterministe attendu | GUT, headless |
| **Contrat réseau** | `protocol`, `reconciler` | Round-trip sérialisation ; reconstruction d'affichage depuis snapshot ; rejet d'intent invalide | GUT |
| **Intégration** | hôte + invité local | Deux `NetSession` reliées par un transport en mémoire (faux relais) → partie de bout en bout | GUT |
| **Manuel / E2E** | builds web + mobile | Latence réelle, exports, ressenti | manuel |

**Test de simulation = liste d'Intentions + seed → état final vérifiable.** Verrouille l'équilibrage et rejoue n'importe quel bug de partie à l'identique.

---

## 8. Anti-triche « par construction »

Rien ajouté après coup — découle des choix ci-dessus : autorité unique sur le Cœur, `get_view` qui filtre l'information, RNG seedé côté autorité, validation des Intentions. La migration serveur transforme ce « bon » anti-triche client-hôte en anti-triche « fort », sans changer le Cœur.

---

## 9. Points hors périmètre de cette spec (à traiter plus tard)

- Contenu et structure du **mode Exploration** (spec dédiée).
- Chiffrage précis du game design (valeurs de `match_config`, formule d'originalité, diminishing returns) — paramètres de config, itérés en équilibrage.
- Direction artistique / palette / assets.
- Choix d'hébergement du relais et matchmaking avancé (classement, files d'attente).
- Persistance de compte / progression.
