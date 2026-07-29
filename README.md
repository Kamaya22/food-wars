# Food Wars

Jeu de duel culinaire 1v1 en ligne, sur Godot 4.5 / GDScript. Deux joueurs composent
un plat — ingrédients, actions sur une timeline, cartes — puis un moteur de jugement
départage les assiettes selon des critères versionnés.

> **État du projet.** Le cœur de jeu et la couche réseau sont terminés et testés
> (129 tests Godot + 9 tests Node). **Il n'y a pas encore de couche de présentation** :
> le dépôt ne contient aucune scène (`.tscn`) et le jeu ne se joue pas encore à la main.
> Une partie complète se déroule aujourd'hui via un harnais headless scripté
> (`scripts/net_smoke.gd`) ou par les tests d'intégration.

## Architecture

Quatre couches, dépendances strictement descendantes. Le principe non négociable :
*la logique de jeu ne connaît ni le rendu, ni le réseau.*

| Couche | Dossier | Rôle |
|---|---|---|
| Présentation | — | *pas encore implémentée* |
| Réseau / session | `net/` | Route les intentions vers l'hôte, diffuse les snapshots filtrés |
| Cœur de logique | `core/` | Règles, phases, résolution, jugement, RNG seedé — pur, headless |
| Contenu | `content/` | YAML versionné → JSON compilé → Resources Godot typées |

Conséquences concrètes de ce découpage :

- **Le cœur est pur** (`RefCounted` uniquement, aucun `Node`, aucun `get_tree()`), donc
  déplaçable tel quel dans un Godot headless côté serveur.
- **Autorité chez l'hôte.** L'invité envoie des intentions et applique des snapshots ;
  il ne décide de rien. Le filtrage anti-triche vit dans `get_view` — la main de
  l'adversaire ne quitte jamais la machine de l'hôte.
- **Le transport est abstrait** (`net/i_transport.gd`). `InMemoryTransport` sert aux
  tests déterministes, `WebSocketTransport` parle au vrai relais. Le relais Node ne
  connaît aucune règle : il apparie deux sockets et transfère des messages opaques.

## Arborescence

```
core/          cœur de jeu pur (game_core, game_state, phases, systems/)
  systems/     timeline, résolution de cartes/effets, jugement, stats, événements
net/           protocol, transport (in-memory + WebSocket), session, reconciler
content/       loader + resources typées ; sources YAML dans content/source/
relay/         relais WebSocket Node (aucune logique de jeu) + ses tests
tests/         27 suites GUT
scripts/       build_content.py (compilation du contenu), net_smoke.gd (E2E)
docs/          specs d'architecture, plans d'implémentation, checklist E2E
```

## Démarrage

### Prérequis

- **Godot 4.5**, binaire `godot` accessible sur le PATH
- **Node ≥ 18** pour le relais
- *(optionnel)* **Python 3** + PyYAML pour compiler le contenu YAML

### Installation

GUT, le framework de test, n'est pas versionné — une étape une fois après le clone :

```bash
git clone --depth 1 https://github.com/bitwes/Gut.git /tmp/gut
mkdir -p addons && cp -r /tmp/gut/addons/gut addons/gut
```

C'est tout ce qu'il faut pour lancer la suite : les tests et le harnais réseau
construisent leur contenu depuis une fixture (`tests/fixtures/`), pas depuis les YAML.

Compiler le contenu réel est **optionnel** — cela active `test_content_compiled.gd`,
qui valide les YAML de `content/source/` et qui reste en *pending* sans ce fichier :

```bash
pip install pyyaml
python scripts/build_content.py     # -> content/compiled/content.json
```

### Tests

```bash
# Suite Godot (129 tests) — l'import doit précéder GUT après tout ajout de class_name
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# Suite du relais (9 tests) — aucun npm install requis, relay.js est pur
node --test relay/relay.test.js
```

GUT émet des avertissements `NavigationServer*Manager` en headless : ils sont
inoffensifs, seul le compte « Passing Tests » fait foi.

### Jouer une partie en réseau réel

```bash
# Terminal 1 — le relais
cd relay && npm install && npm start      # ws://localhost:8080

# Terminal 2 — l'hôte, qui affiche un code de room
godot --headless -s scripts/net_smoke.gd -- host ws://localhost:8080

# Terminal 3 — l'invité, avec ce code
godot --headless -s scripts/net_smoke.gd -- join ws://localhost:8080 <CODE>
```

Les deux processus jouent un match scripté de bout en bout et impriment le résultat.
La procédure complète, y compris les scénarios de déconnexion, est dans
[`docs/MANUAL-E2E.md`](docs/MANUAL-E2E.md).

## Protocole réseau

Le relais attribue les rôles `host` / `guest`, génère la seed partagée et route les
messages sans les inspecter.

- **Contrôle** (JSON avec `t`) : `create` → `created{code}` ; `join{code}` →
  `room_ready{role,seed,opponent_id}` aux deux, ou `error{reason}`.
- **Reconnexion** : fenêtre de 30 s. `peer_left` (pause) → `peer_rejoined` (resync) ou
  `room_closed` à l'expiration. `host_left` est terminal.
- **Jeu** : tout message portant un champ `kind` est transféré verbatim au pair.

Côté Godot, `peer_disconnected` est **terminal** ; la pause transitoire passe par les
signaux `peer_suspended` / `peer_resumed`.

## Documentation

- [`docs/superpowers/specs/`](docs/superpowers/specs/) — décisions d'architecture et
  design réseau, avec leurs justifications
- [`docs/superpowers/plans/`](docs/superpowers/plans/) — plans d'implémentation
  détaillés, tâche par tâche
- [`docs/food_wars_requirements.yaml`](docs/food_wars_requirements.yaml) — document de
  game design
- [`relay/README.md`](relay/README.md) — le relais en détail
