--[[============================================================
  startup.lua  —  Demarrage automatique de la tortue de minage
  ------------------------------------------------------------
  S'execute tout seul a chaque allumage / redemarrage de la tortue.

  - Si une tache de minage est en cours (fichier .mine_state),
    elle est REPRISE automatiquement, sans rien demander.
    (utile apres un redemarrage serveur, un rechargement de chunk,
     ou la commande "restart" envoyee depuis la tablette remote.lua)

  - Sinon, la tortue laisse la main : tape "mine" pour ouvrir le menu.

  Pose ce fichier a la racine de la tortue, a cote de mine.lua.
============================================================]]--

if fs.exists(".mine_state") then
  print("Tache de minage detectee : reprise automatique...")
  sleep(1)                       -- laisse le monde / les peripheriques se stabiliser
  shell.run("mine", "resume")    -- reprend sans poser de question
else
  print("Tortue de minage prete.")
  print("Tape 'mine' pour demarrer (ou 'mine tunnel 50').")
end
