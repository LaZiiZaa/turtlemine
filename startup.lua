--[[============================================================
  startup.lua  —  Demarrage COMMUN (tortue / tablette / ordinateur)
  ------------------------------------------------------------
  Meme fichier sur tous les appareils :

  - Tortue avec une tache de minage en cours (.mine_state) :
    REPRISE automatique du minage (apres reboot serveur, rechargement
    de chunk, ou commande "restart" depuis la tablette). La tortue
    ne s'arrete pas pour rien demander.

  - Sinon : ouvre le MENU de gestion (menu.lua) d'ou l'on peut
    lancer le programme, mettre a jour, reinstaller, supprimer...

  Installe par install_tortue / install_tablette / install_ordinateur.
============================================================]]--

if turtle and fs.exists(".mine_state") then
  print("Tache de minage detectee : reprise automatique...")
  sleep(1)                       -- laisse le monde / les peripheriques se stabiliser
  shell.run("mine", "resume")    -- reprend sans poser de question
  -- a la fin du job, on enchaine sur le menu ci-dessous (hub : relancer, attendre...)
end

if fs.exists("menu.lua") or fs.exists("menu") then
  shell.run("menu")

else
  print("menu.lua introuvable.")
  print("Relance l'installateur :")
  print("  install_tortue / install_tablette / install_ordinateur")
end
