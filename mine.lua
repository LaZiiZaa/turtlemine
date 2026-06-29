--[[============================================================
  mine.lua  v2  —  Tortue de minage pour CC: Tweaked
  ------------------------------------------------------------
  Modes      : tunnel (couloir)  |  excavate (volume)
  Filtrage   : ne garde QUE les minerais (jette roche/terre)
  Extensions :
    [1] Depot auto quand l'inventaire est plein
        - "ender" : coffre de l'Ender pose sur place (aucun trajet)
        - "home"  : retour au coffre place SOUS le point de depart
    [2] Calcul/verification du carburant avant de partir
    [4] Reprise apres coupure (etat sauvegarde dans un fichier)
    [5] Menu interactif au lancement (ou arguments en ligne)

  Usage :
    mine                       -> menu interactif
    mine tunnel   <long> [haut] [larg] [tout|rien]
    mine excavate <long> <larg> <prof> [tout|rien]   (prof 0 = jusqu'a la bedrock)
    -> "tout" = garder tous les blocs ; "rien" = creuser sans rien garder
       (defaut : garder seulement les minerais)
============================================================]]--

if not turtle then error("A executer sur une TORTUE.", 0) end

-------------------------------------------------------------
-- CONFIGURATION
-------------------------------------------------------------
local ORE_KEYWORDS  = { "ore", "ancient_debris", "raw_" }
local FUEL_ITEMS    = {
  ["minecraft:coal"]=true, ["minecraft:charcoal"]=true,
  ["minecraft:blaze_rod"]=true, ["minecraft:lava_bucket"]=true,
}
local FUEL_VALUE    = {
  ["minecraft:coal"]=80, ["minecraft:charcoal"]=80,
  ["minecraft:blaze_rod"]=120, ["minecraft:lava_bucket"]=1000,
}
local ENDER_CHEST_ID = "minecraft:ender_chest"  -- objet utilise en mode "ender"
local DEFAULT_DEPOSIT= "ender"                  -- depot par defaut en ligne de commande
local VEIN_MINE      = true
local KEEP_FUEL      = true
local FUEL_BUFFER    = 10
local FUEL_RESERVE   = 50          -- carburant a garder en reserve pour rentrer (marge de securite)
local REFUEL_GRAB    = 10           -- nb de piles aspirees dans le coffre carburant a chaque passage
local MAX_VEIN       = 64
local RETURN_HOME    = true        -- revenir au point de depart a la fin (tous les modes)
local STATE_FILE     = ".mine_state"

-------------------------------------------------------------
-- ETAT GLOBAL
--   heading : 0=+x  1=+z  2=-x  3=-z
-------------------------------------------------------------
local DELTA   = { [0]={1,0}, [1]={0,1}, [2]={-1,0}, [3]={0,-1} }
local pos     = { x=0, y=0, z=0 }
local heading = 0
local trail   = {}        -- fil d'Ariane (deplacements principaux depuis le depart)
local recording   = false -- enregistre-t-on les deplacements dans le trail ?
local TRAIL_ENABLED = false
local aborted = false     -- mis a true si on doit interrompre (ex: carburant)
local job     = nil       -- description de la tache en cours
local resumed = false     -- true si on reprend une tache sauvegardee

-- Pilotage distant / pause (modifies par la tache UI-reseau)
local paused        = false
local homeRequested = false   -- demande de retour immediat a la base
local stopRequested = false   -- demande d'arret complet
local state         = "Init"  -- etat courant (HUD + diffusion reseau)
local statusMsg     = ""      -- message transitoire affiche sous le HUD

-- Declarations anticipees (definies plus bas, utilisees plus haut)
local isOre          -- detection minerai (defini en section FILTRAGE)
local controlCheck   -- pause/retour/arret distant (defini en section CONTROLE)

-- Statistiques (compteurs : HUD, rapport de fin, diffusion reseau)
local stats = {
  startClock = 0, blocks = 0, ores = {}, oresTotal = 0,
  mined = {},   -- recolte cumulee du job : nom -> nb (compte AU MOMENT du minage,
                -- donc inclut ce qui a deja ete depose / jete ; survit a une reprise)
  deposits = 0, trips = 0, distance = 0, fuelStart = 0,
}

-------------------------------------------------------------
-- PETITS UTILITAIRES D'ENTREE
-------------------------------------------------------------
local function yesno(msg, default)
  while true do
    write(msg.." (o/n)"..(default and " ["..default.."]" or "")..": ")
    local r = read():lower()
    if r=="" and default then r=default end
    if r=="o" or r=="oui" or r=="y" then return true end
    if r=="n" or r=="non" then return false end
  end
end
local function askNum(msg, default)
  while true do
    write(msg..(default and " ["..default.."]" or "")..": ")
    local r = read()
    if r=="" and default then return default end
    local n = tonumber(r)
    if n then return math.floor(n) end
  end
end

-------------------------------------------------------------
-- PERSISTANCE (reprise apres coupure)
-------------------------------------------------------------
local function saveState()
  job.pos     = { x=pos.x, y=pos.y, z=pos.z }
  job.heading = heading
  job.trail   = trail   -- on garde toujours le chemin (retour de securite + reprise)
  job.stats   = stats   -- compteurs (continuite des totaux apres une coupure)
  local h = fs.open(STATE_FILE, "w")
  h.write(textutils.serialize(job))
  h.close()
end
local function clearState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end
local function describe(j)
  if j.mode=="tunnel" then
    return ("Tunnel L=%d l=%d h=%d (bloc %d/%d)"):format(j.length, j.width or 1, j.height, j.progress.i, j.length)
  end
  local d = j.bedrock and "bedrock" or tostring(j.depth)
  return ("Excavate L=%d l=%d prof=%s (couche %d)")
    :format(j.length, j.width or 1, d, j.progress.layer or 0)
end

-------------------------------------------------------------
-- CARBURANT
-------------------------------------------------------------
local function refuelFromInventory()
  for s=1,16 do
    local d = turtle.getItemDetail(s)
    if d and FUEL_ITEMS[d.name] then
      turtle.select(s)
      if turtle.refuel(1) then turtle.select(1); return true end
    end
  end
  turtle.select(1); return false
end
local function refuelAll()
  for s=1,16 do
    local d=turtle.getItemDetail(s)
    if d and FUEL_VALUE[d.name] then turtle.select(s); turtle.refuel() end  -- brule toute la pile
  end
  turtle.select(1)
end
local function ensureFuel()
  if turtle.getFuelLevel()=="unlimited" then return true end
  while turtle.getFuelLevel() <= FUEL_BUFFER do
    if not refuelFromInventory() then
      if turtle.getFuelLevel() <= 0 then statusMsg="Plus de carburant !"; return false end
      return true
    end
  end
  return true
end
local function availableFuel()
  local f = turtle.getFuelLevel()
  if f=="unlimited" then return math.huge end
  for s=1,16 do
    local d = turtle.getItemDetail(s)
    if d and FUEL_VALUE[d.name] then f = f + FUEL_VALUE[d.name]*d.count end
  end
  return f
end
local function estimateFuel(j)
  local base
  if j.mode=="tunnel" then
    local w, h = (j.width or 1), (j.height or 1)
    local perCell = 1 + 2*(w-1) + w*2*math.max(0, h-1)       -- avance + tranche LxH
    base = j.length*perCell + 2*j.length + 10                -- + un aller-retour
  else
    local depth = j.bedrock and 64 or j.depth                -- bedrock : estimation ~64 couches
    base = j.length*j.width*depth + depth                    -- volume + descentes
         + (j.length + j.width + depth) + 10                 -- retour
  end
  return math.ceil(base * 1.2)                               -- marge 20%
end
local function checkFuel(j)
  if j.mode=="tunnel" and j.deposit=="home" then
    print("Carburant : ravitaillement auto via le coffre de gauche.")
    return true
  end
  local need, have = estimateFuel(j), availableFuel()
  if have==math.huge then return true end
  print(("Carburant : besoin ~%d, dispo ~%d"):format(need, have))
  if have < need then
    print("!! Possiblement insuffisant (le vein-mining augmente le besoin).")
    return yesno("Continuer quand meme ?", "n")
  end
  return true
end

-- SECURITE CARBURANT : a-t-on de quoi rentrer au depart ?
local function safetyMargin(j)
  -- reserve voulue + conso possible avant le prochain controle (une tranche)
  local tunnel = (j.mode=="tunnel")
  local h = tunnel and (j.height or 1) or 1
  local w = tunnel and (j.width or 1) or 1
  local step = 1 + 2*(w-1) + w*2*math.max(0, h-1)  -- avance + tranche du tunnel
  if j.vein then
    local veins = tunnel and (w*h) or 1            -- en tunnel : une detection par case de la tranche
    step = step + veins*2*MAX_VEIN
  end
  return FUEL_RESERVE + step
end
local function fuelLow(j)
  local f = turtle.getFuelLevel()
  if f=="unlimited" then return false end
  local home = math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)  -- distance au depart
  return f <= home + safetyMargin(j)
