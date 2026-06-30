--[[============================================================
  minenet.lua  —  Protocole reseau partage
  ------------------------------------------------------------
  Module commun a mine.lua (tortue) et remote.lua (tablette).
  Centralise le nom de protocole et les helpers reseau pour
  eviter toute duplication.

  Schema des messages (rednet, protocole M.PROTOCOL) :

    -- Etat diffuse par une tortue (~1 Hz) :
    { type="state", id=<number>, label=<string|nil>,
      state=<string>,            -- "Minage","Depot","Retour","Pause","Termine","Erreur"...
      pct=<number|nil>,          -- progression 0..100 (nil si inconnue, ex: bedrock)
      x=,y=,z=, dir=<0..3>,
      fuel=<number|"unlimited">, fuelPct=<number|nil>,
      invPct=<number>,           -- inventaire utilise 0..100
      elapsed=<number>,          -- secondes
      eta=<number|nil>,          -- secondes restantes estimees
      blocks=<number>, ores=<number>,
      distRemaining=<number|nil>,
      mode=<string>, finished=<bool> }

    -- Commande envoyee a une tortue (ou a toutes) :
    { type="cmd", target=<id|"all">,
      cmd="pause"|"resume"|"return"|"stop"|"stats"|"restart"|"inv"|"start",
      preset=<string> }          -- 'preset' : uniquement pour cmd="start"

    -- Inventaire renvoye par une tortue (reponse a la commande "inv") :
    { type="inv", id=<number>, label=<string|nil>,
      fuel=<number|"unlimited">,
      items={ { slot=<1..16>, name=<string>, count=<number> }, ... } }
============================================================]]--

local M = {}

M.PROTOCOL  = "turtlemine"   -- protocole rednet commun
M.OFFLINE   = 4              -- secondes sans message => tortue "hors-ligne" (cote tablette)

-- Presets de minage proposes depuis la tablette (demarrage a distance).
-- Partages tortue <-> tablette pour rester synchronises : la tortue construit
-- le job complet a partir de ces descripteurs (mine.lua -> buildPresetJob).
-- depot = "home" : coffre de VIDAGE derriere la tortue + coffre de CARBURANT a
-- sa GAUCHE (jamais casse ; plein "refuel all" au depart). Filtrage minerais +
-- vein mining actives. Place la tortue au bord GAUCHE de la zone a creuser.
M.PRESETS = {
  { name = "Tunnel",      mode = "tunnel",
    length = 32, width = 3, height = 3,
    vein = true, keep = "ores", deposit = "home" },
  { name = "Excavatrice", mode = "excavate",
    length = 8, width = 8, bedrock = true,
    vein = true, keep = "ores", deposit = "home" },
  { name = "Alternance",  mode = "excavate",
    length = 8, width = 8, bedrock = true, alternate = true,
    vein = true, keep = "ores", deposit = "home" },
}

-- Ouvre le premier modem disponible (sans fil de preference). Renvoie true si ok.
function M.openModem()
  if not (rednet and peripheral) then return false end
  local chosen
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local wireless = peripheral.call(name, "isWireless")
      if wireless then chosen = name; break end   -- on prefere le sans-fil
      chosen = chosen or name
    end
  end
  if not chosen then return false end
  if not rednet.isOpen(chosen) then rednet.open(chosen) end
  return true
end

-- Diffuse une table d'etat (depuis la tortue).
function M.sendState(stateTbl)
  stateTbl.type = "state"
  rednet.broadcast(stateTbl, M.PROTOCOL)
end

-- Diffuse l'inventaire d'une tortue (reponse a la commande "inv").
function M.sendInventory(invTbl)
  invTbl.type = "inv"
  rednet.broadcast(invTbl, M.PROTOCOL)
end

-- Envoie une commande a une tortue precise (id) ou a toutes ("all").
-- 'extra' (optionnel) : champs supplementaires fusionnes dans le message
-- (ex. { preset="Alternance" } pour cmd="start").
function M.sendCommand(targetId, cmd, extra)
  local m = { type = "cmd", target = targetId, cmd = cmd }
  if type(extra) == "table" then
    for k, v in pairs(extra) do if m[k] == nil then m[k] = v end end
  end
  rednet.broadcast(m, M.PROTOCOL)
end

return M
