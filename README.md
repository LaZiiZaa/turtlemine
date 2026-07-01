# turtlemine — Système de minage pour CC: Tweaked

Tortues de minage autonomes (tunnel / excavatrice) + tablette de suivi et de
contrôle à distance, pour [CC: Tweaked](https://tweaked.cc/) (Minecraft).

## Composants

| Fichier | Appareil | Rôle |
|---|---|---|
| `mine.lua` | Tortue | Programme de minage : modes tunnel/excavatrice, filtrage des minerais, dépôt auto (coffres à la base), gestion du carburant, reprise après coupure. |
| `remote.lua` | Tablette | Pocket Computer / ordinateur de contrôle : suit toutes les tortues en temps réel, vue détail, commandes (pause / reprise / retour base / arrêt / restart / inventaire). Affichage **responsive**, diffusion sur un **moniteur** si présent. |
| `minenet.lua` | Les deux | Module réseau partagé (protocole rednet commun). |
| `startup.lua` | Tous | Démarrage commun : reprend le minage (tortue avec tâche en cours), sinon ouvre `menu`. |
| `install_tortue.lua` | Tortue | Installe `minenet` + `mine` + `startup` (reprise). |
| `install_tablette.lua` | Pocket | Installe `minenet` + `remote` + `startup`. |
| `install_ordinateur.lua` | Ordinateur | Installe `minenet` + `remote` + `startup` (affichage sur moniteur si présent). |
| `menu.lua` | Tous | Gestionnaire interactif : mettre à jour, réinstaller, lancer, tout supprimer, redémarrer. |

## Installation

Sur **chaque** appareil, avec HTTP activé, lance le script dédié.

**Tortue :**
```
wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/install_tortue.lua install_tortue.lua
install_tortue
```

**Tablette (Pocket Computer) :**
```
wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/install_tablette.lua install_tablette.lua
install_tablette
```

**Ordinateur de contrôle :**
```
wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/install_ordinateur.lua install_ordinateur.lua
install_ordinateur
```

Chaque script télécharge le bon set de fichiers (dont le bon `startup` et `menu.lua`) puis redémarre l'appareil.

## Mise à jour & gestion (`menu.lua`)

Pas besoin de tout supprimer pour mettre à jour : les fichiers sont **écrasés**
en place (les données comme `.mine_state` sont conservées). Le gestionnaire
`menu` (installé automatiquement) propose un menu :

```
menu
```

- **Mettre à jour** — re-télécharge et écrase, garde les données.
- **Réinstallation propre** — supprime puis re-télécharge.
- **Lancer** — démarre `mine` / `remote`.
- **Tout supprimer** — efface les fichiers installés.
- **Redémarrer / Quitter**.

Navigable au clavier (flèches + Entrée, ou le chiffre) **et** à la souris/tactile.

## Matériel

- **Tortue de minage** (Mining Turtle) avec une pioche + un **modem sans fil**.
- Pour le dépôt (mode `home`) : un **coffre de vidage** placé **derrière** la tortue
  et un **coffre de carburant** à sa **gauche** (voir « Dépôt à la base » plus bas).
- **Tablette** : Pocket Computer avancée **ou** ordinateur avancé + modem sans fil.
  Un **moniteur avancé** attaché à l'ordinateur affichera l'interface (tactile).

## Utilisation

Sur la tortue :

```
mine                                   -- menu interactif
mine tunnel   <long> [haut] [larg]     -- tunnel
mine excavate <long> <larg> <prof>     -- volume (prof 0 = jusqu'à la bedrock)
mine excavate <long> <larg> <prof> alt -- preset alternance de couches (1 sur 2)
```

**Preset « alternance de couches »** (mode excavatrice) : mine la couche 1,
ignore la couche 2, mine la couche 3, ignore la 4… sur toute la profondeur.
Les couches ignorées sont simplement traversées par le puits central. Le preset
active automatiquement le **filtrage des minerais** et le **vein mining** pour
extraire les filons détectés. Idéal pour creuser vite de gros volumes en
réduisant l'usure, la consommation de carburant et le temps passé sur les
couches inutiles, sans manquer les minerais.

Sur la tablette / l'ordinateur : lance `remote` (ou laisse le startup le faire).
Clique/tape une tortue pour la suivre, puis utilise les boutons. Le bouton **Inv**
affiche tout ce que la tortue a miné depuis le début de la tâche (y compris ce qui
a déjà été déposé dans les coffres).

### Démarrage à distance par presets

Chaque tortue est **indépendante** (id, état, reprise propres) et peut être
démarrée seule ou en groupe :

- **Une seule** : sélectionne la tortue (chiffre/clic dans la liste) → dans sa vue
  détail, **Demarrer** (touche `D`) → choisis le preset. Seule **cette** tortue
  démarre.
- **Toutes** : depuis la liste, **Dem.tout** (touche `D`) → preset diffusé à
  **toutes les tortues en attente**.

Une tortue se met en attente via l'entrée **« Attendre les ordres »** de son menu
(elle apparaît alors à l'état *Attente* sur la tablette ; une touche sur la tortue
annule). Presets fournis (définis dans `minenet.lua` ; filtrage minerais + vein
mining + dépôt à la base) :

| Preset | Détail |
|--------|--------|
| Tunnel | tunnel 32 × 3 × 3 |
| Excavatrice | excavatrice 8 × 8 jusqu'à la bedrock |
| Alternance | excavatrice 8 × 8 jusqu'à la bedrock, 1 couche sur 2 |

**Dépôt « à la base » (mode `home`)** — un coffre de **VIDAGE** derrière la tortue
et un coffre de **CARBURANT** à gauche (jamais cassé : `refuel all` au départ +
ravitaillements). La tortue revient à la base pour vider les minerais et refaire
le plein.

- **Tunnel** : coffre carburant **collé à gauche** du départ (la voie part vers
  l'avant).
- **Excavatrice (centrée)** : place la tortue **au milieu** de la zone ; le coffre
  carburant va au **bord gauche** de la zone (1 bloc au-delà du bord), aligné sur
  la rangée de départ. La tortue s'y rend pour le plein.

```
Excavatrice centrée — vue de dessus (avant → droite) :

      C
      # # # # #     ← bord gauche de la zone
      # # # # #
  V   T # # # #     ← T = départ (au MILIEU) ; V = vidage (derrière)
      # # # # #
      # # # # #     ← bord droit de la zone

  C = carburant, 1 bloc au-delà du bord gauche (aligné sur la colonne de T)
```

### Boutons de contrôle (vue détail)

**Pause / Reprendre** (halte légère), **Stop** (arrêt *doux* : halte + sauvegarde,
mais la tortue **reste à l'écoute** → reprenable à distance par Reprendre/Restart),
**Base** (rentre puis termine), **Inv**, **Restart** (redémarre la tortue, reprise
auto). À la souris/tactile **ou** au clavier (1re lettre).