end

-------------------------------------------------------------
-- COMPTEURS (blocs casses / minerais) + CREUSER (anti gravier/sable)
-------------------------------------------------------------
-- Casse un bloc via digFn en le comptant ; inspectFn donne le nom AVANT
-- de creuser pour taller les minerais par type. Renvoie le succes du dig.
local function tallyDig(inspectFn, digFn)
  local seen, data = inspectFn()
  if not digFn() then return false end
  stats.blocks = stats.blocks + 1
  if seen and data then
    -- recolte cumulee : on compte TOUT bloc casse, des qu'il est mine
    -- (donc compris ce qui sera ensuite depose dans un coffre ou jete)
    stats.mined[data.name] = (stats.mined[data.name] or 0) + 1
    if isOre(data.name) then
      stats.ores[data.name] = (stats.ores[data.name] or 0) + 1
      stats.oresTotal = stats.oresTotal + 1
    end
  end
  return true
end
local function digFront()
  local n=0
  while turtle.detect() do
    if not tallyDig(turtle.inspect, turtle.dig) then break end
    sleep(0); n=n+1; if n>64 then break end
  end
end
local function digUp()
  local n=0
  while turtle.detectUp() do
    if not tallyDig(turtle.inspectUp, turtle.digUp) then break end
    sleep(0); n=n+1; if n>64 then break end
  end
end
local function digDown() return tallyDig(turtle.inspectDown, turtle.digDown) end

