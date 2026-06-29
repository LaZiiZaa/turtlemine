# Tableau de bord web — stats des tortues en temps réel

```
Tortues ──rednet──▶ webbridge.lua (ordi CC) ──HTTP POST──▶ server.js ──SSE──▶ navigateur
```

## 1. Lancer le serveur (sur ton PC ou un VPS)

Il faut **Node.js** (aucune dépendance à installer).

```bash
node server.js          # port 3000 par défaut
# ou : PORT=8080 node server.js
```

Ouvre ensuite **http://localhost:3000** dans ton navigateur.

## 2. Lancer la passerelle dans Minecraft

Sur un **ordinateur dédié** (pas une tortue) avec un **modem sans fil**, à côté de `minenet.lua` :

```
wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/webbridge.lua webbridge.lua
```

Édite la 1ʳᵉ ligne `SERVER` de `webbridge.lua` pour pointer vers ton serveur, puis :

```
webbridge
```

## 3. ⚠️ Le piège à connaître : l'API HTTP de CC bloque les IP privées

Par défaut, CC: Tweaked **interdit** aux ordinateurs de contacter des adresses
locales (`127.0.0.1`, `192.168.x.x`, `10.x.x.x`…) pour des raisons de sécurité.
Si ton serveur tourne sur le **même réseau** que le serveur Minecraft, il faut
l'autoriser dans la config **`computercraft-server.toml`** :

```toml
[[http.rules]]
host = "192.168.1.50"   # l'IP de la machine qui fait tourner server.js
action = "allow"
```

> Place cette règle **avant** les règles `deny` des plages privées (les règles
> sont évaluées dans l'ordre). Puis redémarre le serveur Minecraft.
> Vérifie aussi que `[http] enabled = true`.

**Alternatives sans toucher à la config :**
- Héberger `server.js` sur un **VPS / hébergeur public** (IP publique → autorisée par défaut).
- Utiliser un **tunnel** (ex. `ngrok http 3000`) et mettre l'URL publique dans `SERVER`.

## Notes
- `webbridge.lua` peut tourner en permanence (mets-le dans un `startup` sur l'ordi passerelle).
- Le serveur garde le dernier état en mémoire et le pousse instantanément (SSE) à chaque mise à jour — pas de rafraîchissement de page nécessaire.
- Plusieurs navigateurs peuvent regarder en même temps.
