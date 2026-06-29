--[[============================================================
  menu.lua  —  Gestionnaire du systeme de minage
  ------------------------------------------------------------
  Menu interactif (clavier OU souris/tactile) pour :
    - Mettre a jour      : retelecharge et ECRASE (garde les donnees)
    - Reinstallation     : supprime puis retelecharge (propre)
    - Lancer             : demarre le programme (mine / remote)
    - Tout supprimer     : efface les fichiers installes
    - Redemarrer / Quitter

  Detecte tout seul tortue / tablette-ordinateur.

    wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/menu.lua menu.lua
    menu
============================================================]]--

local BASE = "https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/"

local isTurtle = (turtle ~= nil)
-- Fichiers geres pour cet appareil : { source GitHub, destination locale }
local SET = isTurtle and {
  { src="minenet.lua", dst="minenet.lua" },
  { src="mine.lua",    dst="mine.lua" },
  { src="startup.lua", dst="startup.lua" },
} or {
  { src="minenet.lua",        dst="minenet.lua" },
  { src="remote.lua",         dst="remote.lua" },
  { src="startup_remote.lua", dst="startup.lua" },
}
local DEVICE = isTurtle and "TORTUE" or "TABLETTE / ORDI"
local RUNCMD = isTurtle and "mine" or "remote"

-------------------------------------------------------------
-- Couleurs
-------------------------------------------------------------
local COLOR = term.isColour and term.isColour()
local function pT(c) if COLOR and colors then term.setTextColour(colors[c] or colors.white) end end
local function pB(c) if COLOR and colors then term.setBackgroundColour(colors[c] or colors.black) end end
local function reset() pB("black"); pT("white") end

-------------------------------------------------------------
-- Telechargement / fichiers
-------------------------------------------------------------
local function download(src)
  if not http then return nil, "HTTP desactive" end
  local cb = tostring(os.epoch and os.epoch("utc") or os.clock())
  local h = http.get(BASE..src.."?cb="..cb)
  if not h then return nil, "echec telechargement" end
  local d = h.readAll(); h.close()
  return d
end

local function deleteFiles()
  local n = 0
  for _, f in ipairs(SET) do
    if fs.exists(f.dst) then fs.delete(f.dst); n = n + 1 end
  end
  return n
end

