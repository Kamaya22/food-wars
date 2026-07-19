# Food Wars — Plan 2 : Cœur de partie & machine à phases

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Faire tourner un **match complet et déterministe** dans le cœur pur/headless : machine à phases (planning → exécution → jugement → fini), pose d'ingrédients/actions sous budget, cartes (deck, pioche, jeu de cartes globales/contextuelles), événements aléatoires seedés, exécution séquentielle des actions dans le temps, puis jugement via les critères pondérés. Le tout piloté par des **Intentions** sérialisables et un contrat public `start_match / apply_intent / tick / get_view`, sans rendu ni réseau.

**Architecture:** Étend la couche **Cœur** du Plan 1. `GameState`/`PlayerState` sont des données sérialisables ; `GameCore` est la façade statique (mutation en place de l'état + flux d'`events` retourné) ; les systèmes (`Intents`, `EffectResolver`, `CardResolver`, `Timeline`, `EventScheduler`, `PhaseMachine`, `Dish`) ont chacun une responsabilité unique. Tout aléa passe par l'`Rng` seedé du Plan 1 (état sérialisé dans `GameState`). Réutilise `Stats`, `StatEngine`, `JudgmentEngine`, les Resources et `ContentDB` du Plan 1 sans les modifier.

**Tech Stack:** Godot 4.5 (GDScript), GUT headless. `godot` est sur le PATH (voir Plan 1). Rappels d'exécution : après ajout de scripts `class_name`, lancer `godot --headless --import` avant GUT ; bruit non-fatal de l'addon GUT (NavigationServer*Manager) à ignorer ; versionner les sidecars `.uid` ; indentation **4 espaces** (house style du projet).

## Global Constraints

