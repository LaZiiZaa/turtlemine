--[[============================================================
  install_tablette.lua  —  Installe la tablette de controle (POCKET)
  ------------------------------------------------------------
  Telecharge : minenet.lua + remote.lua + startup (lance remote)
  A lancer SUR LA POCKET COMPUTER (avancee de preference), avec un
  modem sans fil et HTTP active.

    wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/install_tablette.lua install_tablette.lua
    install_tablette
============================================================]]--

local BASE  = "https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/"
local FILES = {
  { "minenet.lua",        "minenet.lua", "module reseau" },
  { "remote.lua",         "remote.lua",  "tablette de controle" },
  { "startup.lua",        "startup.lua", "demarrage commun (menu)" },
  { "menu.lua",           "menu.lua",    "gestionnaire (maj/suppr)" },
}

-------------------------------------------------------------
local COLOR = term.isColour and term.isColour()
local function c(col) if COLOR and colors then term.setTextColour(colors[col] or colors.white) end end
local function ok(m)  c("lime"); print(m); c("white") end
local function err(m) c("red");  print(m); c("white") end

term.clear(); term.setCursorPos(1,1)
c("cyan"); print("== Installation : TABLETTE (pocket) =="); c("white")

if turtle    then err("Ce script est pour une TABLETTE, pas une tortue.") return end
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
ok("Tablette installee ! Redemarrage dans 3 s (Ctrl+T annule)...")
sleep(3); os.reboot()