local function downloadAll()
  local fails = {}
  for _, f in ipairs(SET) do
    write("  "..f.dst.." ... ")
    local d, e = download(f.src)
    if d then
      local fh = fs.open(f.dst, "w"); fh.write(d); fh.close()
      pT("lime"); print("ok"); reset()
    else
      pT("red"); print("ECHEC"); reset()
      fails[#fails+1] = f.src.." ("..tostring(e)..")"
    end
  end
  return fails
end

-------------------------------------------------------------
-- Petits ecrans utilitaires
-------------------------------------------------------------
local function pause()
  print("")
  pT("lightGray"); print("[ touche ou clic pour revenir ]"); reset()
  while true do
    local e = os.pullEvent()
    if e=="key" or e=="mouse_click" or e=="monitor_touch" or e=="char" then return end
  end
end

local function confirm(msg)
  reset(); term.clear(); term.setCursorPos(1,1)
  pT("orange"); print(msg); reset()
  print("")
  pT("lightGray"); write("Confirmer ? (o/n) : "); reset()
  while true do
    local _, ch = os.pullEvent("char")
    ch = ch:lower()
    if ch=="o" then return true elseif ch=="n" then return false end
  end
end

-------------------------------------------------------------
-- Actions
-------------------------------------------------------------
local function actUpdate()
  reset(); term.clear(); term.setCursorPos(1,1)
  pT("cyan"); print("Mise a jour (ecrase, garde les donnees)"); reset()
  if not http then pT("red"); print("HTTP desactive dans la config CC."); reset(); pause(); return end
  local fails = downloadAll()
  print("")
  if #fails==0 then pT("lime"); print("A jour ! ("..#SET.." fichiers)")
  else pT("red"); print(#fails.." echec(s) :"); for _,m in ipairs(fails) do print("  - "..m) end end
  reset(); pause()
end

local function actReinstall()
  if not confirm("Reinstallation PROPRE : supprime puis retelecharge.") then return end
  reset(); term.clear(); term.setCursorPos(1,1)
  pT("cyan"); print("Suppression..."); reset()
  print("  "..deleteFiles().." fichier(s) supprime(s)")
  pT("cyan"); print("Telechargement..."); reset()
  local fails = downloadAll()
  print("")
  if #fails==0 then pT("lime"); print("Reinstalle ! ("..#SET.." fichiers)")
  else pT("red"); print(#fails.." echec(s).") end
  reset(); pause()
end

local function actRun()
  reset(); term.clear(); term.setCursorPos(1,1)
  if not (fs.exists(RUNCMD) or fs.exists(RUNCMD..".lua")) then
    pT("red"); print(RUNCMD.." n'est pas installe."); reset()
    print("Fais d'abord 'Mettre a jour'.")
    pause(); return
  end
  shell.run(RUNCMD)        -- rend la main au menu quand le programme se termine
end

local function actDelete()
  if not confirm("TOUT SUPPRIMER : efface les fichiers du programme ?") then return end
  reset(); term.clear(); term.setCursorPos(1,1)
  local n = deleteFiles()
  if isTurtle and fs.exists(".mine_state") then fs.delete(".mine_state"); n = n + 1 end
  pT("lime"); print(n.." fichier(s) supprime(s)."); reset()
  pT("lightGray"); print("(le menu lui-meme est conserve)")
  pause()
end

-------------------------------------------------------------
-- Boucle du menu
-------------------------------------------------------------
local running = true
local items = {
  { "Mettre a jour (garde les donnees)", actUpdate },
  { "Reinstallation propre",             actReinstall },
  { "Lancer ("..RUNCMD..")",             actRun },
  { "Tout supprimer",                    actDelete },
  { "Redemarrer",                        function() os.reboot() end },
  { "Quitter",                           function() running = false end },
}

local sel = 1
local function draw()
  local W, H = term.getSize()
  pB("black"); pT("white"); term.clear()
  pB(COLOR and "blue" or "black"); pT("white")
  term.setCursorPos(1,1); term.write((" Gestion minage - "..DEVICE..string.rep(" ", W)):sub(1, W))
  pB("black")
  for i, it in ipairs(items) do
    local y = 2 + i
    term.setCursorPos(1, y)
    if i == sel then
      pB(COLOR and "gray" or "black"); pT(COLOR and "yellow" or "white")
      term.write(((" > "..i..". "..it[1])..string.rep(" ", W)):sub(1, W))
      pB("black")
    else
      pT("white"); term.write(("   "..i..". "..it[1]):sub(1, W))
    end
  end
  reset(); pT("lightGray"); term.setCursorPos(1, H)
  term.write(("fleches+Entree | chiffre | clic"):sub(1, W))
end

local function activate(i)
  sel = i
  items[i][2]()
end

while running do
  draw()
  local ev = { os.pullEvent() }
  local e = ev[1]
  if e == "key" then
    local k = ev[2]
    if     k == keys.up    then sel = (sel - 2) % #items + 1
    elseif k == keys.down  then sel =  sel      % #items + 1
    elseif k == keys.enter then activate(sel) end
  elseif e == "char" then
    local n = tonumber(ev[2])
    if n and items[n] then activate(n)
    elseif ev[2]:lower() == "q" then running = false end
  elseif e == "mouse_click" or e == "monitor_touch" then
    local i = ev[4] - 2                      -- ligne -> index (titre = ligne 1)
    if items[i] then activate(i) end
  end
end

reset(); term.clear(); term.setCursorPos(1,1)
print("Menu ferme.")
