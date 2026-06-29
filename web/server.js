/* ============================================================
   server.js — Serveur du tableau de bord des tortues de minage
   ------------------------------------------------------------
   Zero dependance (juste Node.js). Il fait 3 choses :
     - POST /update : recoit le JSON envoye par webbridge.lua (CC)
     - GET  /events : flux SSE qui pousse les stats au navigateur
     - GET  /       : sert le tableau de bord (HTML/CSS/JS ci-dessous)

   Lancer :   node server.js        (port 3000 par defaut)
              PORT=8080 node server.js
   Ouvrir :   http://localhost:3000
   ============================================================ */

const http = require("http");
const PORT = process.env.PORT || 3000;

let latest = { turtles: [], time: Date.now() };
const clients = new Set(); // connexions SSE (navigateurs)

function broadcast() {
  const payload = `data: ${JSON.stringify(latest)}\n\n`;
  for (const res of clients) {
    try { res.write(payload); } catch (_) { clients.delete(res); }
  }
}

const server = http.createServer((req, res) => {
  // --- Reception des stats depuis CC (webbridge.lua) ---
  if (req.method === "POST" && req.url === "/update") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      try {
        const data = JSON.parse(body);
        latest = { turtles: data.turtles || [], time: Date.now() };
        broadcast();
      } catch (e) { /* JSON invalide : on ignore */ }
      res.writeHead(204).end();
    });
    return;
  }

  // --- Flux temps reel pour le navigateur (Server-Sent Events) ---
  if (req.method === "GET" && req.url === "/events") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    res.write(`data: ${JSON.stringify(latest)}\n\n`); // etat initial
    clients.add(res);
    req.on("close", () => clients.delete(res));
    return;
  }

  // --- Tableau de bord ---
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(HTML);
});

server.listen(PORT, () => {
  console.log(`Tableau de bord : http://localhost:${PORT}`);
  console.log(`CC doit POSTer sur : http://<cette-machine>:${PORT}/update`);
});

/* ------------------------------------------------------------
   Tableau de bord (page unique)
   ------------------------------------------------------------ */
const HTML = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mineuses — temps réel</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: system-ui, Segoe UI, Roboto, sans-serif;
         background:#0d1117; color:#e6edf3; }
  header { padding:16px 20px; border-bottom:1px solid #21262d;
           display:flex; align-items:center; gap:12px; position:sticky; top:0;
           background:#0d1117; z-index:1; }
  header h1 { font-size:18px; margin:0; font-weight:600; }
  .dot { width:9px; height:9px; border-radius:50%; background:#3fb950; }
  .dot.stale { background:#f85149; }
  #meta { margin-left:auto; color:#8b949e; font-size:13px; }
  main { padding:20px; display:grid; gap:16px;
         grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); }
  .card { background:#161b22; border:1px solid #21262d; border-radius:12px;
          padding:16px; }
  .card.offline { opacity:.55; }
  .row { display:flex; align-items:center; justify-content:space-between; gap:8px; }
  .name { font-weight:600; font-size:16px; }
  .badge { font-size:12px; padding:2px 8px; border-radius:999px;
           background:#30363d; color:#e6edf3; white-space:nowrap; }
  .label { color:#8b949e; font-size:12px; margin:10px 0 4px; }
  .bar { height:14px; background:#30363d; border-radius:7px; overflow:hidden; }
  .bar > span { display:block; height:100%; width:0;
                transition:width .4s ease, background .4s; }
  .stats { display:grid; grid-template-columns:1fr 1fr; gap:6px 14px;
           margin-top:12px; font-size:13px; }
  .stats b { color:#e6edf3; font-weight:600; }
  .stats span { color:#8b949e; }
  .status { margin-top:10px; font-size:13px; color:#d29922; min-height:1em; }
  #empty { color:#8b949e; padding:40px; text-align:center; grid-column:1/-1; }
</style>
</head>
<body>
<header>
  <span class="dot" id="live"></span>
  <h1>Tortues de minage</h1>
  <span id="meta">connexion…</span>
</header>
<main id="grid"><div id="empty">En attente de données… (webbridge.lua + une tortue en minage)</div></main>

<script>
const STATE_COLORS = {
  Minage:"#3fb950", Depot:"#d29922", Ravitaillement:"#d29922", Retour:"#58a6ff",
  Pause:"#e3b341", Termine:"#3fb950", Erreur:"#f85149", Init:"#8b949e"
};
function fmtTime(s){
  if(s==null) return "?";
  s=Math.floor(s); const m=Math.floor(s/60);
  if(m>=60){ const h=Math.floor(m/60); return h+"h"+String(m%60).padStart(2,"0"); }
  return m+"m"+String(s%60).padStart(2,"0")+"s";
}
function fuelColor(p){ return p==null?"#3fb950": p<15?"#f85149": p<40?"#e3b341":"#3fb950"; }

function card(t){
  const c = document.createElement("div");
  c.className = "card" + (t.online===false ? " offline":"");
  const sc = STATE_COLORS[t.state] || "#8b949e";
  const pct = t.pct;
  const fuelPct = t.fuelPct;
  c.innerHTML = \`
    <div class="row">
      <span class="name">\${t.label || ("#"+t.id)}</span>
      <span class="badge" style="background:\${sc}22;color:\${sc}">\${t.state||"?"}\${t.online===false?" • hors ligne":""}</span>
    </div>
    <div class="label">Progression \${pct!=null?pct+"%":"(profondeur)"}</div>
    <div class="bar"><span style="width:\${pct!=null?pct:0}%;background:#3fb950"></span></div>
    <div class="label">Fuel \${t.fuel}\${fuelPct!=null?" • "+fuelPct+"%":" (illimité)"}</div>
    <div class="bar"><span style="width:\${fuelPct!=null?fuelPct:100}%;background:\${fuelColor(fuelPct)}"></span></div>
    <div class="stats">
      <div><span>Inv</span> <b>\${t.invPct!=null?t.invPct+"%":"?"}</b></div>
      <div><span>Reste</span> <b>\${t.distRemaining!=null?t.distRemaining+" blocs":"?"}</b></div>
      <div><span>Blocs</span> <b>\${t.blocks??"?"}</b></div>
      <div><span>Minerais</span> <b>\${t.ores??"?"}</b></div>
      <div><span>Temps</span> <b>\${fmtTime(t.elapsed)}</b></div>
      <div><span>ETA</span> <b>\${fmtTime(t.eta)}</b></div>
    </div>
    <div class="status">\${t.statusMsg||""}</div>\`;
  return c;
}

function render(data){
  const grid = document.getElementById("grid");
  const list = (data.turtles||[]).slice().sort((a,b)=>(a.id||0)-(b.id||0));
  grid.innerHTML = "";
  if(!list.length){
    grid.innerHTML = '<div id="empty">En attente de données…</div>'; return;
  }
  for(const t of list) grid.appendChild(card(t));
  const age = Math.round((Date.now()-(data.time||Date.now()))/1000);
  document.getElementById("meta").textContent =
    list.length + " tortue(s) • maj il y a " + age + "s";
}

const es = new EventSource("/events");
es.onmessage = e => { render(JSON.parse(e.data)); document.getElementById("live").classList.remove("stale"); };
es.onerror = () => { document.getElementById("live").classList.add("stale");
                     document.getElementById("meta").textContent = "reconnexion…"; };
</script>
</body>
</html>`;
