--[[============================================================
  webbridge.lua  —  Passerelle CC -> page web (stats temps reel)
  ------------------------------------------------------------
  A lancer sur un ORDINATEUR DEDIE (pas une tortue) equipe d'un
  modem sans fil, dans la portee des tortues, avec l'API HTTP activee.

  Role : ecoute les etats diffuses par les tortues (rednet) et les
  envoie regulierement au serveur web (server.js) en JSON.

  Le navigateur affiche ensuite tout en direct (voir web/server.js).

  Necessite minenet.lua dans le meme dossier.
============================================================]]--

-- >>> A ADAPTER : URL de ton serveur (voir web/server.js) <<<
--   - Serveur local : "http://TON_IP_LAN:3000/update" (PAS localhost cote MC)
--   - Serveur public : "http://mondomaine:3000/update"
local SERVER = "http://127.0.0.1:3000/update"
local PERIOD = 1.5    -- secondes entre deux envois

-------------------------------------------------------------
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
if not net then error("minenet.lua introuvable a cote de webbridge.lua", 0) end
if not http then error("HTTP desactive : active-le dans la config de CC: Tweaked", 0) end
if not net.openModem() then error("Aucun modem sans fil trouve sur cet ordinateur", 0) end

print("== Passerelle web ==")
print("Envoi vers : "..SERVER)
print("En ecoute des tortues... (Ctrl+T pour arreter)")

local turtles = {}                 -- id -> { st = <etat>, last = os.clock() }
local OFFLINE = net.OFFLINE or 4
local sent, fails = 0, 0

local timer = os.startTimer(PERIOD)
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]

  if e == "rednet_message" then
    local msg = ev[3]
    if type(msg)=="table" and msg.type=="state" and msg.id then
      turtles[msg.id] = { st = msg, last = os.clock() }
    end

  elseif e == "timer" and ev[2] == timer then
    timer = os.startTimer(PERIOD)
    local arr = {}
    for _, rec in pairs(turtles) do
      local s = rec.st
      s.online = (os.clock() - rec.last) <= OFFLINE   -- en ligne ?
      arr[#arr+1] = s
    end
    -- envoi non bloquant (on traite la reponse via http_success/failure)
    http.request{
      url     = SERVER,
      method  = "POST",
      body    = textutils.serializeJSON({ turtles = arr, count = #arr }),
      headers = {
        ["Content-Type"] = "application/json",
        -- evite la page d'avertissement de ngrok (sans effet sur un serveur normal)
        ["ngrok-skip-browser-warning"] = "1",
      },
    }
    local _, y = term.getCursorPos()
    term.setCursorPos(1, y)
    term.clearLine()
    io.write(("OK:%d  Echecs:%d  Tortues:%d"):format(sent, fails, #arr))

  elseif e == "http_success" then
    sent = sent + 1
    if ev[3] and ev[3].close then ev[3].close() end

  elseif e == "http_failure" then
    fails = fails + 1
    -- echec ponctuel (serveur eteint, URL bloquee...) : on reessaie au prochain tick
  end
end
