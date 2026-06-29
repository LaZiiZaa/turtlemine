--[[============================================================
  install_ordinateur.lua  —  Installe le poste de controle (ORDINATEUR)
  ------------------------------------------------------------
  Telecharge : minenet.lua + remote.lua + startup (lance remote)
  A lancer SUR UN ORDINATEUR avance, avec un modem sans fil et HTTP
  active. Si un MONITEUR est attache, l'interface s'affichera dessus
  (tactile) ; sinon elle reste sur l'ecran de l'ordinateur.

    wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/install_ordinateur.lua install_ordinateur.lua
    install_ordinateur
============================================================]]--

local BASE  = "https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/"
local FILES = {
  { "minenet.lua",        "minenet.lua", "module reseau" },
  { "remote.lua",         "remote.lua",  "poste de controle" },
  { "startup_remote.lua", "startup.lua", "demarrage auto (remote)" },
}

-------------------------------------------------------------
local COLOR = term.isColour and term.isColour()
local function c(col) if COLOR and colors then term.setTextColour(colors[col] or colors.white) end end
local function ok(m)  c("lime"); print(m); c("white") end
local function err(m) c("red");  print(m); c("white") end

term.clear(); term.setCursorPos(1,1)
c("cyan"); print("== Installation : ORDINATEUR de controle =="); c("white")

if turtle    then err("Ce script est pour un ORDINATEUR, pas une tortue.") return end
if not http  then err("HTTP est desactive (active-le dans la config de CC).") return end

local fails = 0
for _, f in ipairs(FILES) do
  write("- "..f[3].." -> "..f[2].." ... ")
  local url = BASE..f[1].."?cb="..tostring(os.epoch and os.epoch("utc") or os.clock())
  local h = http.get(url)
  if h then
    local data = h.readAll(); h.close()
    local fh = fs.open(f[2], "w"); fh.write(data); fh.close()
    ok("OK ("..#data.." o)")
  else
    err("ECHEC"); fails = fails + 1
  end
end

print()
if fails > 0 then
  err(fails.." fichier(s) en echec. Verifie HTTP et la connexion.")
  return
end
ok("Ordinateur installe ! Redemarrage dans 3 s (Ctrl+T annule)...")
sleep(3); os.reboot()
