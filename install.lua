--[[============================================================
  install.lua  —  Installateur / mise a jour du systeme de minage
  ------------------------------------------------------------
  Telecharge et installe les BONS fichiers selon l'appareil :
    - TORTUE   : minenet.lua + mine.lua   + startup.lua (reprise auto)
    - TABLETTE : minenet.lua + remote.lua + startup.lua (lance remote)
  (TABLETTE = Pocket Computer ou ordinateur de controle avec modem)

  Avantage : tortue et tablette ont TOUJOURS les memes versions, et le
  bon startup est mis en place tout seul (plus de renommage a la main).

  ============================================================
  ETAPE 1 — CONFIGURER LA SOURCE (une seule fois)

  --- Option A : GitHub (le plus simple : une seule URL) ---
   1. Mets minenet.lua, mine.lua, remote.lua, startup.lua et
      menu.lua dans un depot GitHub.
   2. Renseigne GITHUB_BASE ci-dessous = l'URL "raw" du dossier,
      terminee par "/". Exemple :
        https://raw.githubusercontent.com/TONPSEUDO/turtlemine/main/

  --- Option B : Pastebin (laisse GITHUB_BASE vide) ---
   1. Televerse CHAQUE fichier sur https://pastebin.com .
   2. Note le code (la partie apres pastebin.com/, ex: aBcD1234).
   3. Remplis la table PASTE ci-dessous.

  ============================================================
  ETAPE 2 — LANCER L'INSTALLATION SUR CHAQUE APPAREIL
   - install.lua aussi sur pastebin (code INSTALL) :  pastebin run INSTALL
   - install.lua deja copie sur l'appareil :          install
============================================================]]--

-------------------------------------------------------------
-- CONFIGURATION DE LA SOURCE  (remplis A *ou* B)
-------------------------------------------------------------
local GITHUB_BASE = "https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/"

local PASTE = {
  ["minenet.lua"] = "",   -- code pastebin de minenet.lua
  ["mine.lua"]    = "",   -- code pastebin de mine.lua
  ["remote.lua"]  = "",   -- code pastebin de remote.lua
  ["startup.lua"] = "",   -- code pastebin du startup commun
  ["menu.lua"]    = "",   -- code pastebin du gestionnaire
}

-------------------------------------------------------------
-- Affichage (couleur si dispo)
-------------------------------------------------------------
local COLOR = term.isColour and term.isColour()
local function col(c) if COLOR and colors then term.setTextColour(colors[c] or colors.white) end end
local function info(m) col("white");  print(m) end
local function okMsg(m) col("lime");  print(m); col("white") end
local function warn(m) col("orange"); print(m); col("white") end
local function err(m)  col("red");    print(m); col("white") end

term.clear(); term.setCursorPos(1,1)
col("cyan"); print("== Installation : systeme de minage =="); col("white")

if not http then
  err("HTTP est desactive sur ce serveur/monde.")
  print("Active 'http' dans la config de CC: Tweaked,")
  print("ou copie les fichiers a la main.")
  return
end

-------------------------------------------------------------
-- Telechargement
-------------------------------------------------------------
-- URL d'un fichier source selon la config choisie (GitHub prioritaire)
local function sourceURL(name)
  if GITHUB_BASE ~= "" then return GITHUB_BASE..name end
  local code = PASTE[name]
  if not code or code=="" then return nil end
  -- cache-buster : evite qu'un proxy renvoie une vieille version
  local cb = tostring(os.epoch and os.epoch("utc") or os.clock())
  return "https://pastebin.com/raw/"..code.."?cb="..cb
end

local function download(name)
  local u = sourceURL(name)
  if not u then return nil, "source non configuree (GITHUB_BASE/PASTE)" end
  local h, e = http.get(u)
  if not h then return nil, (e or "echec http") end
  local data = h.readAll(); h.close()
  if not data or #data == 0 then return nil, "fichier vide" end
  return data
end

local function save(dest, data)
  local f = fs.open(dest, "w")
  if not f then return false end
  f.write(data); f.close(); return true
end

-------------------------------------------------------------
-- Plan d'installation selon l'appareil
-------------------------------------------------------------
local isTurtle = (turtle ~= nil)
info(isTurtle and "Appareil detecte : TORTUE"
              or  "Appareil detecte : TABLETTE (controle)")
print()

-- { fichier source, destination sur l'appareil, libelle }
local plan
if isTurtle then
  plan = {
    { "minenet.lua", "minenet.lua", "module reseau" },
    { "mine.lua",    "mine.lua",    "programme de minage" },
    { "startup.lua", "startup.lua", "demarrage commun (reprise/menu)" },
    { "menu.lua",    "menu.lua",    "gestionnaire (maj/suppr)" },
  }
else
  plan = {
    { "minenet.lua",        "minenet.lua", "module reseau" },
    { "remote.lua",         "remote.lua",  "tablette de controle" },
    { "startup.lua",        "startup.lua", "demarrage commun (menu)" },
    { "menu.lua",           "menu.lua",    "gestionnaire (maj/suppr)" },
  }
end

-------------------------------------------------------------
-- Execution
-------------------------------------------------------------
local failed = 0
for _, item in ipairs(plan) do
  local src, dest, label = item[1], item[2], item[3]
  write("- "..label.." -> "..dest.." ... ")
  local data, e = download(src)
  if data and save(dest, data) then
    okMsg("OK ("..#data.." o)")
  else
    err("ECHEC : "..tostring(e))
    failed = failed + 1
  end
end

print()
if failed > 0 then
  warn(failed.." fichier(s) en echec.")
  warn("Verifie GITHUB_BASE / les codes PASTE, et que HTTP est actif.")
  return
end

okMsg("Installation terminee !")
print("Redemarrage dans 3 s (Ctrl+T pour annuler)...")
sleep(3)
os.reboot()