- **Moteur** : Godot 4.5, **GDScript uniquement**. Aucun C#.
- **Pureté du Cœur** : tous les fichiers sous `core/` référencent uniquement `RefCounted`/`Resource`/types de données. Aucune API de rendu/nœud (`Node`, `get_tree()`, `Sprite`, …). C'est ce qui permet la future migration serveur (spec §2).
- **Déterminisme absolu** : aucun `randi()`/`randf()` global ; tout aléa via une instance `Rng` (Plan 1) restaurée depuis `GameState.rng_state` et resauvegardée. **Toute itération sur un dictionnaire de `ContentDB` doit se faire sur ses clés triées** (`keys()` puis `.sort()`) avant tout tirage — l'ordre d'itération d'un `Dictionary` n'est pas garanti et casserait le déterminisme.
- **Le temps est en secondes flottantes** : `tick(state, delta_sec)` ; le Cœur est déterministe pour une même *suite* de deltas + seed.
- **Mutation en place** : `apply_intent` et `tick` mutent le `GameState` reçu et retournent `{"state": GameState, "events": Array}`. Une Intention invalide ne mute rien et produit un event `intent_rejected`.
- **Anti-triche par construction** : les `events` diffusables ne doivent jamais contenir d'information cachée (ex. l'id d'une carte piochée) ; `get_view` filtre la main adverse.
- **Décisions de game design verrouillées pour ce plan** :
  - Exécution **séquentielle dans le temps** : les actions de la timeline d'un joueur s'exécutent l'une après l'autre ; chacune consomme `base_duration_sec` ; un délai (`exec_delay_left`) met en pause la progression.
  - Fin de planning : **timer expiré OU les deux joueurs `ready`**.
  - Cartes **incluses** : deck construit par tirage avec remise jusqu'à `deck_size`, main de départ, **pioche d'1 carte à chaque action terminée** (`draw_trigger = action_transition`), jeu de cartes globales (n'importe quand) et contextuelles (seulement si l'action liée s'exécute sur la cible).
  - Originalité **reportée** : le jugement reste `JudgmentEngine.judge` (critères pondérés du Plan 1).
- **Tests** : GUT headless ; chaque test assert un comportement réel ; sortie propre (hors bruit addon GUT). Fichiers `snake_case.gd`, classes `PascalCase` via `class_name`.

---

## Modèle de données partagé (référence — implémenté aux Tasks 1-2, cité par toutes les tâches)

Toutes les tâches utilisent EXACTEMENT ces noms.

### `GameState.Phase` (enum, dans `core/game_state.gd`)
`enum Phase { PLANNING, EXECUTION, JUDGMENT, FINISHED }`

### `GameState` (champs)
- `seed: int`
- `rng_state: int` — état sérialisé de l'`Rng`
- `phase: int` (une valeur `Phase`)
- `phase_time_left: float`
- `event_timer_left: float`
- `player_order: Array` — ids joueurs, ordre d'itération déterministe
- `players: Dictionary` — `player_id: String → PlayerState`
- `config: Dictionary` — snapshot scalaire (clés : `ingredient_budget`, `ingredients_max`, `timeline_max`, `deck_size`, `starting_hand_size`, `planning_sec`, `execution_sec`, `judgment_sec`, `event_window_sec`)
- `result: Dictionary` — `{}` tant que non jugé ; puis `{"scores": {player_id: float}, "winner": String}` (`winner` = id gagnant ou `""` si nul)

### `PlayerState` (champs)
- `budget_left: int`
- `ingredients: Array` — ids d'ingrédients posés
- `timeline: Array` — ids d'actions, dans l'ordre
- `hand: Array` — ids de cartes en main
- `deck: Array` — ids de cartes restant à piocher (pioche par l'avant)
- `ready: bool`
- `exec_index: int` — index de l'action en cours d'exécution (0 au début ; = `timeline.size()` quand tout est fait)
- `exec_elapsed: float` — secondes écoulées sur l'action en cours
- `exec_delay_left: float` — secondes de pause restantes (délai d'un event/carte)
- `stat_modifiers: Dictionary` — deltas de stats cumulés par cartes/événements

### Intent (forme)
`Dictionary` `{"type": String, ...payload}`. Constantes de type dans `core/intents.gd` :
`ADD_INGREDIENT="add_ingredient"`, `REMOVE_INGREDIENT="remove_ingredient"`, `ADD_ACTION="add_action"`, `REMOVE_ACTION="remove_action"`, `SET_READY="set_ready"`, `PLAY_CARD="play_card"`.

### Event (forme)
`Dictionary` `{"type": String, ...}`. Types émis : `intent_rejected{reason}`, `ingredient_added{player,ingredient_id}`, `ingredient_removed{player,ingredient_id}`, `action_added{player,action_id}`, `action_removed{player,action_id}`, `ready_changed{player,ready}`, `card_played{player,card_id,target}`, `card_drawn{player}` (jamais l'id — anti-triche), `action_completed{player,action_id}`, `phase_changed{from,to}`, `event_fired{event_id,description}`, `judged{result}`, `match_finished{result}`.

### Contrat `GameCore` (statique, dans `core/game_core.gd`)
- `start_match(db: ContentDB, config: MatchConfigRes, seed: int, player_ids: Array) -> GameState`
- `apply_intent(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary` → `{"state","events"}`
- `tick(db: ContentDB, state: GameState, delta: float) -> Dictionary` → `{"state","events"}`
- `get_view(db: ContentDB, state: GameState, viewer_id: String) -> Dictionary` (prend `db` car la dérivation du plat en a besoin)

### Dérivation du plat (`core/systems/dish.gd`)
`Dish.compute(db, player) -> Dictionary` = `Stats.clamp_stats( Stats.add( StatEngine.compute_dish(ings, applied_actions), player.stat_modifiers ), StatEngine.STAT_MIN, StatEngine.STAT_MAX )` où `ings` = `player.ingredients` mappés en `IngredientRes`, `applied_actions` = `player.timeline` **tronqué à `[0, exec_index)`** mappé en `ActionRes`.

---

## Structure de fichiers

| Fichier | Responsabilité |
|---|---|
| `core/player_state.gd` | `PlayerState` — données joueur + `to_dict`/`from_dict` |
| `core/game_state.gd` | `GameState` + enum `Phase` + `to_dict`/`from_dict` |
| `core/intents.gd` | `Intents` — constantes de type + `validate_shape` |
| `core/systems/effect_resolver.gd` | `EffectResolver` — applique un `EffectSpec` à un `PlayerState` |
| `core/systems/card_resolver.gd` | `CardResolver` — cible + applicabilité + application d'une carte jouée |
| `core/systems/timeline.gd` | `Timeline` — progression séquentielle des actions dans le temps |
| `core/systems/event_scheduler.gd` | `EventScheduler` — tir d'événements windowés seedés |
| `core/systems/dish.gd` | `Dish` — calcul du plat courant d'un joueur |
| `core/systems/phase_machine.gd` | `PhaseMachine` — transitions de phases + entrées de phase + jugement |
| `core/game_core.gd` | `GameCore` — façade `start_match/apply_intent/tick/get_view` |
| `tests/*.gd` | Suites GUT (une par système + intégration) |
| `tests/fixtures/match_content.gd` | `MatchContent.db()` — un `ContentDB` prêt pour les tests de match |

---

### Task 1 : `PlayerState` + `GameState` + enum `Phase` + sérialisation

**Files:**
- Create: `core/player_state.gd`
- Create: `core/game_state.gd`
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Consumes: rien (données pures).
- Produces: `PlayerState` et `GameState` avec les champs du Modèle de données partagé, plus `to_dict()/from_dict(d)` sur chacun (round-trip fidèle), et l'enum `GameState.Phase`.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_game_state.gd` :

```gdscript
extends GutTest

func test_player_state_roundtrip():
    var p := PlayerState.new()
    p.budget_left = 7
    p.ingredients = ["tomate", "boeuf"]
    p.timeline = ["cuire"]
    p.hand = ["c1"]
    p.deck = ["c2", "c3"]
    p.ready = true
    p.exec_index = 1
    p.exec_elapsed = 2.5
    p.exec_delay_left = 0.0
    p.stat_modifiers = {"umami": 2}
    var back := PlayerState.from_dict(p.to_dict())
    assert_eq(back.budget_left, 7)
    assert_eq(back.ingredients, ["tomate", "boeuf"])
    assert_eq(back.timeline, ["cuire"])
    assert_eq(back.hand, ["c1"])
    assert_eq(back.deck, ["c2", "c3"])
    assert_true(back.ready)
    assert_eq(back.exec_index, 1)
    assert_almost_eq(back.exec_elapsed, 2.5, 0.001)
    assert_eq(int(back.stat_modifiers["umami"]), 2)

func test_phase_enum_values():
    assert_eq(GameState.Phase.PLANNING, 0)
    assert_eq(GameState.Phase.FINISHED, 3)

func test_game_state_roundtrip():
    var s := GameState.new()
    s.seed = 42
    s.rng_state = 123
    s.phase = GameState.Phase.EXECUTION
    s.phase_time_left = 12.0
    s.event_timer_left = 240.0
    s.player_order = ["p0", "p1"]
    s.config = {"ingredient_budget": 10}
    s.result = {}
    var p := PlayerState.new()
    p.budget_left = 3
    s.players = {"p0": p, "p1": PlayerState.new()}
    var back := GameState.from_dict(s.to_dict())
    assert_eq(back.seed, 42)
    assert_eq(back.phase, GameState.Phase.EXECUTION)
    assert_almost_eq(back.phase_time_left, 12.0, 0.001)
    assert_eq(back.player_order, ["p0", "p1"])
    assert_eq(back.players.size(), 2)
    assert_eq(back.players["p0"].budget_left, 3)
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_state.gd -gexit`
Expected : FAIL — `PlayerState`/`GameState` non définis.

- [ ] **Step 3 : Implémenter `core/player_state.gd`**

```gdscript
class_name PlayerState
extends RefCounted

var budget_left: int = 0
var ingredients: Array = []
var timeline: Array = []
var hand: Array = []
var deck: Array = []
var ready: bool = false
var exec_index: int = 0
var exec_elapsed: float = 0.0
var exec_delay_left: float = 0.0
var stat_modifiers: Dictionary = {}

func to_dict() -> Dictionary:
    return {
        "budget_left": budget_left,
        "ingredients": ingredients.duplicate(),
        "timeline": timeline.duplicate(),
        "hand": hand.duplicate(),
        "deck": deck.duplicate(),
        "ready": ready,
        "exec_index": exec_index,
        "exec_elapsed": exec_elapsed,
        "exec_delay_left": exec_delay_left,
        "stat_modifiers": stat_modifiers.duplicate(),
    }

static func from_dict(d: Dictionary) -> PlayerState:
    var p := PlayerState.new()
    p.budget_left = int(d.get("budget_left", 0))
    p.ingredients = (d.get("ingredients", []) as Array).duplicate()
    p.timeline = (d.get("timeline", []) as Array).duplicate()
    p.hand = (d.get("hand", []) as Array).duplicate()
    p.deck = (d.get("deck", []) as Array).duplicate()
    p.ready = bool(d.get("ready", false))
    p.exec_index = int(d.get("exec_index", 0))
    p.exec_elapsed = float(d.get("exec_elapsed", 0.0))
    p.exec_delay_left = float(d.get("exec_delay_left", 0.0))
    p.stat_modifiers = (d.get("stat_modifiers", {}) as Dictionary).duplicate()
    return p
```

- [ ] **Step 4 : Implémenter `core/game_state.gd`**

```gdscript
class_name GameState
extends RefCounted

enum Phase { PLANNING, EXECUTION, JUDGMENT, FINISHED }

var seed: int = 0
var rng_state: int = 0
var phase: int = Phase.PLANNING
var phase_time_left: float = 0.0
var event_timer_left: float = 0.0
var player_order: Array = []
var players: Dictionary = {}
var config: Dictionary = {}
var result: Dictionary = {}

func to_dict() -> Dictionary:
    var pl: Dictionary = {}
    for id in players:
        pl[id] = players[id].to_dict()
    return {
        "seed": seed,
        "rng_state": rng_state,
        "phase": phase,
        "phase_time_left": phase_time_left,
        "event_timer_left": event_timer_left,
        "player_order": player_order.duplicate(),
        "players": pl,
        "config": config.duplicate(),
        "result": result.duplicate(),
    }

static func from_dict(d: Dictionary) -> GameState:
    var s := GameState.new()
    s.seed = int(d.get("seed", 0))
    s.rng_state = int(d.get("rng_state", 0))
    s.phase = int(d.get("phase", Phase.PLANNING))
    s.phase_time_left = float(d.get("phase_time_left", 0.0))
    s.event_timer_left = float(d.get("event_timer_left", 0.0))
    s.player_order = (d.get("player_order", []) as Array).duplicate()
    s.config = (d.get("config", {}) as Dictionary).duplicate()
    s.result = (d.get("result", {}) as Dictionary).duplicate()
    var pl: Dictionary = d.get("players", {})
    for id in pl:
        s.players[id] = PlayerState.from_dict(pl[id])
    return s
```

- [ ] **Step 5 : Lancer, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_state.gd -gexit`
Expected : PASS (3 tests).

- [ ] **Step 6 : Commit**

```bash
git add core/player_state.gd core/player_state.gd.uid core/game_state.gd core/game_state.gd.uid tests/test_game_state.gd tests/test_game_state.gd.uid
git commit -m "feat(core): GameState/PlayerState + enum Phase + sérialisation"
```

---

### Task 2 : `Intents` — constantes de type + `validate_shape`

**Files:**
- Create: `core/intents.gd`
- Test: `tests/test_intents.gd`

**Interfaces:**
- Consumes: rien.
- Produces:
  - Constantes : `Intents.ADD_INGREDIENT`, `REMOVE_INGREDIENT`, `ADD_ACTION`, `REMOVE_ACTION`, `SET_READY`, `PLAY_CARD` (les chaînes du Modèle de données partagé).
  - `Intents.validate_shape(intent: Dictionary) -> Dictionary` → `{"ok": bool, "error": String}`. Vérifie que `type` est une chaîne connue et que le payload minimal est présent avec le bon type (id chaîne non vide, index entier, `ready` booléen). NE vérifie PAS les règles de jeu (budget/phase/main).

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_intents.gd` :

```gdscript
extends GutTest

func test_valid_add_ingredient():
    var r := Intents.validate_shape({"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    assert_true(r.ok, r.error)

func test_valid_set_ready():
    assert_true(Intents.validate_shape({"type": Intents.SET_READY, "ready": true}).ok)

func test_valid_play_card_optional_target():
    assert_true(Intents.validate_shape({"type": Intents.PLAY_CARD, "card_id": "c1"}).ok)
    assert_true(Intents.validate_shape({"type": Intents.PLAY_CARD, "card_id": "c1", "target_player_id": "p1"}).ok)

func test_unknown_type_rejected():
    var r := Intents.validate_shape({"type": "voler_recette"})
    assert_false(r.ok)
    assert_true(r.error.length() > 0)

func test_missing_payload_rejected():
    assert_false(Intents.validate_shape({"type": Intents.ADD_INGREDIENT}).ok)
    assert_false(Intents.validate_shape({"type": Intents.REMOVE_ACTION, "index": "pas_un_int"}).ok)
    assert_false(Intents.validate_shape({"type": Intents.SET_READY, "ready": "oui"}).ok)

func test_non_dict_or_missing_type_rejected():
    assert_false(Intents.validate_shape({}).ok)
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_intents.gd -gexit`
Expected : FAIL — `Intents` non défini.

- [ ] **Step 3 : Implémenter `core/intents.gd`**

```gdscript
class_name Intents
extends RefCounted

const ADD_INGREDIENT := "add_ingredient"
const REMOVE_INGREDIENT := "remove_ingredient"
const ADD_ACTION := "add_action"
const REMOVE_ACTION := "remove_action"
const SET_READY := "set_ready"
const PLAY_CARD := "play_card"

static func _ok() -> Dictionary:
    return {"ok": true, "error": ""}

static func _err(msg: String) -> Dictionary:
    return {"ok": false, "error": msg}

static func _is_id(v) -> bool:
    return typeof(v) == TYPE_STRING and (v as String).length() > 0

static func validate_shape(intent: Dictionary) -> Dictionary:
    if not intent.has("type") or typeof(intent["type"]) != TYPE_STRING:
        return _err("intent sans 'type' chaîne")
    var t: String = intent["type"]
    match t:
        ADD_INGREDIENT:
            return _ok() if _is_id(intent.get("ingredient_id")) else _err("ingredient_id requis")
        REMOVE_INGREDIENT, REMOVE_ACTION:
            return _ok() if typeof(intent.get("index")) == TYPE_INT else _err("index entier requis")
        ADD_ACTION:
            return _ok() if _is_id(intent.get("action_id")) else _err("action_id requis")
        SET_READY:
            return _ok() if typeof(intent.get("ready")) == TYPE_BOOL else _err("ready booléen requis")
        PLAY_CARD:
            if not _is_id(intent.get("card_id")):
                return _err("card_id requis")
            if intent.has("target_player_id") and not _is_id(intent.get("target_player_id")):
                return _err("target_player_id invalide")
            return _ok()
        _:
            return _err("type d'intent inconnu: %s" % t)
```

- [ ] **Step 4 : Lancer, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_intents.gd -gexit`
Expected : PASS (6 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/intents.gd core/intents.gd.uid tests/test_intents.gd tests/test_intents.gd.uid
git commit -m "feat(core): Intents — constantes de type + validation de forme"
```

---

### Task 3 : fixture de contenu de match + `GameCore.start_match`

**Files:**
- Create: `tests/fixtures/match_content.gd`
- Create: `core/game_core.gd`
- Test: `tests/test_start_match.gd`

**Interfaces:**
- Consumes: `ContentDB`, `ContentLoader`, `ValidContent` (Plan 1), `Rng`, `GameState`, `PlayerState`, `MatchConfigRes`.
- Produces:
  - `MatchContent.db() -> ContentDB` — charge `ValidContent.make()` via `ContentLoader.load_from_dict` et renvoie le `db` (échoue le test si invalide).
  - `GameCore.start_match(db, config, seed, player_ids) -> GameState`. Construit l'état : `config` snapshot, `player_order = player_ids`, un `PlayerState` par id avec `budget_left = ingredient_budget`, deck de `deck_size` cartes tirées **avec remise** parmi `db.cards.keys()` triées (via `Rng`), puis pioche de `starting_hand_size` cartes (par l'avant du deck) dans la main. `phase = PLANNING`, `phase_time_left = planning_sec`, `event_timer_left = event_window_sec`, `rng_state` sauvegardé, `result = {}`.

- [ ] **Step 1 : Écrire la fixture `tests/fixtures/match_content.gd`**

```gdscript
class_name MatchContent
extends RefCounted

static func db() -> ContentDB:
    var res := ContentLoader.load_from_dict(ValidContent.make())
    assert(res.ok, "fixture de contenu invalide: %s" % str(res.errors))
    return res.db
```

- [ ] **Step 2 : Écrire le test qui échoue**

Fichier `tests/test_start_match.gd` :

```gdscript
extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _config() -> MatchConfigRes:
    return _db.match_config

func test_start_match_initial_state():
    var s := GameCore.start_match(_db, _config(), 123, ["p0", "p1"])
    assert_eq(s.phase, GameState.Phase.PLANNING)
    assert_eq(s.player_order, ["p0", "p1"])
    assert_eq(s.players.size(), 2)
    assert_almost_eq(s.phase_time_left, float(_config().phase_planning_sec), 0.001)
    var p0: PlayerState = s.players["p0"]
    assert_eq(p0.budget_left, _config().ingredient_budget)
    assert_eq(p0.hand.size(), _config().starting_hand_size)
    assert_eq(p0.deck.size(), _config().deck_size_max - _config().starting_hand_size)

func test_start_match_is_deterministic():
    var a := GameCore.start_match(_db, _config(), 777, ["p0", "p1"])
    var b := GameCore.start_match(_db, _config(), 777, ["p0", "p1"])
    assert_eq(a.players["p0"].hand, b.players["p0"].hand)
    assert_eq(a.players["p0"].deck, b.players["p0"].deck)

func test_start_match_different_seed_differs():
    var a := GameCore.start_match(_db, _config(), 1, ["p0", "p1"])
    var b := GameCore.start_match(_db, _config(), 2, ["p0", "p1"])
    # au moins une des deux mains diffère (extrêmement probable ; sinon deck)
    var same := a.players["p0"].hand == b.players["p0"].hand and a.players["p0"].deck == b.players["p0"].deck
    assert_false(same)
```

- [ ] **Step 3 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_start_match.gd -gexit`
Expected : FAIL — `MatchContent`/`GameCore` non définis.

- [ ] **Step 4 : Implémenter `core/game_core.gd` (avec `start_match` uniquement pour l'instant)**

```gdscript
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
```

- [ ] **Step 5 : Lancer, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_start_match.gd -gexit`
Expected : PASS (3 tests).

- [ ] **Step 6 : Commit**

```bash
git add tests/fixtures/match_content.gd tests/fixtures/match_content.gd.uid core/game_core.gd core/game_core.gd.uid tests/test_start_match.gd tests/test_start_match.gd.uid
git commit -m "feat(core): GameCore.start_match + fixture de contenu de match"
```

---

### Task 4 : `GameCore.apply_intent` — Intentions de planning

**Files:**
- Modify: `core/game_core.gd` (ajout de `apply_intent` + handlers de planning + helpers `_reject`/`_ok_events`)
- Test: `tests/test_apply_intent_planning.gd`

**Interfaces:**
- Consumes: `Intents`, `GameState`, `ContentDB`.
- Produces: `GameCore.apply_intent(db, state, player_id, intent) -> {"state","events"}`. Valide la forme (`Intents.validate_shape`), l'existence du joueur, puis dispatche par phase. En **PLANNING** gère `ADD_INGREDIENT` (id existe dans `db.ingredients` ; `ingredients.size() < config.ingredients_max` ; `cost <= budget_left`), `REMOVE_INGREDIENT` (index valide ; rembourse le coût), `ADD_ACTION` (id existe ; `timeline.size() < config.timeline_max`), `REMOVE_ACTION` (index valide), `SET_READY`. Toute violation → event `intent_rejected{reason}`, état inchangé. `PLAY_CARD` est géré à la Task 6.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_apply_intent_planning.gd` :

```gdscript
extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _fresh() -> GameState:
    return GameCore.start_match(_db, _db.match_config, 5, ["p0", "p1"])

func _events_of(res: Dictionary, type: String) -> Array:
    var out := []
    for e in res.events:
        if e.type == type:
            out.append(e)
    return out

func test_add_ingredient_deducts_budget():
    var s := _fresh()
    var before: int = s.players["p0"].budget_left
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    assert_eq(s.players["p0"].ingredients, ["tomate"])
    assert_eq(s.players["p0"].budget_left, before - _db.ingredients["tomate"].cost)
    assert_eq(_events_of(res, "ingredient_added").size(), 1)

func test_add_ingredient_unknown_rejected():
    var s := _fresh()
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "licorne"})
    assert_eq(s.players["p0"].ingredients.size(), 0)
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_add_ingredient_over_budget_rejected():
    var s := _fresh()
    s.players["p0"].budget_left = 0
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    assert_eq(s.players["p0"].ingredients.size(), 0)
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_remove_ingredient_refunds():
    var s := _fresh()
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    var mid: int = s.players["p0"].budget_left
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.REMOVE_INGREDIENT, "index": 0})
    assert_eq(s.players["p0"].ingredients.size(), 0)
    assert_eq(s.players["p0"].budget_left, mid + _db.ingredients["tomate"].cost)

func test_add_action_respects_limit():
    var s := _fresh()
    var maxn: int = int(s.config["timeline_max"])
    for i in range(maxn):
        GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_ACTION, "action_id": "cuire"})
    assert_eq(s.players["p0"].timeline.size(), maxn)
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_ACTION, "action_id": "cuire"})
    assert_eq(s.players["p0"].timeline.size(), maxn)
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_set_ready():
    var s := _fresh()
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.SET_READY, "ready": true})
    assert_true(s.players["p0"].ready)

func test_bad_shape_rejected():
    var s := _fresh()
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT})
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_unknown_player_rejected():
    var s := _fresh()
    var res := GameCore.apply_intent(_db, s, "p9", {"type": Intents.SET_READY, "ready": true})
    assert_eq(_events_of(res, "intent_rejected").size(), 1)
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_apply_intent_planning.gd -gexit`
Expected : FAIL — `apply_intent` non défini.

- [ ] **Step 3 : Ajouter à `core/game_core.gd`**

```gdscript
static func _result(state: GameState, events: Array) -> Dictionary:
    return {"state": state, "events": events}

static func _reject(state: GameState, reason: String) -> Dictionary:
    return _result(state, [{"type": "intent_rejected", "reason": reason}])

static func apply_intent(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var shape := Intents.validate_shape(intent)
    if not shape.ok:
        return _reject(state, "forme: " + shape.error)
    if not state.players.has(player_id):
        return _reject(state, "joueur inconnu: " + player_id)
    var t: String = intent["type"]

    if state.phase == GameState.Phase.PLANNING:
        match t:
            Intents.ADD_INGREDIENT:
                return _plan_add_ingredient(db, state, player_id, intent)
            Intents.REMOVE_INGREDIENT:
                return _plan_remove_ingredient(db, state, player_id, intent)
            Intents.ADD_ACTION:
                return _plan_add_action(db, state, player_id, intent)
            Intents.REMOVE_ACTION:
                return _plan_remove_action(db, state, player_id, intent)
            Intents.SET_READY:
                state.players[player_id].ready = bool(intent["ready"])
                var ev := [{"type": "ready_changed", "player": player_id, "ready": state.players[player_id].ready}]
                ev.append_array(PhaseMachine.maybe_end_planning(db, state))
                return _result(state, ev)
            Intents.PLAY_CARD:
                return _play_card(db, state, player_id, intent)
            _:
                return _reject(state, "intent non géré en planning: " + t)
    elif state.phase == GameState.Phase.EXECUTION:
        if t == Intents.PLAY_CARD:
            return _play_card(db, state, player_id, intent)
        return _reject(state, "intent non autorisé en exécution: " + t)
    return _reject(state, "aucun intent autorisé dans la phase courante")

static func _plan_add_ingredient(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var id: String = intent["ingredient_id"]
    if not db.ingredients.has(id):
        return _reject(state, "ingrédient inconnu: " + id)
    if p.ingredients.size() >= int(state.config["ingredients_max"]):
        return _reject(state, "limite d'ingrédients atteinte")
    var cost: int = db.ingredients[id].cost
    if cost > p.budget_left:
        return _reject(state, "budget insuffisant")
    p.ingredients.append(id)
    p.budget_left -= cost
    return _result(state, [{"type": "ingredient_added", "player": player_id, "ingredient_id": id}])

static func _plan_remove_ingredient(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var idx: int = intent["index"]
    if idx < 0 or idx >= p.ingredients.size():
        return _reject(state, "index d'ingrédient invalide")
    var id: String = p.ingredients[idx]
    p.ingredients.remove_at(idx)
    p.budget_left += db.ingredients[id].cost
    return _result(state, [{"type": "ingredient_removed", "player": player_id, "ingredient_id": id}])

static func _plan_add_action(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var id: String = intent["action_id"]
    if not db.actions.has(id):
        return _reject(state, "action inconnue: " + id)
    if p.timeline.size() >= int(state.config["timeline_max"]):
        return _reject(state, "limite d'actions atteinte")
    p.timeline.append(id)
    return _result(state, [{"type": "action_added", "player": player_id, "action_id": id}])

static func _plan_remove_action(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var idx: int = intent["index"]
    if idx < 0 or idx >= p.timeline.size():
        return _reject(state, "index d'action invalide")
    var id: String = p.timeline[idx]
    p.timeline.remove_at(idx)
    return _result(state, [{"type": "action_removed", "player": player_id, "action_id": id}])
```

> Note : `_play_card` (Task 6) et `PhaseMachine.maybe_end_planning` (Task 9) n'existent pas encore. Pour que ce fichier compile et que les tests de planning passent dès maintenant, ajoute des **stubs temporaires minimaux** dans `game_core.gd` et un `phase_machine.gd` réduit :
> - dans `game_core.gd` : `static func _play_card(db, state, player_id, intent) -> Dictionary: return _reject(state, "cartes non implémentées")`
> - crée `core/systems/phase_machine.gd` : `class_name PhaseMachine` / `extends RefCounted` / `static func maybe_end_planning(db, state) -> Array: return []`
> Ces stubs seront remplacés par les Tasks 6 et 9. Signale-les dans ton rapport (concern) pour que le reviewer sache qu'ils sont temporaires.

- [ ] **Step 4 : Lancer, vérifier le succès**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_apply_intent_planning.gd -gexit`
Expected : PASS (8 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/game_core.gd core/systems/phase_machine.gd core/systems/phase_machine.gd.uid tests/test_apply_intent_planning.gd tests/test_apply_intent_planning.gd.uid
git commit -m "feat(core): apply_intent — intentions de planning (+ stubs cartes/phase)"
```

---

### Task 5 : `EffectResolver`

**Files:**
- Create: `core/systems/effect_resolver.gd`
- Test: `tests/test_effect_resolver.gd`

**Interfaces:**
- Consumes: `Stats`, `PlayerState`.
- Produces: `EffectResolver.apply(player: PlayerState, effect: Dictionary) -> String`. Si `effect` a `"stats"` : `player.stat_modifiers = Stats.add(player.stat_modifiers, effect["stats"])`, retourne `"stats"`. Sinon si `"rule"` : `"delay_execution_seconds"` → `player.exec_delay_left += float(effect.get("value", 0))`, retourne `"delay"` ; toute autre règle → `"noop"`. Sinon `"noop"`.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_effect_resolver.gd` :

```gdscript
extends GutTest

func test_stats_effect_accumulates():
    var p := PlayerState.new()
    p.stat_modifiers = Stats.empty()
    assert_eq(EffectResolver.apply(p, {"stats": {"umami": 2}}), "stats")
    EffectResolver.apply(p, {"stats": {"umami": 3, "acide": 1}})
    assert_eq(int(p.stat_modifiers["umami"]), 5)
    assert_eq(int(p.stat_modifiers["acide"]), 1)

func test_delay_rule():
    var p := PlayerState.new()
    assert_eq(EffectResolver.apply(p, {"rule": "delay_execution_seconds", "value": 5}), "delay")
    assert_almost_eq(p.exec_delay_left, 5.0, 0.001)

func test_unknown_rule_is_noop():
    var p := PlayerState.new()
    p.stat_modifiers = Stats.empty()
    assert_eq(EffectResolver.apply(p, {"rule": "invoquer_dragon"}), "noop")
    assert_almost_eq(p.exec_delay_left, 0.0, 0.001)

func test_empty_effect_is_noop():
    var p := PlayerState.new()
    assert_eq(EffectResolver.apply(p, {}), "noop")
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_effect_resolver.gd -gexit`
Expected : FAIL — `EffectResolver` non défini.

- [ ] **Step 3 : Implémenter `core/systems/effect_resolver.gd`**

```gdscript
class_name EffectResolver
extends RefCounted

static func apply(player: PlayerState, effect: Dictionary) -> String:
    if effect.has("stats"):
        player.stat_modifiers = Stats.add(player.stat_modifiers, effect["stats"])
        return "stats"
    if effect.has("rule"):
        match String(effect["rule"]):
            "delay_execution_seconds":
                player.exec_delay_left += float(effect.get("value", 0))
                return "delay"
            _:
                return "noop"
    return "noop"
```

- [ ] **Step 4 : Lancer, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_effect_resolver.gd -gexit`
Expected : PASS (4 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/systems/effect_resolver.gd core/systems/effect_resolver.gd.uid tests/test_effect_resolver.gd tests/test_effect_resolver.gd.uid
git commit -m "feat(core): EffectResolver — stats + règle delay_execution_seconds"
```

---

### Task 6 : `CardResolver` + intention `PLAY_CARD`

**Files:**
- Create: `core/systems/card_resolver.gd`
- Modify: `core/game_core.gd` (remplace le stub `_play_card`)
- Test: `tests/test_card_resolver.gd`

**Interfaces:**
- Consumes: `CardRes`, `EffectResolver`, `PlayerState`, `GameState`, `ContentDB`.
- Produces:
  - `CardResolver.target_id(state, caster_id, card: CardRes) -> String` — `caster_id` si `card.target == Target.SELF`, sinon l'autre joueur de `player_order` (1v1). En dehors du 1v1, prend le premier autre id.
  - `CardResolver.is_playable(state, caster_id, card: CardRes) -> Dictionary` → `{"ok","error"}`. Une carte `GLOBAL` est jouable si `state.phase ∈ {PLANNING, EXECUTION}`. Une carte `CONTEXTUAL` n'est jouable qu'en `EXECUTION` ET si l'action courante de la CIBLE (`timeline[exec_index]` si `exec_index < timeline.size()`) égale `card.linked_action`.
  - `CardResolver.play(db, state, caster_id, card: CardRes) -> String` — applique `card.effect` à la cible via `EffectResolver.apply`, retourne l'id de la cible.
  - `GameCore._play_card(db, state, player_id, intent)` (remplace le stub) : la carte doit être dans `player.hand` ET dans `db.cards` ; `is_playable` doit passer ; sinon `intent_rejected`. Sinon : retire la carte de la main, `CardResolver.play`, émet `card_played{player, card_id, target}`.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_card_resolver.gd` :

```gdscript
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
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_card_resolver.gd -gexit`
Expected : FAIL — `CardResolver` non défini / stub `_play_card` rejette tout.

- [ ] **Step 3 : Implémenter `core/systems/card_resolver.gd`**

```gdscript
class_name CardResolver
extends RefCounted

static func target_id(state: GameState, caster_id: String, card: CardRes) -> String:
    if card.target == CardRes.Target.SELF:
        return caster_id
    for id in state.player_order:
        if id != caster_id:
            return id
    return caster_id

static func _current_action(player: PlayerState) -> String:
    if player.exec_index >= 0 and player.exec_index < player.timeline.size():
        return player.timeline[player.exec_index]
    return ""

static func is_playable(state: GameState, caster_id: String, card: CardRes) -> Dictionary:
    if card.type == CardRes.Type.GLOBAL:
        if state.phase == GameState.Phase.PLANNING or state.phase == GameState.Phase.EXECUTION:
            return {"ok": true, "error": ""}
        return {"ok": false, "error": "carte globale hors phase jouable"}
    # CONTEXTUAL
    if state.phase != GameState.Phase.EXECUTION:
        return {"ok": false, "error": "carte contextuelle jouable seulement en exécution"}
    var tid := target_id(state, caster_id, card)
    if _current_action(state.players[tid]) != card.linked_action:
        return {"ok": false, "error": "action liée non en cours sur la cible"}
    return {"ok": true, "error": ""}

static func play(db: ContentDB, state: GameState, caster_id: String, card: CardRes) -> String:
    var tid := target_id(state, caster_id, card)
    EffectResolver.apply(state.players[tid], card.effect)
    return tid
```

- [ ] **Step 4 : Remplacer le stub `_play_card` dans `core/game_core.gd`**

```gdscript
static func _play_card(db: ContentDB, state: GameState, player_id: String, intent: Dictionary) -> Dictionary:
    var p: PlayerState = state.players[player_id]
    var card_id: String = intent["card_id"]
    if not p.hand.has(card_id):
        return _reject(state, "carte absente de la main: " + card_id)
    if not db.cards.has(card_id):
        return _reject(state, "carte inconnue: " + card_id)
    var card: CardRes = db.cards[card_id]
    var playable := CardResolver.is_playable(state, player_id, card)
    if not playable.ok:
        return _reject(state, playable.error)
    p.hand.erase(card_id)
    var tid := CardResolver.play(db, state, player_id, card)
    return _result(state, [{"type": "card_played", "player": player_id, "card_id": card_id, "target": tid}])
```

- [ ] **Step 5 : Lancer, vérifier le succès**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_card_resolver.gd -gexit`
Expected : PASS (5 tests). Lance aussi `tests/test_apply_intent_planning.gd` pour confirmer l'absence de régression.

- [ ] **Step 6 : Commit**

```bash
git add core/systems/card_resolver.gd core/systems/card_resolver.gd.uid core/game_core.gd tests/test_card_resolver.gd tests/test_card_resolver.gd.uid
git commit -m "feat(core): CardResolver + intention play_card (globale/contextuelle)"
```

---

### Task 7 : `Timeline` — progression séquentielle des actions

**Files:**
- Create: `core/systems/timeline.gd`
- Test: `tests/test_timeline.gd`

**Interfaces:**
- Consumes: `PlayerState`, `ActionRes`, `ContentDB`.
- Produces:
  - `Timeline.advance(db, player: PlayerState, delta: float) -> Array` — avance l'exécution d'UN joueur de `delta` secondes ; retourne la liste (ordonnée) des ids d'actions **terminées pendant ce pas**. Consomme d'abord `exec_delay_left` (progression en pause tant qu'il reste du délai) ; puis fait avancer l'action courante (`timeline[exec_index]`, durée `base_duration_sec`) ; quand une action se termine, `exec_index += 1`, `exec_elapsed = 0`, et on continue avec le temps restant. Si `exec_index >= timeline.size()`, ne fait rien (joueur au repos).
  - `Timeline.advance_all(db, state: GameState, delta: float) -> Array` — appelle `advance` pour chaque joueur dans `state.player_order` ; pour chaque action terminée, émet `action_completed{player,action_id}` puis pioche **1** carte si `deck` non vide (`hand.append(deck.pop_front())`) et émet `card_drawn{player}` (sans id). Retourne le tableau d'events.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_timeline.gd` :

```gdscript
extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _player(timeline: Array) -> PlayerState:
    var p := PlayerState.new()
    p.timeline = timeline
    return p

func test_action_completes_after_its_duration():
    var p := _player(["assaisonner"])   # base_duration_sec = 15
    var done := Timeline.advance(_db, p, 10.0)
    assert_eq(done.size(), 0)
    assert_eq(p.exec_index, 0)
    done = Timeline.advance(_db, p, 10.0)
    assert_eq(done, ["assaisonner"])
    assert_eq(p.exec_index, 1)

func test_delay_pauses_progress():
    var p := _player(["assaisonner"])   # 15s
    p.exec_delay_left = 5.0
    var done := Timeline.advance(_db, p, 5.0)  # tout consommé par le délai
    assert_eq(done.size(), 0)
    assert_almost_eq(p.exec_delay_left, 0.0, 0.001)
    assert_almost_eq(p.exec_elapsed, 0.0, 0.001)

func test_multiple_actions_in_one_big_delta():
    var p := _player(["assaisonner", "mixer"])  # 15 + 20 = 35
    var done := Timeline.advance(_db, p, 40.0)
    assert_eq(done, ["assaisonner", "mixer"])
    assert_eq(p.exec_index, 2)

func test_idle_when_finished():
    var p := _player([])
    assert_eq(Timeline.advance(_db, p, 100.0).size(), 0)

func test_advance_all_emits_and_draws():
    var s := GameCore.start_match(_db, _db.match_config, 3, ["p0", "p1"])
    s.players["p0"].timeline = ["assaisonner"]
    s.players["p0"].deck = ["card_boost_umami"]
    var hand_before: int = s.players["p0"].hand.size()
    var events := Timeline.advance_all(_db, s, 20.0)
    var completed := events.filter(func(e): return e.type == "action_completed")
    var drawn := events.filter(func(e): return e.type == "card_drawn")
    assert_eq(completed.size(), 1)
    assert_eq(drawn.size(), 1)
    assert_false(drawn[0].has("card_id"))  # anti-triche : pas d'id dans l'event
    assert_eq(s.players["p0"].hand.size(), hand_before + 1)
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_timeline.gd -gexit`
Expected : FAIL — `Timeline` non défini.

- [ ] **Step 3 : Implémenter `core/systems/timeline.gd`**

```gdscript
class_name Timeline
extends RefCounted

static func advance(db: ContentDB, player: PlayerState, delta: float) -> Array:
    var completed: Array = []
    var remaining: float = delta
    # 1) consommer le délai en cours
    if player.exec_delay_left > 0.0:
        var d: float = min(player.exec_delay_left, remaining)
        player.exec_delay_left -= d
        remaining -= d
    # 2) faire avancer les actions
    while remaining > 0.0 and player.exec_index < player.timeline.size():
        var action: ActionRes = db.actions[player.timeline[player.exec_index]]
        var dur: float = float(action.base_duration_sec)
        var need: float = dur - player.exec_elapsed
        var step: float = min(need, remaining)
        player.exec_elapsed += step
        remaining -= step
        if player.exec_elapsed >= dur:
            completed.append(player.timeline[player.exec_index])
            player.exec_index += 1
            player.exec_elapsed = 0.0
    return completed

static func advance_all(db: ContentDB, state: GameState, delta: float) -> Array:
    var events: Array = []
    for id in state.player_order:
        var p: PlayerState = state.players[id]
        for action_id in advance(db, p, delta):
            events.append({"type": "action_completed", "player": id, "action_id": action_id})
            if not p.deck.is_empty():
                p.hand.append(p.deck.pop_front())
                events.append({"type": "card_drawn", "player": id})
    return events
```

- [ ] **Step 4 : Lancer, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_timeline.gd -gexit`
Expected : PASS (5 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/systems/timeline.gd core/systems/timeline.gd.uid tests/test_timeline.gd tests/test_timeline.gd.uid
git commit -m "feat(core): Timeline — exécution séquentielle + pioche sur transition"
```

---

### Task 8 : `EventScheduler` — événements aléatoires windowés

**Files:**
- Create: `core/systems/event_scheduler.gd`
- Test: `tests/test_event_scheduler.gd`

**Interfaces:**
- Consumes: `Rng`, `EffectResolver`, `EventRes`, `GameState`, `ContentDB`.
- Produces: `EventScheduler.tick(db, state, delta) -> Array`. N'agit qu'en `PLANNING`/`EXECUTION`. Décrémente `state.event_timer_left -= delta` ; tant qu'il est `<= 0`, tire (via `Rng` restauré de `state.rng_state`) un événement parmi ceux dont le `trigger_window` correspond à la phase courante (clés `db.events` **triées**), l'applique via `EffectResolver.apply` à **tous** les joueurs (ordre `player_order`), émet `event_fired{event_id,description}`, puis `event_timer_left += event_window_sec`. S'il n'existe aucun événement pour la fenêtre courante, réarme quand même le timer (pas de tir). Resauvegarde `rng_state`. Map phase→chaîne : PLANNING→"planning", EXECUTION→"execution".

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_event_scheduler.gd` :

```gdscript
extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _exec_state() -> GameState:
    var s := GameCore.start_match(_db, _db.match_config, 9, ["p0", "p1"])
    s.phase = GameState.Phase.EXECUTION
    s.players["p0"].stat_modifiers = Stats.empty()
    s.players["p1"].stat_modifiers = Stats.empty()
    return s

func test_no_fire_before_window_elapses():
    var s := _exec_state()
    s.event_timer_left = 100.0
    var events := EventScheduler.tick(_db, s, 10.0)
    assert_eq(events.size(), 0)
    assert_almost_eq(s.event_timer_left, 90.0, 0.001)

func test_fires_when_window_elapses():
    var s := _exec_state()
    s.event_timer_left = 5.0
    # le seul event fixture ("coupure") a trigger_window=execution, rule delay 5s
    var events := EventScheduler.tick(_db, s, 5.0)
    var fired := events.filter(func(e): return e.type == "event_fired")
    assert_eq(fired.size(), 1)
    assert_eq(fired[0].event_id, "coupure")
    assert_almost_eq(s.players["p0"].exec_delay_left, 5.0, 0.001)
    assert_almost_eq(s.players["p1"].exec_delay_left, 5.0, 0.001)
    assert_true(s.event_timer_left > 0.0)  # réarmé

func test_deterministic_same_seed():
    var a := _exec_state(); a.event_timer_left = 1.0
    var b := _exec_state(); b.event_timer_left = 1.0
    var ea := EventScheduler.tick(_db, a, 1.0)
    var eb := EventScheduler.tick(_db, b, 1.0)
    assert_eq(ea.size(), eb.size())
    assert_eq(a.players["p0"].exec_delay_left, b.players["p0"].exec_delay_left)

func test_no_events_for_phase_still_rearms():
    var s := _exec_state()
    s.phase = GameState.Phase.PLANNING  # aucun event fixture en planning
    s.event_timer_left = 1.0
    var events := EventScheduler.tick(_db, s, 1.0)
    assert_eq(events.filter(func(e): return e.type == "event_fired").size(), 0)
    assert_true(s.event_timer_left > 0.0)
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_event_scheduler.gd -gexit`
Expected : FAIL — `EventScheduler` non défini.

- [ ] **Step 3 : Implémenter `core/systems/event_scheduler.gd`**

```gdscript
class_name EventScheduler
extends RefCounted

static func _phase_window(phase: int) -> String:
    match phase:
        GameState.Phase.PLANNING: return "planning"
        GameState.Phase.EXECUTION: return "execution"
        GameState.Phase.JUDGMENT: return "judgment"
        _: return ""

static func tick(db: ContentDB, state: GameState, delta: float) -> Array:
    var events: Array = []
    if state.phase != GameState.Phase.PLANNING and state.phase != GameState.Phase.EXECUTION:
        return events
    var window := _phase_window(state.phase)
    var candidates: Array = []
    var ids: Array = db.events.keys()
    ids.sort()
    for id in ids:
        if db.events[id].trigger_window == window:
            candidates.append(id)

    var rng := Rng.new(0)
    rng.set_state(state.rng_state)
    state.event_timer_left -= delta
    while state.event_timer_left <= 0.0:
        if not candidates.is_empty():
            var pick: String = candidates[rng.randi_range(0, candidates.size() - 1)]
            var ev: EventRes = db.events[pick]
            for pid in state.player_order:
                EffectResolver.apply(state.players[pid], ev.effect)
            events.append({"type": "event_fired", "event_id": pick, "description": ev.display_name})
        state.event_timer_left += float(state.config["event_window_sec"])
    state.rng_state = rng.get_state()
    return events
```

- [ ] **Step 4 : Lancer, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_event_scheduler.gd -gexit`
Expected : PASS (4 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/systems/event_scheduler.gd core/systems/event_scheduler.gd.uid tests/test_event_scheduler.gd tests/test_event_scheduler.gd.uid
git commit -m "feat(core): EventScheduler — événements windowés seedés"
```

---

### Task 9 : `Dish` + `PhaseMachine` (transitions + jugement)

**Files:**
- Create: `core/systems/dish.gd`
- Modify: `core/systems/phase_machine.gd` (remplace le stub par la vraie machine)
- Test: `tests/test_phase_machine.gd`

**Interfaces:**
- Consumes: `Stats`, `StatEngine`, `JudgmentEngine`, `Dish`, `GameState`, `PlayerState`, `ContentDB`.
- Produces:
  - `Dish.compute(db, player) -> Dictionary` (voir Modèle de données partagé) : `applied_actions = player.timeline` tronqué à `[0, exec_index)`.
  - `PhaseMachine.maybe_end_planning(db, state) -> Array` — si `phase == PLANNING` et (`phase_time_left <= 0` OU tous les joueurs `ready`), appelle `enter_execution` et retourne `[phase_changed{from:PLANNING,to:EXECUTION}]` ; sinon `[]`.
  - `PhaseMachine.enter_execution(state)` — pour chaque joueur : `exec_index=0, exec_elapsed=0, exec_delay_left=0` ; `phase=EXECUTION`, `phase_time_left=execution_sec`, `event_timer_left=event_window_sec`.
  - `PhaseMachine.enter_judgment(db, state)` — calcule le plat de chaque joueur (`Dish.compute`), classe via `JudgmentEngine.judge` (dish du 1er de `player_order` = A, 2e = B) ; remplit `state.result = {"scores": {id: score}, "winner": id ou ""}` ; `phase=JUDGMENT`, `phase_time_left=judgment_sec`. Retourne `[phase_changed{...}, judged{result}]`.
  - `PhaseMachine.advance_timers(db, state, delta) -> Array` — PLANNING : `phase_time_left -= delta` puis `maybe_end_planning`. EXECUTION : `phase_time_left -= delta` ; si `<= 0` → `enter_judgment`. JUDGMENT : `phase_time_left -= delta` ; si `<= 0` → `phase=FINISHED` + `[phase_changed{...}, match_finished{result}]`. FINISHED : `[]`.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_phase_machine.gd` :

```gdscript
extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _fresh() -> GameState:
    return GameCore.start_match(_db, _db.match_config, 5, ["p0", "p1"])

func _types(events: Array) -> Array:
    return events.map(func(e): return e.type)

func test_dish_compute_uses_applied_actions_only():
    var s := _fresh()
    var p: PlayerState = s.players["p0"]
    p.ingredients = ["boeuf"]          # umami 5, gras 3
    p.timeline = ["cuire", "mixer"]
    p.exec_index = 1                    # seule "cuire" appliquée (umami +2, acide -1)
    p.stat_modifiers = Stats.empty()
    var dish := Dish.compute(_db, p)
    assert_eq(int(dish["umami"]), 7)
    assert_eq(int(dish["acide"]), -1)   # (pas de mixer)

func test_planning_ends_when_both_ready():
    var s := _fresh()
    s.players["p0"].ready = true
    s.players["p1"].ready = true
    var ev := PhaseMachine.maybe_end_planning(_db, s)
    assert_eq(s.phase, GameState.Phase.EXECUTION)
    assert_true(_types(ev).has("phase_changed"))

func test_planning_stays_if_only_one_ready():
    var s := _fresh()
    s.players["p0"].ready = true
    PhaseMachine.maybe_end_planning(_db, s)
    assert_eq(s.phase, GameState.Phase.PLANNING)

func test_planning_ends_on_timer():
    var s := _fresh()
    s.phase_time_left = 1.0
    var ev := PhaseMachine.advance_timers(_db, s, 2.0)
    assert_eq(s.phase, GameState.Phase.EXECUTION)
    assert_true(_types(ev).has("phase_changed"))

func test_execution_timer_leads_to_judgment_then_finished():
    var s := _fresh()
    PhaseMachine.enter_execution(s)
    s.players["p0"].ingredients = ["boeuf"]
    s.players["p1"].ingredients = ["citron"]
    s.phase_time_left = 1.0
    var ev1 := PhaseMachine.advance_timers(_db, s, 2.0)
    assert_eq(s.phase, GameState.Phase.JUDGMENT)
    assert_true(_types(ev1).has("judged"))
    assert_true(s.result.has("winner"))
    assert_eq(s.result["winner"], "p0")   # boeuf (umami/gras) bat citron
    s.phase_time_left = 1.0
    var ev2 := PhaseMachine.advance_timers(_db, s, 2.0)
    assert_eq(s.phase, GameState.Phase.FINISHED)
    assert_true(_types(ev2).has("match_finished"))
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_phase_machine.gd -gexit`
Expected : FAIL — `Dish` non défini / `PhaseMachine.maybe_end_planning` (stub) ne transitionne pas.

- [ ] **Step 3 : Implémenter `core/systems/dish.gd`**

```gdscript
class_name Dish
extends RefCounted

static func compute(db: ContentDB, player: PlayerState) -> Dictionary:
    var ings: Array = []
    for id in player.ingredients:
        if db.ingredients.has(id):
            ings.append(db.ingredients[id])
    var applied: Array = []
    var upto: int = clampi(player.exec_index, 0, player.timeline.size())
    for i in range(upto):
        var aid: String = player.timeline[i]
        if db.actions.has(aid):
            applied.append(db.actions[aid])
    var base := StatEngine.compute_dish(ings, applied)
    var combined := Stats.add(base, player.stat_modifiers)
    return Stats.clamp_stats(combined, StatEngine.STAT_MIN, StatEngine.STAT_MAX)
```

- [ ] **Step 4 : Remplacer `core/systems/phase_machine.gd` par la vraie machine**

```gdscript
class_name PhaseMachine
extends RefCounted

static func _all_ready(state: GameState) -> bool:
    for id in state.player_order:
        if not state.players[id].ready:
            return false
    return true

static func maybe_end_planning(db: ContentDB, state: GameState) -> Array:
    if state.phase != GameState.Phase.PLANNING:
        return []
    if state.phase_time_left <= 0.0 or _all_ready(state):
        enter_execution(state)
        return [{"type": "phase_changed", "from": GameState.Phase.PLANNING, "to": GameState.Phase.EXECUTION}]
    return []

static func enter_execution(state: GameState) -> void:
    for id in state.player_order:
        var p: PlayerState = state.players[id]
        p.exec_index = 0
        p.exec_elapsed = 0.0
        p.exec_delay_left = 0.0
    state.phase = GameState.Phase.EXECUTION
    state.phase_time_left = float(state.config["execution_sec"])
    state.event_timer_left = float(state.config["event_window_sec"])

static func enter_judgment(db: ContentDB, state: GameState) -> Array:
    var ids: Array = state.player_order
    var dishes: Dictionary = {}
    for id in ids:
        dishes[id] = Dish.compute(db, state.players[id])
    var criteria: Array = db.criteria.values()
    var scores: Dictionary = {}
    var winner := ""
    if ids.size() == 2:
        var verdict := JudgmentEngine.judge(dishes[ids[0]], dishes[ids[1]], criteria)
        scores[ids[0]] = verdict["score_a"]
        scores[ids[1]] = verdict["score_b"]
        if verdict["winner"] == "a":
            winner = ids[0]
        elif verdict["winner"] == "b":
            winner = ids[1]
    else:
        for id in ids:
            scores[id] = JudgmentEngine.score_dish(dishes[id], criteria)
    state.result = {"scores": scores, "winner": winner}
    var from_phase := state.phase
    state.phase = GameState.Phase.JUDGMENT
    state.phase_time_left = float(state.config["judgment_sec"])
    return [
        {"type": "phase_changed", "from": from_phase, "to": GameState.Phase.JUDGMENT},
        {"type": "judged", "result": state.result},
    ]

static func advance_timers(db: ContentDB, state: GameState, delta: float) -> Array:
    match state.phase:
        GameState.Phase.PLANNING:
            state.phase_time_left -= delta
            return maybe_end_planning(db, state)
        GameState.Phase.EXECUTION:
            state.phase_time_left -= delta
            if state.phase_time_left <= 0.0:
                return enter_judgment(db, state)
            return []
        GameState.Phase.JUDGMENT:
            state.phase_time_left -= delta
            if state.phase_time_left <= 0.0:
                state.phase = GameState.Phase.FINISHED
                return [
                    {"type": "phase_changed", "from": GameState.Phase.JUDGMENT, "to": GameState.Phase.FINISHED},
                    {"type": "match_finished", "result": state.result},
                ]
            return []
        _:
            return []
```

- [ ] **Step 5 : Lancer, vérifier le succès**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_phase_machine.gd -gexit`
Expected : PASS (5 tests). Relance `tests/test_apply_intent_planning.gd` (le stub `maybe_end_planning` est remplacé — `set_ready` peut maintenant transitionner ; les tests de planning n'y touchent pas car un seul joueur `ready`).

- [ ] **Step 6 : Commit**

```bash
git add core/systems/dish.gd core/systems/dish.gd.uid core/systems/phase_machine.gd tests/test_phase_machine.gd tests/test_phase_machine.gd.uid
git commit -m "feat(core): Dish + PhaseMachine (transitions + jugement)"
```

---

### Task 10 : `GameCore.tick` (câblage complet) + `GameCore.get_view`

**Files:**
- Modify: `core/game_core.gd` (ajout de `tick` et `get_view`)
- Test: `tests/test_game_core_tick_view.gd`

**Interfaces:**
- Consumes: `Timeline`, `EventScheduler`, `PhaseMachine`, `Dish`, `GameState`, `ContentDB`.
- Produces:
  - `GameCore.tick(db, state, delta) -> {"state","events"}` : si `FINISHED`, aucun event. En `EXECUTION` : `events += Timeline.advance_all` puis `events += EventScheduler.tick`. En `PLANNING` : `events += EventScheduler.tick`. Dans tous les cas : `events += PhaseMachine.advance_timers`. (Ordre : progression/événements d'abord, puis timers/transitions.)
  - `GameCore.get_view(db, state, viewer_id) -> Dictionary` : `{"phase","phase_time_left","result", "you": <vue self>, "opponents": {id: <vue publique>}}`. Vue self : `budget_left, ingredients, timeline, hand (ids), deck_count, ready, exec_index, exec_elapsed, dish` (= `Dish.compute`). Vue publique adverse : `ingredients, timeline, ready, exec_index, dish, hand_count, deck_count` — **jamais** `hand` (ids) ni `deck` (contenu). Prend `db` en premier argument (nécessaire à `Dish.compute`).

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_game_core_tick_view.gd` :

```gdscript
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
    var completed := res.events.filter(func(e): return e.type == "action_completed")
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
    var view := GameCore.get_view(s, "p0")
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
    var view := GameCore.get_view(s, "p0")
    assert_eq(int(view.you.dish["umami"]), 5)
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_core_tick_view.gd -gexit`
Expected : FAIL — `tick`/`get_view` non définis.

- [ ] **Step 3 : Ajouter à `core/game_core.gd`**

```gdscript
static func tick(db: ContentDB, state: GameState, delta: float) -> Dictionary:
    if state.phase == GameState.Phase.FINISHED:
        return _result(state, [])
    var events: Array = []
    if state.phase == GameState.Phase.EXECUTION:
        events.append_array(Timeline.advance_all(db, state, delta))
        events.append_array(EventScheduler.tick(db, state, delta))
    elif state.phase == GameState.Phase.PLANNING:
        events.append_array(EventScheduler.tick(db, state, delta))
    events.append_array(PhaseMachine.advance_timers(db, state, delta))
    return _result(state, events)

static func _self_view(db: ContentDB, p: PlayerState) -> Dictionary:
    return {
        "budget_left": p.budget_left,
        "ingredients": p.ingredients.duplicate(),
        "timeline": p.timeline.duplicate(),
        "hand": p.hand.duplicate(),
        "deck_count": p.deck.size(),
        "ready": p.ready,
        "exec_index": p.exec_index,
        "exec_elapsed": p.exec_elapsed,
        "dish": Dish.compute(db, p),
    }

static func _public_view(db: ContentDB, p: PlayerState) -> Dictionary:
    return {
        "ingredients": p.ingredients.duplicate(),
        "timeline": p.timeline.duplicate(),
        "ready": p.ready,
        "exec_index": p.exec_index,
        "dish": Dish.compute(db, p),
        "hand_count": p.hand.size(),
        "deck_count": p.deck.size(),
    }

static func get_view(db: ContentDB, state: GameState, viewer_id: String) -> Dictionary:
    var opponents: Dictionary = {}
    for id in state.player_order:
        if id != viewer_id:
            opponents[id] = _public_view(db, state.players[id])
    return {
        "phase": state.phase,
        "phase_time_left": state.phase_time_left,
        "result": state.result.duplicate(),
        "you": _self_view(db, state.players[viewer_id]),
        "opponents": opponents,
    }
```

> Note : `get_view` prend `db` en premier argument (nécessaire à `Dish.compute`) ; les tests l'appellent en `GameCore.get_view(_db, s, "p0")`.

- [ ] **Step 4 : Lancer, vérifier le succès**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_core_tick_view.gd -gexit`
Expected : PASS (4 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/game_core.gd tests/test_game_core_tick_view.gd tests/test_game_core_tick_view.gd.uid
git commit -m "feat(core): GameCore.tick (câblage complet) + get_view filtré (anti-triche)"
```

---

### Task 11 : Intégration — un match déterministe de bout en bout

**Files:**
- Test: `tests/test_integration_match.gd`

**Interfaces:**
- Consumes: tout `GameCore` + la fixture `MatchContent`.
- Produces: la preuve du livrable du Plan 2 — un match complet joué par un script d'Intentions + un seed produit un **résultat déterministe**, et rejouer la même séquence donne le même état.

- [ ] **Step 1 : Écrire le test d'intégration**

Fichier `tests/test_integration_match.gd` :

```gdscript
extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

# Joue un match scripté et renvoie le GameState final.
func _play(seed: int) -> GameState:
    var s := GameCore.start_match(_db, _db.match_config, seed, ["p0", "p1"])
    # --- PLANNING : chaque joueur pose des ingrédients + actions, puis se déclare prêt ---
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "boeuf"})
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_ACTION, "action_id": "cuire"})
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_ACTION, "action_id": "assaisonner"})
    GameCore.apply_intent(_db, s, "p1", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "citron"})
    GameCore.apply_intent(_db, s, "p1", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "sucre"})
    GameCore.apply_intent(_db, s, "p1", {"type": Intents.ADD_ACTION, "action_id": "mixer"})
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.SET_READY, "ready": true})
    GameCore.apply_intent(_db, s, "p1", {"type": Intents.SET_READY, "ready": true})
    assert_eq(s.phase, GameState.Phase.EXECUTION, "les deux prêts → exécution")
    # --- EXECUTION + JUDGMENT : on tick jusqu'à la fin du match ---
    var guard := 0
    while s.phase != GameState.Phase.FINISHED and guard < 100000:
        GameCore.tick(_db, s, 1.0)
        guard += 1
    assert_ne(s.phase, GameState.Phase.EXECUTION, "le match doit se terminer")
    return s

func test_full_match_produces_winner():
    var s := _play(2024)
    assert_eq(s.phase, GameState.Phase.FINISHED)
    assert_true(s.result.has("winner"))
    # p0 (boeuf/tomate, cuit+assaisonné → umami/gras) doit battre p1 (citron/sucre, mixé)
    assert_eq(s.result["winner"], "p0",
        "scores=%s" % str(s.result["scores"]))

func test_match_is_deterministic():
    var a := _play(2024)
    var b := _play(2024)
    assert_eq(a.to_dict(), b.to_dict(), "même seed + même script → même état final")

func test_view_never_leaks_opponent_hand_during_match():
    var s := GameCore.start_match(_db, _db.match_config, 7, ["p0", "p1"])
    var view := GameCore.get_view(_db, s, "p0")
    assert_false(view.opponents["p1"].has("hand"))
```

- [ ] **Step 2 : Lancer, vérifier le succès**

Run : `godot --headless --import` puis `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_integration_match.gd -gexit`
Expected : PASS (3 tests).

- [ ] **Step 3 : Lancer TOUTE la suite (non-régression Plan 1 + Plan 2)**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected : toutes les suites passent, 0 échec.

- [ ] **Step 4 : Commit**

```bash
git add tests/test_integration_match.gd tests/test_integration_match.gd.uid
git commit -m "test(core): match déterministe de bout en bout (intents + tick + jugement)"
```

---

## Self-Review (effectuée)

**Couverture spec (§3 — cœur de partie) :**
- `GameState`/`PlayerState` sérialisables → Task 1 ✅
- Intentions sérialisables + validation de forme → Task 2 ✅
- `start_match` (budget, deck, main, seed) → Task 3 ✅
- `apply_intent` (mutation unique de l'état, rejet d'intent invalide) → Tasks 4, 6 ✅
- `tick` (seul l'hôte tick, avance timers/actions/événements) → Tasks 8, 9, 10 ✅
- `get_view` (filtrage anti-triche de la main adverse) → Task 10 ✅
- `PhaseMachine` planning/exécution/jugement → Task 9 ✅
- `Timeline`, `StatEngine`(Plan 1), `CardResolver`, `EventScheduler`, `JudgmentEngine`(Plan 1) → Tasks 5-9 ✅
- RNG seedé unique côté autorité, itération triée pour le déterminisme → Global Constraints + Tasks 3, 8 ✅
- Décisions verrouillées (exécution séquentielle, timer-ou-prêt, cartes incluses, originalité reportée) → Global Constraints ✅

**Scan placeholders :** aucun TODO/TBD ; chaque étape de code est complète. Les stubs de la Task 4 (`_play_card`, `maybe_end_planning`) sont **explicitement temporaires**, remplacés aux Tasks 6 et 9, et signalés comme tels (ce n'est pas un placeholder de plan mais une séquence d'implémentation incrémentale d'un même fichier).

**Cohérence des types :** les noms du Modèle de données partagé (`GameState.Phase`, champs `PlayerState`/`GameState`, `Intents.*`, formes d'events, `GameCore.start_match/apply_intent/tick/get_view`, `Dish.compute`, signatures des systèmes) sont identiques entre la section de référence, les blocs `Interfaces`, le code et les tests. `get_view(db, state, viewer_id)` prend `db` en premier argument partout (référence, Task 10, tests) car `Dish.compute` requiert le `ContentDB`.

**Réutilisation Plan 1 :** `Stats`, `StatEngine`, `JudgmentEngine`, Resources, `ContentDB`, `ContentLoader`, `ValidContent`, `Rng` sont consommés sans modification.

---

## Suite

Après validation/implémentation du Plan 2 :
- **Plan 3** — Réseau (relais WebSocket, `NetSession`/`ITransport`, `protocol` sérialisant Intentions/Snapshots via `GameState.to_dict`/`get_view`, `reconciler`, test d'intégration hôte/invité en transport mémoire).
- **Plan 4** — Présentation (scènes Godot, UI, input → Intentions, view models depuis `get_view`, optimistic UI).
