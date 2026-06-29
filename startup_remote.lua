--[[============================================================
  startup_remote.lua  —  Demarrage automatique de la tablette remote
  ------------------------------------------------------------
  S'execute tout seul a chaque allumage / redemarrage de l'appareil
  de controle (Pocket Computer avancee ou ordinateur avec modem).

  - Detecte automatiquement un modem sans fil sur tous les cotes
    (technique de peripheral.isPresent / getType / getNames).
  - Si un modem sans fil est trouve  -> lance remote.lua.
  - Si seul un modem filaire existe  -> avertit puis lance quand meme.
  - Si aucun modem                   -> explique comment en attacher un.

  INSTALLATION : pose ce fichier sur la Pocket Computer / l'ordinateur
  de controle et RENOMME-le en "startup" (ou "startup.lua") pour qu'il
  se lance tout seul. Doit etre a cote de remote.lua et minenet.lua.
============================================================]]--

-- Repli couleur (Pocket avancee = couleur, sinon monochrome)
local COLOR = term.isColour and term.isColour()
local function pT(c) if COLOR and colors then term.setTextColour(colors[c] or colors.white) end end
local function info(msg)  pT("white");  print(msg) end
local function ok(msg)    pT("lime");   print(msg); pT("white") end
local function warn(msg)  pT("orange"); print(msg); pT("white") end
local function err(msg)   pT("red");    print(msg); pT("white") end

term.clear(); term.setCursorPos(1,1)
pT("cyan"); print("== Tablette de minage =="); pT("white")

-------------------------------------------------------------
-- Detection des modems (inspire de image.png)
--   On parcourt chaque cote, on teste isPresent + getType,
--   puis on regarde si le modem est sans fil (isWireless).
-------------------------------------------------------------
local SIDES = { "front", "back", "left", "right", "top", "bottom" }

local function findModem()
  local wireless, wired = nil, nil
  -- Cotes physiques de l'appareil
  for _, side in ipairs(SIDES) do
    if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
      if peripheral.call(side, "isWireless") then
        wireless = wireless or side
      else
        wired = wired or side
      end
    end
  end
  -- Filet de securite : modems nommes (cables reseau, etc.)
  if not (wireless or wired) and peripheral.getNames then
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name) == "modem" then
        if peripheral.call(name, "isWireless") then wireless = wireless or name
        else wired = wired or name end
      end
    end
  end
  return wireless, wired
end

local wireless, wired = findModem()

-------------------------------------------------------------
-- Lancement de remote.lua selon ce qu'on a trouve
-------------------------------------------------------------
if not fs.exists("remote.lua") and not fs.exists("remote") then
  err("remote.lua introuvable sur cet appareil !")
  print("Copie remote.lua et minenet.lua ici.")
  return
end

if wireless then
  ok("Modem sans fil detecte sur : "..wireless)
  sleep(0.5)
  shell.run("remote")
elseif wired then
  warn("Seul un modem FILAIRE a ete trouve ("..wired..").")
  warn("Le suivi des tortues fonctionne mieux en sans fil.")
  sleep(1)
  shell.run("remote")
else
  err("Aucun modem trouve sur cet appareil.")
  print("Attache un modem sans fil :")
  print(" - Pocket : clic-droit avec le Wireless Modem")
  print(" - Ordi   : pose un modem sans fil sur un cote")
  print("Puis redemarre (Ctrl+R).")
end
