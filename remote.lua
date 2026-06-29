--[[============================================================
  remote.lua  —  Tablette de suivi & controle des tortues de minage
  ------------------------------------------------------------
  A lancer sur une Pocket Computer (avancee de preference, pour la
  couleur) ou un ordinateur avec un modem sans fil.

  - Liste en temps reel toutes les tortues qui diffusent leur etat.
  - Vue detail d'une tortue : progression, position, carburant, etc.
  - Commandes : pause / reprise / retour base / arret / stats / restart.
  - Couleur si appareil avance, sinon repli monochrome.
  - Selection a la souris/tactile OU au clavier.

  Necessite minenet.lua dans le meme dossier.
============================================================]]--

-- Chargement du module reseau partage (require, sinon dofile par chemin)
local function loadNet()
  local ok, m = pcall(require, "minenet")
  if not (ok and type(m)=="table") then
    local prog = shell and shell.getRunningProgram and shell.getRunningProgram()
    local dir  = (prog and fs.getDir) and fs.getDir(prog) or ""
    local path = (dir~="" and (dir.."/") or "").."minenet.lua"
    if fs.exists(path) then ok, m = pcall(dofile, path) end
  end
  return (ok and type(m)=="table") and m or nil
end

local net = loadNet()
if not net then print("minenet.lua introuvable !"); return end
if not net.openModem() then
  print("Aucun modem trouve.")
  print("Attache un modem sans fil a cet appareil.")
  return
end

-------------------------------------------------------------
-- Ecran : diffuse sur un moniteur attache s'il y en a un
--   (peripheral.find("monitor") + term.redirect)
--   Sinon, on reste sur l'ecran de l'appareil (Pocket).
-------------------------------------------------------------
local native  = (term.current and term.current()) or term
local monitor = peripheral.find and peripheral.find("monitor")
if monitor then
  pcall(monitor.setTextScale, 0.5)   -- plus de place a l'affichage
  monitor.clear()
  term.redirect(monitor)
end
local function restoreTerm()
  if monitor then term.redirect(native); pcall(monitor.clear) end
end

-------------------------------------------------------------
-- Affichage (couleur + repli monochrome)
-------------------------------------------------------------
local W, H = term.getSize()
local COLOR = term.isColour and term.isColour()
local function pT(c) if COLOR and colors then term.setTextColour(colors[c] or colors.white) end end
local function pB(c) if COLOR and colors then term.setBackgroundColour(colors[c] or colors.black) end end
-- RESPONSIVE : on relit la taille de l'ecran a chaque effacement, donc a
-- chaque affichage. La mise en page s'adapte ainsi a la Pocket comme au mur
-- de moniteurs (ou si le moniteur change de taille/echelle en cours de route).
local function clear()
  W, H = term.getSize()
  pB("black"); pT("white"); term.clear(); term.setCursorPos(1,1)
end

local STATE_COL = {
  Minage="lime", Depot="orange", Ravitaillement="orange", Retour="cyan",
  Pause="yellow", Termine="green", Erreur="red", Init="lightGray",
}
local function dirName(d) return ({[0]="+X (E)",[1]="+Z (S)",[2]="-X (O)",[3]="-Z (N)"})[d] or "?" end
local function fmtTime(s)
  if not s then return "?" end
  s = math.floor(s); local m = math.floor(s/60)
  if m>=60 then return ("%dh%02dm"):format(math.floor(m/60), m%60) end
  return ("%dm%02ds"):format(m, s%60)
end
local function drawBar(frac, width, x, y)
  term.setCursorPos(x, y)
  local filled = math.floor((frac or 0)*width + 0.5)
  if COLOR and colors then
    pB("green"); term.write(string.rep(" ", filled))
    pB("gray");  term.write(string.rep(" ", width-filled)); pB("black")
  else
    term.write("["..string.rep("=", filled)..string.rep(" ", width-filled).."]")
  end
end

