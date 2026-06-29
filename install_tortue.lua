--[[============================================================
  install_tortue.lua  —  Installe le systeme de minage sur une TORTUE
  ------------------------------------------------------------
  Telecharge : minenet.lua + mine.lua + startup.lua (reprise auto)
  A lancer SUR LA TORTUE (HTTP doit etre active).

    wget https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/install_tortue.lua install_tortue.lua
    install_tortue
============================================================]]--

local BASE  = "https://raw.githubusercontent.com/LaZiiZaa/turtlemine/main/"
local FILES = {
  { "minenet.lua", "minenet.lua", "module reseau" },
  { "mine.lua",    "mine.lua",    "programme de minage" },
  { "startup.lua", "startup.lua", "demarrage auto (reprise)" },
}

-------------------------------------------------------------
local COLOR = term.isColour and term.isColour()
local function c(col) if COLOR and colors then term.setTextColour(colors[col] or colors.white) end end
local function ok(m)  c("lime"); print(m); c("white") end
local function err(m) c("red");  print(m); c("white") end

term.clear(); term.setCursorPos(1,1)
c("cyan"); print("== Installation : TORTUE de minage =="); c("white")

if not turtle then err("Ce script doit etre lance sur une TORTUE.") return end
if not http   then err("HTTP est desactive (active-le dans la config de CC).") return end

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
ok("Tortue installee ! Redemarrage dans 3 s (Ctrl+T annule)...")
sleep(3); os.reboot()
