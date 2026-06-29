# turtlemine — Système de minage pour CC: Tweaked

Tortues de minage autonomes (tunnel / excavatrice) + tablette de suivi et de
contrôle à distance, pour [CC: Tweaked](https://tweaked.cc/) (Minecraft).

## Composants

| Fichier | Appareil | Rôle |
|---|---|---|
| `mine.lua` | Tortue | Programme de minage : modes tunnel/excavatrice, filtrage des minerais, dépôt auto (coffre Ender ou coffre de base), gestion du carburant, reprise après coupure. |
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
- Pour le dépôt : un **coffre de l'Ender** dans l'inventaire (mode `ender`) ou un
  coffre placé à la base (mode `home`).
- **Tablette** : Pocket Computer avancée **ou** ordinateur avancé + modem sans fil.
  Un **moniteur avancé** attaché à l'ordinateur affichera l'interface (tactile).

## Utilisation

Sur la tortue :

```
mine                                   -- menu interactif
mine tunnel   <long> [haut] [larg]     -- tunnel
mine excavate <long> <larg> <prof>     -- volume (prof 0 = jusqu'à la bedrock)
```

Sur la tablette / l'ordinateur : lance `remote` (ou laisse le startup le faire).
Clique/tape une tortue pour la suivre, puis utilise les boutons. Le bouton **Inv**
affiche tout ce que la tortue a miné depuis le début de la tâche (y compris ce qui
a déjà été déposé dans les coffres).