-------------------------------------------------------------
-- DEPLACEMENT (met a jour la position + trail)
-------------------------------------------------------------
local function record(dx,dy,dz)
  if recording and TRAIL_ENABLED then trail[#trail+1] = {dx,dy,dz} end
end
local function turnRight() turtle.turnRight(); heading=(heading+1)%4 end
local function turnLeft()  turtle.turnLeft();  heading=(heading+3)%4 end
local function face(h)
  local diff = (h - heading) % 4
  if diff==1 then turnRight()
  elseif diff==2 then turnRight(); turnRight()
  elseif diff==3 then turnLeft() end
end
local function forward()
  if not ensureFuel() then return false end
  local n=0
  while not turtle.forward() do
    if turtle.detect() then digFront() else turtle.attack() end
    n=n+1; if n>64 then return false end
  end
  pos.x = pos.x + DELTA[heading][1]; pos.z = pos.z + DELTA[heading][2]
  stats.distance = stats.distance + 1
  record(DELTA[heading][1], 0, DELTA[heading][2])
  return true
end
local function back()
  if not ensureFuel() then return false end
  if turtle.back() then
    pos.x = pos.x - DELTA[heading][1]; pos.z = pos.z - DELTA[heading][2]
    stats.distance = stats.distance + 1
    return true
  end
  turnRight(); turnRight(); local ok = forward(); turnRight(); turnRight()
  return ok
end
local function up()
  if not ensureFuel() then return false end
  local n=0
  while not turtle.up() do
    if turtle.detectUp() then digUp() else turtle.attackUp() end
    n=n+1; if n>64 then return false end
  end
  pos.y = pos.y + 1; stats.distance = stats.distance + 1; record(0,1,0); return true
end
local function down()
  if not ensureFuel() then return false end
  local n=0
  while not turtle.down() do
    if turtle.detectDown() then digDown() else turtle.attackDown() end
    n=n+1; if n>64 then return false end
  end
  pos.y = pos.y - 1; stats.distance = stats.distance + 1; record(0,-1,0); return true
end

-- creuse la colonne au-dessus de la cellule courante (tunnel plus haut)
-- + detecte les veines de minerai a CHAQUE niveau (si vein=true)
local mineVein     -- declaration anticipee (defini dans la section VEIN MINING)
local function clearColumn(height, vein)
  if vein then mineVein() end                  -- veines au niveau du sol
  if not height or height<=1 then return end
  local prev=recording; recording=false
  local climbed=0
  for _=2,height do
    digUp()
    if not up() then break end
    climbed=climbed+1
    if vein then mineVein() end                -- veines a ce niveau
  end
  for _=1,climbed do down() end
  recording=prev
end

-- creuse une tranche LARGEUR x HAUTEUR CENTREE sur la voie de la tortue
-- (gauche et droite equilibres), puis revient au centre, au sol, face au tunnel.
local function carveSlice(width, height, vein)
  width = width or 1
  local left  = math.floor((width-1)/2)
  local right = (width-1) - left
  clearColumn(height, vein)                    -- colonne centrale (la voie)
  local moved
  moved=0                                       -- cote DROIT
  for _=1,right do
    turnRight(); digFront()
    if not forward() then turnLeft(); break end
    turnLeft(); moved=moved+1
    clearColumn(height, vein)
  end
  for _=1,moved do turnLeft(); forward(); turnRight() end   -- retour au centre
  moved=0                                       -- cote GAUCHE
  for _=1,left do
    turnLeft(); digFront()
    if not forward() then turnRight(); break end
    turnRight(); moved=moved+1
    clearColumn(height, vein)
  end
  for _=1,moved do turnRight(); forward(); turnLeft() end    -- retour au centre
end

-- NAVIGATION ABSOLUE (par rapport au point de depart), en creusant si besoin.
-- Tunnel : on circule sur la voie centrale (deja creusee).
-- Excavate : on descend par un puits central au point de depart (deja creuse).
local function gotoY(ty)
  while pos.y < ty do if not up()   then break end end
  while pos.y > ty do if not down() then break end end
end
local function gotoX(tx)
  if pos.x ~= tx then face(pos.x < tx and 0 or 2) end
  while pos.x ~= tx do if not forward() then break end end
end
local function gotoZ(tz)
  if pos.z ~= tz then face(pos.z < tz and 1 or 3) end
  while pos.z ~= tz do if not forward() then break end end
end
-- revient au bloc de depart (0,0,0), oriente vers l'avant
local function goToStart()
  gotoX(0); gotoZ(0)   -- se recaler sur la colonne du depart (au niveau courant)
  gotoY(0)             -- remonter par le puits central
  face(0)
end
-- rejoint une position de travail memorisee (x,y,z,orientation)
local function gotoWork(wx, wy, wz, wh)
  gotoY(wy)
  gotoX(wx); gotoZ(wz)
  face(wh or 0)
  stats.trips = stats.trips + 1   -- un aller-retour base<->chantier de plus
end

-------------------------------------------------------------
-- FILTRAGE
-------------------------------------------------------------
function isOre(name)   -- (assigne a la declaration anticipee ci-dessus)
  if not name then return false end
  for _,kw in ipairs(ORE_KEYWORDS) do
    if string.find(name, kw, 1, true) then return true end
  end
  return false
end
-- Mode de conservation effectif : "ores" | "all" | "none".
-- Compat : ancienne sauvegarde sans job.keep -> derive de job.filter.
local function keepMode()
  if not job then return "ores" end
  if job.keep then return job.keep end
  if job.filter==false then return "all" end
  return "ores"
end
-- objets a NE PAS jeter au sol (trash)
local function isKeep(name)
  local k = keepMode()
  if k=="all" then return true end
  if KEEP_FUEL and FUEL_ITEMS[name] then return true end   -- carburant : toujours garde
  if name==ENDER_CHEST_ID then return true end             -- coffre Ender : toujours garde
  if k=="none" then return false end                       -- "rien" : on jette tout le reste
  return isOre(name)                                        -- "ores" : on garde les minerais
end
-- objets a verser dans le coffre / coffre de l'Ender
local function isDepositable(name)
  if name==ENDER_CHEST_ID then return false end            -- on garde le coffre
  if KEEP_FUEL and FUEL_ITEMS[name] then return false end   -- on garde le carburant
  local k = keepMode()
  if k=="none" then return false end                       -- rien a deposer (tout jete au sol)
  if k=="all"  then return true end                        -- on depose tout le reste
  return isOre(name)                                        -- seulement les minerais
end
local function findItem(id)
  for s=1,16 do local d=turtle.getItemDetail(s); if d and d.name==id then return s end end
  return nil
end
local function cleanInventory()
  for s=1,16 do
    local d=turtle.getItemDetail(s)
    if d and not isKeep(d.name) then turtle.select(s); turtle.dropDown() end
  end
  turtle.select(1)
end
local function inventoryFull()
  for s=1,16 do if turtle.getItemCount(s)==0 then return false end end
  return true
end

-------------------------------------------------------------
-- DEPOT [1]
-------------------------------------------------------------
local function depositEnder()
  local slot = findItem(ENDER_CHEST_ID)
  if not slot then statusMsg="Pas de coffre de l'Ender !"; return end
  state="Depot"; statusMsg="Depot (coffre de l'Ender)"
  stats.deposits = stats.deposits + 1
  turtle.digUp()
  turtle.select(slot)
  if not turtle.placeUp() then turtle.digUp(); turtle.placeUp() end
  for s=1,16 do
    local d=turtle.getItemDetail(s)
    if d and isDepositable(d.name) then turtle.select(s); turtle.dropUp() end
  end
  turtle.select(1)
  turtle.digUp()                 -- recupere le coffre
end
-- TUNNEL : coffre de vidage a l'ARRIERE, coffre carburant a GAUCHE du depart
local function initFuelTunnel()
  face(3)                                    -- coffre carburant (gauche)
  for _=1,REFUEL_GRAB do if not turtle.suck() then break end end
  refuelAll()
  face(0)
end
local function serviceAtHomeTunnel()
  local wx,wy,wz,wh = pos.x,pos.y,pos.z,heading
  state="Ravitaillement"; statusMsg="Vidage + plein au depart"
  stats.deposits = stats.deposits + 1
  goToStart()                                 -- revient a (0,0,0), face avant
  face(2)                                     -- coffre de vidage (arriere)
  for s=1,16 do
    local d=turtle.getItemDetail(s)
    if d and isDepositable(d.name) then
      turtle.select(s)
      if not turtle.drop() then statusMsg="Coffre arriere plein !" end
    end
  end
  face(3)                                     -- coffre carburant (gauche)
  for _=1,REFUEL_GRAB do if not turtle.suck() then break end end
  refuelAll()
  turtle.select(1)
  if job and fuelLow(job) then                -- pas assez meme apres le plein -> on reste
    state="Erreur"; statusMsg="Plein insuffisant : reste au depart"
    face(0); aborted=true; return
  end
  gotoWork(wx,wy,wz,wh)                        -- repart au chantier
end
local function depositHome()
  if job.mode=="tunnel" then serviceAtHomeTunnel(); return end
  -- EXCAVATE : coffre de vidage a l'ARRIERE du point de depart (en surface)
  local wx,wy,wz,wh = pos.x,pos.y,pos.z,heading
  state="Depot"; statusMsg="Vidage au depart"
  stats.deposits = stats.deposits + 1
  goToStart()
  face(2)
  for s=1,16 do
    local d=turtle.getItemDetail(s)
    if d and isDepositable(d.name) then
      turtle.select(s)
      if not turtle.drop() then statusMsg="Coffre arriere plein/absent" end
    end
  end
  turtle.select(1)
  statusMsg="Retour au chantier"
  gotoWork(wx,wy,wz,wh)
end
local function manageInventory()
  if not inventoryFull() then return end
  cleanInventory()
  if not inventoryFull() then return end          -- de la place liberee, ok
  if     job.deposit=="ender" then depositEnder()
  elseif job.deposit=="home"  then depositHome()
  else statusMsg="Inventaire plein (depot off) : surplus perdu" end
end
-- retour d'urgence : rentre au depart et s'arrete
local function emergencyHome()
  state="Retour"; statusMsg="Carburant bas : retour au depart"
  goToStart()
  aborted = true
end
-- a appeler avant de miner chaque nouvelle cellule
local function fuelGuard(j)
  if not fuelLow(j) then return end
  ensureFuel()                       -- d'abord bruler le charbon en stock
  if not fuelLow(j) then return end
  if j.mode=="tunnel" and j.deposit=="home" then
    serviceAtHomeTunnel()            -- va se ravitailler (peut declencher l'arret)
  else
    emergencyHome()
  end
end

-------------------------------------------------------------
-- VEIN MINING
-------------------------------------------------------------
local function nameAt(dir)
  local ok,data
  if     dir=="front" then ok,data=turtle.inspect()
  elseif dir=="up"    then ok,data=turtle.inspectUp()
  elseif dir=="down"  then ok,data=turtle.inspectDown() end
  if ok then return data.name end
  return nil
end
function mineVein(budget)     -- (assigne a la declaration anticipee ci-dessus)
  budget = budget or MAX_VEIN
  if budget<=0 then return end
  local prev=recording; recording=false      -- les detours de veine ne vont pas dans le trail
  if isOre(nameAt("up"))   then digUp();   up();   mineVein(budget-1); down() end
  if isOre(nameAt("down")) then digDown(); down(); mineVein(budget-1); up()   end
  for _=1,4 do
    if isOre(nameAt("front")) then digFront(); forward(); mineVein(budget-1); back() end
    turnRight()
  end
  recording=prev
  if inventoryFull() then cleanInventory() end  -- libere de la place sans navigation (sur de partout)
end

-------------------------------------------------------------
-- MODE TUNNEL
-------------------------------------------------------------
local function runTunnel(j)
  state = "Minage"; statusMsg = ("Tunnel %dx%dx%d"):format(j.length, j.width or 1, j.height)
  if j.deposit=="home" then initFuelTunnel() end   -- premier plein depuis le coffre de gauche
  for i=j.progress.i+1, j.length do
    fuelGuard(j); controlCheck(); if aborted then break end
    recording=true
    digFront()
    if not forward() then statusMsg="Bloque a "..i; break end
    carveSlice(j.width or 1, j.height, j.vein)  -- tranche largeur x hauteur (+ minerais)
    manageInventory(); if aborted then break end
    j.progress.i = i
    saveState()
  end
end

-------------------------------------------------------------
-- MODE EXCAVATRICE (footprint L x l, sur 'prof' couches)
-------------------------------------------------------------
-- creuse UNE couche L x l, centree sur la colonne de depart, en serpentin.
-- La tortue commence et finit (via le retour du runExcavate) sur la colonne du depart.
-- Renvoie false si bloquee (bedrock dans la couche, etc.).
local function digLayerCentered(j)
  local W = j.width or 1
  local left = math.floor((W-1)/2)
  for _=1,left do                         -- aller au bord gauche (z = -left)
    fuelGuard(j); controlCheck(); if aborted then return false end
    turnLeft(); digFront()
    if not forward() then turnRight(); return false end
    turnRight()
    if j.vein then mineVein() end
    manageInventory(); if aborted then return false end
    saveState()
  end
  for r=1,W do                            -- W rangees, chacune de longueur 'length'
    for _=1,(j.length-1) do
      fuelGuard(j); controlCheck(); if aborted then return false end
      digFront()
      if not forward() then statusMsg="Bloque (couche)"; return false end
      if j.vein then mineVein() end
      manageInventory(); if aborted then return false end
      saveState()
    end
    if r < W then                         -- decaler vers la rangee suivante (+z)
      fuelGuard(j); controlCheck(); if aborted then return false end
      if r%2==1 then turnRight(); digFront(); forward(); turnRight()
      else           turnLeft();  digFront(); forward(); turnLeft() end
      if j.vein then mineVein() end
      manageInventory(); if aborted then return false end
      saveState()
    end
  end
  return true
end

local function runExcavate(j)
  local depthLabel = j.bedrock and "bedrock" or tostring(j.depth)
  state = "Minage"; statusMsg = ("Excavate %dx%d prof=%s"):format(j.length, j.width or 1, depthLabel)
  gotoX(0); gotoZ(0); face(0)             -- colonne du depart au niveau courant (reprise OK)
  while true do
    local d = -pos.y                       -- profondeur courante (0 = surface)
    j.progress = { layer = d+1 }
    local ok = digLayerCentered(j)
    if aborted then return end
    gotoX(0); gotoZ(0); face(0)            -- revient sur la colonne du depart
    saveState()
    if not ok then break end               -- couche bloquee -> on s'arrete
    if (not j.bedrock) and (d+1) >= j.depth then break end   -- profondeur atteinte
    fuelGuard(j); controlCheck(); if aborted then return end
    digDown()
    if not down() then                     -- bedrock / bloc indestructible -> stop
      statusMsg = j.bedrock and ("Bedrock atteinte (couche "..(d+1)..")") or "Descente bloquee"
      break
    end
    saveState()
  end
end

-------------------------------------------------------------
-- PROGRESSION / AFFICHAGE (HUD couleur, repli monochrome)
-------------------------------------------------------------
-- Nombre total de blocs estime (nil si inconnu, ex: jusqu'a la bedrock)
local function estimatedTotalBlocks(j)
  if not j then return nil end
  if j.mode=="tunnel" then return j.length*(j.width or 1)*(j.height or 1) end
  if j.bedrock then return nil end
  return j.length*(j.width or 1)*(j.depth or 1)
end
local function progressFraction()
  local total = estimatedTotalBlocks(job)
  if not total or total<=0 then return nil end
  return math.min(1, stats.blocks/total)
end
local function elapsedSeconds()
  return math.max(0, os.clock() - (stats.startClock or os.clock()))
end
local function etaSeconds()
  local fr, el = progressFraction(), elapsedSeconds()
  if not fr or fr<=0 or el<=0 then return nil end
  return el/fr - el
end
local function invUsedPct()
  local used=0
  for s=1,16 do if turtle.getItemCount(s)>0 then used=used+1 end end
  return math.floor(used/16*100 + 0.5)
end
local function fuelPctValue()
  local f = turtle.getFuelLevel()
  if f=="unlimited" then return nil end
  local lim = turtle.getFuelLimit and turtle.getFuelLimit()
  if not lim or lim=="unlimited" or lim<=0 then return nil end
  return math.floor(f/lim*100 + 0.5)
end
local function dirName(h)
  return ({[0]="+X (Est)",[1]="+Z (Sud)",[2]="-X (Ouest)",[3]="-Z (Nord)"})[h] or "?"
end
local function fmtTime(sec)
  if not sec then return "?" end
  sec = math.floor(sec)
  local m, s = math.floor(sec/60), sec%60
  if m>=60 then local hh=math.floor(m/60); return ("%dh%02dm"):format(hh, m%60) end
  return ("%dm%02ds"):format(m, s)
end

-- Table d'etat partagee par le HUD ET la diffusion reseau (pas de duplication)
local function buildState(finished)
  local fr = progressFraction()
  local total = estimatedTotalBlocks(job)
  return {
    id    = os.getComputerID and os.getComputerID() or 0,
    label = os.getComputerLabel and os.getComputerLabel() or nil,
    state = state, statusMsg = statusMsg,
    pct   = fr and math.floor(fr*100+0.5) or nil,
    x = pos.x, y = pos.y, z = pos.z, dir = heading,
    fuel = turtle.getFuelLevel(), fuelPct = fuelPctValue(),
    invPct = invUsedPct(),
    elapsed = math.floor(elapsedSeconds()),
    eta = etaSeconds() and math.floor(etaSeconds()) or nil,
    blocks = stats.blocks, ores = stats.oresTotal,
    distRemaining = total and math.max(0, total - stats.blocks) or nil,
    mode = job and job.mode, finished = finished or (state=="Termine"),
  }
end

-- Inventaire actuel (reponse a la commande "inv" de la tablette)
local function buildInventory()
  local items = {}
  for s=1,16 do
    local d = turtle.getItemDetail(s)
    if d then items[#items+1] = { slot=s, name=d.name, count=d.count } end
  end
  return {
    id    = os.getComputerID and os.getComputerID() or 0,
    label = os.getComputerLabel and os.getComputerLabel() or nil,
    fuel  = turtle.getFuelLevel(),
    items = items,                 -- contenu actuel des slots (contexte)
    mined = stats.mined,           -- TOUT ce qui a ete mine depuis le debut du job
    minedTotal = stats.blocks,     -- nb total de blocs casses
  }
end

local COLOR = (term and term.isColour and term.isColour()) or false
local STATE_COL = {
  Minage="lime", Depot="orange", Ravitaillement="orange", Retour="cyan",
  Pause="yellow", Termine="green", Erreur="red", Init="lightGray",
}
local function paintT(c) if COLOR and colors then term.setTextColour(colors[c] or colors.white) end end
local function paintB(c) if COLOR and colors then term.setBackgroundColour(colors[c] or colors.black) end end
local function kv(label, value, col)
  paintT("lightGray"); term.write(label)
  paintT(col or "white"); term.write(tostring(value))
end
local function drawBar(frac, width)
  local filled = frac and math.floor(frac*width+0.5) or 0
  if COLOR and colors then
    paintB("green"); term.write(string.rep(" ", filled))
    paintB("gray");  term.write(string.rep(" ", width-filled))
    paintB("black")
  else
    term.write("["..string.rep("=", filled)..string.rep(" ", width-filled).."]")
  end
end
-- Affiche le tableau de bord en direct (appele par la tache UI sur timer)
local function drawHUD()
  if not term then return end
  local w = ({term.getSize()})[1] or 26
  paintB("black"); term.clear(); term.setCursorPos(1,1)
  paintT("white"); term.write("== MINEUR "..(buildState().label or "").." ==")
  local fr = progressFraction()
  term.setCursorPos(1,2); kv("Etat : ", state, STATE_COL[state])
  term.setCursorPos(1,3); kv("Avanc: ", fr and (math.floor(fr*100).."%") or "(profondeur)")
  term.setCursorPos(1,4); drawBar(fr or 0, math.min((w or 26)-2, 22))
  term.setCursorPos(1,5); kv("Temps: ", fmtTime(elapsedSeconds()).."  reste "..fmtTime(etaSeconds()))
  local fp = fuelPctValue()
  term.setCursorPos(1,6); kv("Fuel : ", tostring(turtle.getFuelLevel())..(fp and (" ("..fp.."%)") or ""),
      (fp and fp<15) and "red" or (fp and fp<40) and "yellow" or "lime")
  term.setCursorPos(1,7); kv("Inv  : ", invUsedPct().."%")
  term.setCursorPos(1,8); kv("Blocs: ", stats.blocks)
  term.setCursorPos(1,9); kv("Miner: ", stats.oresTotal)
  term.setCursorPos(1,10); kv("Pos  : ", ("%d,%d,%d"):format(pos.x,pos.y,pos.z))
  term.setCursorPos(1,11); kv("Dir  : ", dirName(heading))
  term.setCursorPos(1,12); kv("Depot: ", stats.deposits.."  A/R "..stats.trips)
  if statusMsg~="" then
    term.setCursorPos(1,13); paintT("orange"); term.write(statusMsg:sub(1,(w or 26)))
  end
  paintT("white"); paintB("black")
end

-------------------------------------------------------------
-- BILAN (rapport de fin enrichi)
-------------------------------------------------------------
local function report()
  paintB("black"); if term then term.clear(); term.setCursorPos(1,1) end
  paintT("yellow"); print("========= RAPPORT DE FIN =========")
  paintT("white")
  local fuelNow = turtle.getFuelLevel()
  local consumed = (type(stats.fuelStart)=="number" and type(fuelNow)=="number")
                   and math.max(0, stats.fuelStart - fuelNow) or "?"
  local mins = elapsedSeconds()/60
  print("Temps total      : "..fmtTime(elapsedSeconds()))
  print("Distance         : "..stats.distance.." blocs")
  print("Blocs casses     : "..stats.blocks)
  print("Carburant conso. : "..tostring(consumed))
  print("Depots / A-R     : "..stats.deposits.." / "..stats.trips)
  print(("Rendement        : %.1f blocs/min"):format(mins>0 and stats.blocks/mins or 0))
  paintT("lime"); print("---- Minerais recuperes ("..stats.oresTotal..") ----")
  paintT("white")
  local any=false
  for name,n in pairs(stats.ores) do print(("  %4dx %s"):format(n, name)); any=true end
  if not any then print("  (aucun)") end
end

-- retour final au point de depart (tous les modes)
local function returnHome(j)
  state="Retour"; statusMsg="Retour au point de depart"
  goToStart()
  if j.deposit=="home" then                 -- depot final dans le coffre arriere
    face(2)                                 -- coffre de vidage (arriere du depart)
    for s=1,16 do local d=turtle.getItemDetail(s)
      if d and isDepositable(d.name) then turtle.select(s); turtle.drop() end end
    face(0)
    turtle.select(1)
  end
end

-------------------------------------------------------------
-- CONTROLE (pause/retour/arret) + RESEAU (suivi & commandes)
-------------------------------------------------------------
local net   -- module minenet si present (sinon nil = pas de reseau, minage normal)
local function loadNet()
  local ok, m = pcall(require, "minenet")
  if not (ok and type(m)=="table") then        -- repli : chemin relatif au programme
    local prog = shell and shell.getRunningProgram and shell.getRunningProgram()
    local dir  = (prog and fs.getDir) and fs.getDir(prog) or ""
    local path = (dir~="" and (dir.."/") or "").."minenet.lua"
    if fs.exists(path) then ok, m = pcall(dofile, path) end
  end
  if ok and type(m)=="table" then
    net = m
    if net.openModem then net.openModem() end   -- ouvre le modem sans fil si dispo
  end
end

-- (assignation de la declaration anticipee) : pause / retour / arret a chaque cellule
function controlCheck()
  if paused then
    while paused and not stopRequested and not homeRequested and not aborted do
      state="Pause"; os.sleep(0.2)
    end
    if not (homeRequested or stopRequested or aborted) then state="Minage" end
  end
  if homeRequested or stopRequested then aborted = true end
end

-- applique une commande recue de la tablette
local function handleCommand(cmd)
  if     cmd=="pause"   then paused=true
  elseif cmd=="resume"  then paused=false
  elseif cmd=="return"  then homeRequested=true; paused=false
  elseif cmd=="stop"    then stopRequested=true; paused=false
  elseif cmd=="restart" then saveState(); os.reboot()
  elseif cmd=="stats"   then if net then net.sendState(buildState()) end
  elseif cmd=="inv"     then
    if net then
      local data = buildInventory()
      if net.sendInventory then
        net.sendInventory(data)
      else
        -- repli : ancien minenet.lua sans sendInventory -> on diffuse nous-memes
        data.type = "inv"
        rednet.broadcast(data, net.PROTOCOL or "turtlemine")
      end
    end
  end
end

-- tache parallele : HUD + diffusion d'etat (~1 Hz) + ecoute des commandes
local HUD_PERIOD = 0.6
local function uiNetTask()
  local timer = os.startTimer(HUD_PERIOD)
  while true do
    local ev = { os.pullEvent() }
    if ev[1]=="timer" and ev[2]==timer then
      drawHUD()
      if net then net.sendState(buildState()) end
      timer = os.startTimer(HUD_PERIOD)
    elseif ev[1]=="rednet_message" then
      local msg = ev[3]
      local myId = os.getComputerID and os.getComputerID()
      if type(msg)=="table" and msg.type=="cmd"
         and (msg.target=="all" or msg.target==myId) then
        -- pcall : une commande qui echoue ne doit JAMAIS tuer le minage
        local ok, err = pcall(handleCommand, msg.cmd)
        if not ok then statusMsg = "Cmd '"..tostring(msg.cmd).."' erreur: "..tostring(err) end
      end
    end
  end
end

-------------------------------------------------------------
-- MENU INTERACTIF [5]
-------------------------------------------------------------
local function menu()
  term.clear(); term.setCursorPos(1,1)
  print("=================================")
  print("     Tortue de minage  v3")
  print("=================================")
  print("Mode :  1) Tunnel   2) Excavatrice")
  local m
  repeat write("Choix [1]: "); local r=read(); if r=="" then r="1" end; m=tonumber(r) until m==1 or m==2
  local j = {}
  if m==1 then
    j.mode="tunnel"
    j.length = askNum("Longueur", 20)
    j.width  = askNum("Largeur (centree)", 1)
    j.height = askNum("Hauteur (blocs)", 3)
    j.progress = { i=0 }
  else
    j.mode="excavate"
    j.length = askNum("Longueur (vers l'avant)", 8)
    j.width  = askNum("Largeur (centree)", 8)
    j.depth  = askNum("Profondeur (couches, 0 = jusqu'a la bedrock)", 4)
    if j.depth <= 0 then j.bedrock = true; j.depth = nil end
    j.progress = { layer=0 }
  end
  j.vein = yesno("Suivre les veines de minerai ?", "o")
  print("Que conserver ?")
  print("  1) Seulement les minerais")
  print("  2) Tout recuperer")
  print("  3) Ne rien recuperer (creuser uniquement)")
  local k
  repeat write("Choix [1]: "); local r=read(); if r=="" then r="1" end; k=tonumber(r) until k==1 or k==2 or k==3
  j.keep = (k==2 and "all") or (k==3 and "none") or "ores"
  print("Depot quand plein :")
  print("  1) Aucun (surplus jete)")
  print("  2) Coffre de l'Ender (sur place)")
  print("  3) Coffre de vidage a l'ARRIERE du depart")
  print("     (en tunnel : + coffre carburant a GAUCHE)")
  local d
  repeat write("Choix [2]: "); local r=read(); if r=="" then r="2" end; d=tonumber(r) until d==1 or d==2 or d==3
  j.deposit = (d==1 and "off") or (d==2 and "ender") or "home"
  return j
end

-------------------------------------------------------------
-- POINT D'ENTREE
-------------------------------------------------------------
local args = { ... }

-- [4] Reprise ?  ("mine resume" reprend sans poser de question : demarrage auto)
local autoResume = (args[1]=="resume")
if fs.exists(STATE_FILE) then
  local h=fs.open(STATE_FILE,"r"); local data=h.readAll(); h.close()
  local st = textutils.unserialize(data)
  if st then
    print("Tache precedente : "..describe(st))
    if autoResume or yesno("Reprendre cette tache ?", "o") then
      job = st
      pos     = job.pos or { x=0,y=0,z=0 }
      heading = job.heading or 0
      trail   = job.trail or {}
      if job.stats then stats = job.stats end   -- reprend les compteurs
      resumed = true
    else
      clearState()
    end
  end
end

-- Sinon : arguments ou menu
if not job then
  if autoResume then print("Aucune tache a reprendre."); return end
  local keep = "ores"                     -- "tout"->all, "rien"/"none"->none
  for _,a in ipairs(args) do
    if     a=="tout" or a=="all" or a=="nofilter" then keep="all"
    elseif a=="rien" or a=="none" then keep="none" end
  end
  if args[1]=="tunnel" and tonumber(args[2]) then
    job = { mode="tunnel", length=tonumber(args[2]), height=tonumber(args[3]) or 3,
            width=tonumber(args[4]) or 1, keep=keep,
            vein=VEIN_MINE, deposit=DEFAULT_DEPOSIT, progress={ i=0 } }
  elseif args[1]=="excavate" and tonumber(args[2]) and tonumber(args[3]) and tonumber(args[4]) then
    local d = tonumber(args[4])
    job = { mode="excavate", length=tonumber(args[2]), width=tonumber(args[3]),
            depth = (d>0 and d or nil), bedrock = (d<=0), keep=keep,
            vein=VEIN_MINE, deposit=DEFAULT_DEPOSIT, progress={ layer=0 } }
  else
    job = menu()
  end
end

if not checkFuel(job) then print("Annule."); return end
if not (job.mode=="tunnel" and job.deposit=="home") then
  if not ensureFuel() then return end       -- le mode tunnel+coffres fait son plein tout seul
end

-- Init de session : drapeaux, compteurs, reseau
aborted=false; paused=false; homeRequested=false; stopRequested=false
stats.mined = stats.mined or {}   -- reprise d'une ancienne sauvegarde sans ce champ
stats.ores  = stats.ores  or {}
stats.startClock = os.clock()
if not resumed then
  stats.fuelStart = (turtle.getFuelLevel()=="unlimited") and 0 or turtle.getFuelLevel()
end
loadNet()

-- Tache de minage : le nettoyage / retour se fait dedans pour que le HUD continue a vivre
local function miningTask()
  if job.mode=="tunnel" then runTunnel(job) else runExcavate(job) end
  if stopRequested then
    state="Termine"; statusMsg="Arret demande (reprise possible)"   -- on garde .mine_state
  else
    if not aborted then cleanInventory() end          -- jette les dechets sur place
    if RETURN_HOME or homeRequested then returnHome(job) end
    clearState()
    state="Termine"
    statusMsg = homeRequested and "Retour demande : termine"
             or (aborted and "Arrete (carburant)") or "Mission terminee"
  end
end

-- Minage + interface/reseau en parallele ; se termine quand le minage rend la main
parallel.waitForAny(miningTask, uiNetTask)

-- Affichage / diffusion finale, puis rapport
drawHUD()
if net then net.sendState(buildState(true)) end
report()
