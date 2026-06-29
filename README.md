# turtlemine — Système de minage pour CC: Tweaked

Tortues de minage autonomes (tunnel / excavatrice) + tablette de suivi et de
contrôle à distance, pour [CC: Tweaked](https://tweaked.cc/) (Minecraft).

## Composants

| Fichier | Appareil | Rôle |
|---|---|---|
| `mine.lua` | Tortue | Programme de minage : modes tunnel/excavatrice, filtrage des minerais, dépôt auto (coffre Ender ou coffre de base), gestion du carburant, reprise après coupure. |
| `remote.lua` | Tablette | Pocket Computer / ordinateur de contrôle : suit toutes les tortues en temps réel, vue détail, commandes (pause / reprise / retour base / arrêt / restart / inventaire). Affichage **responsive**, diffusion sur un **moniteur** si présent. |
| `minenet.lua` | Les deux | Module réseau partagé (protocole rednet commun). |
| `startup.lua` | Tortue | Démarrage auto : reprend la tâche en cours après un reboot. |
| `startup_remote.lua` | Tablette | Démarrage auto : détecte le modem et lance `remote`. |
| `install.lua` | Les deux | Installateur : détecte l'appareil et télécharge les bons fichiers. |

## Installation rapide (recommandée)

Sur **chaque** appareil (tortue et tablette), avec HTTP activé :

```
wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/install.lua install.lua
install
```

L'installateur détecte automatiquement s'il tourne sur une **tortue** ou sur une
**tablette** et installe le set adapté (dont le bon `startup.lua`), puis redémarre.

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

Sur la tablette : lance `remote` (ou laisse le startup le faire). Clique/tape une
tortue pour la suivre, puis utilise les boutons. Le bouton **Inv** affiche tout
ce que la tortue a miné depuis le début de la tâche (y compris ce qui a déjà été
déposé dans les coffres).