-------------------------------------------------------------
-- Donnees : tortues connues (multi-tortues)
-------------------------------------------------------------
local turtles = {}            -- id -> { st = <etat>, last = os.clock() }
local selected = nil          -- id affiche en detail (nil = vue liste)
local feedback = ""           -- message transitoire (commande envoyee...)
local invCache = {}           -- id -> table inventaire recue (type="inv")
local invShown = false        -- true = on affiche l'inventaire de 'selected'
local scroll    = 0           -- defilement de la vue courante (liste / recolte)
local maxScroll = 0           -- borne max de defilement (recalculee a chaque affichage)

local function idList()
  local t = {}
  for id in pairs(turtles) do t[#t+1] = id end
  table.sort(t)
  return t
end
local function online(rec) return (os.clock() - rec.last) <= (net.OFFLINE or 4) end

-------------------------------------------------------------
-- Boutons cliquables (avec repli clavier)
-------------------------------------------------------------
local btns = {}
local function button(x, y, label, cmd, col)
  local w = #label + 2
  btns[#btns+1] = { x=x, y=y, w=w, cmd=cmd }
  pB(COLOR and (col or "gray") or "black"); pT("white")
  term.setCursorPos(x, y); term.write("["..label.."]")
  pB("black"); pT("white")
  return x + w + 1
end
local function hitButton(mx, my)
  for _, b in ipairs(btns) do
    if my==b.y and mx>=b.x and mx < b.x+b.w then return b.cmd end
  end
end

-- Commandes affichees en boutons : { label (avec raccourci), cmd, couleur }
-- "back" = retour a la liste (pas une commande envoyee a la tortue).
local CMDS = {
  { "P:Pause",   "pause",   "orange" },
  { "R:Repr",    "resume",  "green"  },
  { "B:Base",    "return",  "cyan"   },
  { "S:Stop",    "stop",    "red"      },
  { "X:Stats",   "stats",   "gray"     },
  { "I:Inv",     "inv",     "lightBlue"},
  { "Z:Restart", "restart", "purple"   },
  { "Q:Retour",  "back",    "blue"     },
}

-- Repartit les boutons en rangees selon la largeur dispo (W),
-- pour que rien ne deborde ni ne se chevauche sur un grand ecran.
local function layoutRows(defs)
  local rows, cur, x = {}, {}, 1
  for _, d in ipairs(defs) do
    local w = #d[1] + 2                    -- largeur du bouton "[label]"
    if #cur > 0 and x + w - 1 > W then      -- plus la place -> rangee suivante
      rows[#rows+1] = cur; cur = {}; x = 1
    end
    cur[#cur+1] = d
    x = x + w + 1                           -- +1 espace entre deux boutons
  end
  if #cur > 0 then rows[#rows+1] = cur end
  return rows
end

-- Pied de page commun : boutons de defilement tactiles (si la liste depasse)
-- + texte d'aide + indicateur de position. 'total' et 'vis' servent juste a
-- afficher "x-y/total". Responsive : se replie si l'ecran est etroit.
local function drawFooter(hint, total, vis)
  pB("black"); pT("white")
  local x = 1
  if maxScroll > 0 then
    x = button(1, H, "^", "scrollup", "gray")
    x = button(x, H, "v", "scrolldn", "gray")
  end
  pT("lightGray"); term.setCursorPos(x, H)
  local txt = " "..hint
  if maxScroll > 0 and total and vis then
    txt = txt.."  ["..(scroll+1).."-"..math.min(total, scroll+vis).."/"..total.."]"
  end
  term.write(txt:sub(1, math.max(0, W - x + 1)))
end

-- Affiche une liste d'entrees { text=, col= } en COLONNES responsives dans la
-- zone [y1..y2], avec defilement vertical (scrollRows = nb de rangees masquees
-- en haut). Le nombre de colonnes s'adapte a la largeur. Met a jour maxScroll
-- et renvoie le scroll effectif (borne).
local function drawColumns(entries, y1, y2, scrollRows)
  local rowsVis = math.max(0, y2 - y1 + 1)
  if rowsVis == 0 or #entries == 0 then maxScroll = 0; return 0 end
  local cw = 1
  for _, e in ipairs(entries) do if #e.text > cw then cw = #e.text end end
  cw = math.min(cw, W)                       -- une cellule ne depasse jamais l'ecran
  local gap   = 2
  local ncols = math.max(1, math.floor((W + gap) / (cw + gap)))
  local total = math.ceil(#entries / ncols)
  maxScroll   = math.max(0, total - rowsVis)
  scrollRows  = math.max(0, math.min(scrollRows, maxScroll))
  for r = 1, rowsVis do
    local rowIdx = r + scrollRows
    if rowIdx > total then break end
    for c = 1, ncols do
      local e = entries[(rowIdx - 1) * ncols + c]
      if e then
        term.setCursorPos(1 + (c - 1) * (cw + gap), y1 + r - 1)
        pT(e.col or "white"); term.write(e.text:sub(1, cw))
      end
    end
  end
  pT("white")
  return scrollRows
end

-------------------------------------------------------------
-- Vues
-------------------------------------------------------------
local function drawList()
  btns = {}
  clear()
  pB(COLOR and "blue" or "black"); pT("white")
  term.setCursorPos(1,1); term.write((" Tortues de minage"..string.rep(" ", W)):sub(1, W))
  pB("black")
  local list = idList()
  local bodyTop, bodyBottom = 3, H-1          -- zone de liste (defilable)
  local rowsVis = math.max(0, bodyBottom - bodyTop + 1)
  maxScroll = math.max(0, #list - rowsVis)
  scroll = math.max(0, math.min(scroll, maxScroll))
  if #list==0 then
    pT("lightGray"); term.setCursorPos(1,bodyTop); term.write("(en attente de tortues...)")
  end
  for r = 1, rowsVis do
    local i  = r + scroll
    local id = list[i]
    if not id then break end
    local rec = turtles[id]; local st = rec.st
    local y = bodyTop + r - 1
    btns[#btns+1] = { x=1, y=y, w=W, cmd="sel:"..id }   -- toute la ligne cliquable
    term.setCursorPos(1, y)
    pT(online(rec) and (STATE_COL[st.state] or "white") or "gray")
    local nm = (st.label or ("#"..id)):sub(1,10)
    term.write((("%d) %-10s %-6s %s"):format(i, nm, st.state or "?", st.pct and (st.pct.."%") or "")):sub(1, W))
  end
  drawFooter("chiffre/clic=detail  Q=quitter", #list, rowsVis)
end

local function drawDetail(id)
  btns = {}
  maxScroll = 0                     -- la vue detail tient sur un ecran (pas de defilement)
  local rec = turtles[id]
  if not rec then selected=nil; return drawList() end
  local st = rec.st
  clear()
  pB(COLOR and "blue" or "black"); pT("white")
  term.setCursorPos(1,1); term.write(((" "..(st.label or ("#"..id)))..string.rep(" ", W)):sub(1, W))
  pB("black")
  pT(online(rec) and (STATE_COL[st.state] or "white") or "gray")
  term.setCursorPos(1,2); term.write("Etat : "..(st.state or "?")..(online(rec) and "" or " [HORS LIGNE]"))
  pT("white")
  term.setCursorPos(1,3); term.write("Avanc: "..(st.pct and (st.pct.."%") or "(profondeur)"))
  drawBar(st.pct and st.pct/100 or 0, math.min(W-2, 22), 1, 4)
  term.setCursorPos(1,5); term.write(("Pos  : %d,%d,%d  %s"):format(st.x or 0, st.y or 0, st.z or 0, dirName(st.dir)))
  local fp = st.fuelPct and (" ("..st.fuelPct.."%)") or ""
  term.setCursorPos(1,6); term.write("Fuel : "..tostring(st.fuel)..fp)
  term.setCursorPos(1,7); term.write("Inv  : "..(st.invPct or 0).."%   Blocs: "..(st.blocks or 0))
  term.setCursorPos(1,8); term.write("Miner: "..(st.ores or 0).."   Reste: "..tostring(st.distRemaining or "?"))
  term.setCursorPos(1,9); term.write("Temps: "..fmtTime(st.elapsed).."  ETA "..fmtTime(st.eta))
  if st.statusMsg and st.statusMsg~="" then
    pT("orange"); term.setCursorPos(1,10); term.write(tostring(st.statusMsg):sub(1, W)); pT("white")
  end
  if feedback~="" then pT("yellow"); term.setCursorPos(1,11); term.write(feedback:sub(1,W)); pT("white") end
  -- Boutons de commande : grille cliquable / tactile qui s'adapte a la largeur.
  -- Chaque bouton a sa propre zone de clic (pas de chevauchement) et son
  -- raccourci clavier (la 1re lettre du label).
  local rows = layoutRows(CMDS)
  local startY = math.max(2, H - #rows)        -- ancre en bas de l'ecran
  for i, row in ipairs(rows) do
    local y, x = startY + (i-1), 1
    for _, d in ipairs(row) do x = button(x, y, d[1], d[2], d[3]) end
  end
  pT("lightGray"); term.setCursorPos(1, H)
  term.write(("clic = bouton   |   lettre = raccourci"):sub(1, W))
end

-- nom court d'objet : enleve le prefixe de mod ("minecraft:diamond" -> "diamond")
local function shortName(n) return (tostring(n):gsub("^[%w_]+:", "")) end
-- heuristique "c'est un minerai ?" (pour le surlignage)
local function isOreName(n)
  n = tostring(n)
  return (n:find("ore", 1, true) or n:find("raw_", 1, true) or n:find("debris", 1, true)) ~= nil
end

-- Vue "Recolte" : TOUT ce que la tortue a mine depuis le debut du job
-- (cumul au moment du minage -> inclut ce qui a deja ete depose/jete).
-- Liste complete (scrollable) en colonnes responsives + resume detaille.
local function drawInventory(id)
  btns = {}
  local rec = turtles[id]
  local st  = rec and rec.st
  clear()
  pB(COLOR and "blue" or "black"); pT("white")
  term.setCursorPos(1,1)
  term.write((" Recolte "..((st and st.label) or ("#"..id))..string.rep(" ", W)):sub(1, W))
  pB("black"); pT("white")
  local inv = invCache[id]
  if not inv then
    maxScroll = 0
    pT("lightGray"); term.setCursorPos(1,3); term.write("Demande envoyee, attente...")
  else
    local mined = inv.mined or {}
    local order, oresTot = {}, 0
    for name in pairs(mined) do order[#order+1] = name end
    table.sort(order, function(a,b) return mined[a] > mined[b] end)        -- + abondant d'abord
    for _, name in ipairs(order) do if isOreName(name) then oresTot = oresTot + mined[name] end end
    -- resume detaille (ligne 2)
    pT("lightGray"); term.setCursorPos(1,2)
    term.write((("Blocs %d  Minerais %d  Types %d  Fuel %s")
      :format(inv.minedTotal or 0, oresTot, #order, tostring(inv.fuel))):sub(1, W))
    pT("white")
    if #order==0 then
      maxScroll = 0
      pT("lightGray"); term.setCursorPos(1,4); term.write("(rien mine pour l'instant)")
    else
      local entries = {}
      for _, name in ipairs(order) do
        entries[#entries+1] = {
          text = ("%5dx %s"):format(mined[name], shortName(name)),
          col  = isOreName(name) and "yellow" or "white",
        }
      end
      scroll = drawColumns(entries, 4, H-1, scroll)   -- corps defilable, colonnes auto
    end
  end
  -- Pied de page (libelles compacts pour tenir meme sur une Pocket etroite).
  local x = button(1, H, "Actu", "inv", "green")
  x = button(x, H, "Ret", "invback", "blue")
  if maxScroll > 0 then                       -- fleches de defilement tactiles
    x = button(x, H, "^", "scrollup", "gray")
    x = button(x, H, "v", "scrolldn", "gray")
  end
  pT("lightGray"); term.setCursorPos(x, H)
  term.write((" R=actu Q=ret"):sub(1, math.max(0, W - x + 1)))
end

local function redraw()
  if selected and invShown then drawInventory(selected)
  elseif selected then drawDetail(selected)
  else drawList() end
end

-------------------------------------------------------------
-- Envoi de commande + boucle d'evenements
-------------------------------------------------------------
local function send(cmd)
  if not selected then return end
  net.sendCommand(selected, cmd)
  feedback = "-> "..cmd.." envoye"
end

local KEYCMD = { p="pause", r="resume", b="return", s="stop", x="stats", z="restart" }

clear(); redraw()
local refresh = os.startTimer(1)
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]

  if e=="rednet_message" then
    local msg = ev[3]
    if type(msg)=="table" and msg.id then
      if msg.type=="state" then
        turtles[msg.id] = { st = msg, last = os.clock() }
        redraw()
      elseif msg.type=="inv" then
        invCache[msg.id] = msg
        if selected==msg.id and invShown then redraw() end
      end
    end

  elseif e=="timer" and ev[2]==refresh then
    refresh = os.startTimer(1)
    redraw()                       -- rafraichit (passage hors-ligne, ETA...)

  elseif e=="char" then
    local c = ev[2]:lower()
    if c=="q" then
      if invShown then invShown=false; scroll=0; feedback=""; redraw()      -- recolte -> detail
      elseif selected then selected=nil; invShown=false; scroll=0; feedback=""; redraw()
      else restoreTerm(); clear(); print("Au revoir."); return end
    elseif invShown then
      if c=="r" or c=="i" then send("inv"); redraw() end                    -- R = actualiser
    elseif c=="i" and selected then
      invShown=true; scroll=0; send("inv"); redraw()                        -- ouvre la recolte
    elseif selected then
      if KEYCMD[c] then send(KEYCMD[c]); redraw() end
    else
      local n = tonumber(ev[2]); local list = idList()
      if n and list[n] then selected = list[n]; scroll=0; feedback=""; redraw() end
    end

  elseif e=="key" then
    local k = ev[2]
    if     k==keys.up       then scroll = math.max(0, scroll-1);          redraw()
    elseif k==keys.down     then scroll = math.min(maxScroll, scroll+1);  redraw()
    elseif k==keys.pageUp   then scroll = math.max(0, scroll-5);          redraw()
    elseif k==keys.pageDown then scroll = math.min(maxScroll, scroll+5);  redraw()
    elseif k==keys.backspace then
      if invShown then invShown=false; scroll=0; feedback=""; redraw()
      elseif selected then selected=nil; scroll=0; feedback=""; redraw() end
    end

  elseif e=="mouse_scroll" then
    scroll = math.max(0, math.min(maxScroll, scroll + ev[2]))   -- molette (ev[2] = -1/1)
    redraw()

  elseif e=="mouse_click" or e=="monitor_touch" then
    local cmd = hitButton(ev[3], ev[4])
    if cmd then
      if cmd:sub(1,4)=="sel:" then
        selected = tonumber(cmd:sub(5)); scroll=0; feedback=""; redraw()
      elseif cmd=="back" then
        selected=nil; invShown=false; scroll=0; feedback=""; redraw()      -- Retour -> liste
      elseif cmd=="inv" then
        if not invShown then scroll=0 end                                  -- ouverture: haut ; refresh: garde
        invShown=true; send("inv"); redraw()
      elseif cmd=="invback" then
        invShown=false; scroll=0; feedback=""; redraw()                    -- recolte -> detail
      elseif cmd=="scrollup" then
        scroll = math.max(0, scroll-1); redraw()
      elseif cmd=="scrolldn" then
        scroll = math.min(maxScroll, scroll+1); redraw()
      else
        send(cmd); redraw()
      end
    end
  end
end
