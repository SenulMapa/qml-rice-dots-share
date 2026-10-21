#!/usr/bin/env python3
"""Local review server for icon picks. 127.0.0.1:7820 only. Picks persist immediately to picks.json.
Usage: picker.py [--port 7820]   (never opens a browser; visit http://127.0.0.1:7820/ yourself)"""
import argparse, json, os, sys, io, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from PIL import Image

PAGE = """<!doctype html><meta charset=utf-8><title>mac-icons picker</title>
<link rel=stylesheet href=/picker.css><h2>Mac icon picker</h2>
<p>Click to pick. Unpicked apps use the first candidate (auto: official, then Mac App Store, then macOSicons, then plated Papirus). Saved instantly to picks.json.</p>
<div id=root></div><script src=/picker.js></script>"""

CSS = """body{background:#16171b;color:#ddd;font:14px system-ui;margin:20px}
.app{margin:0 0 18px;padding:12px;background:#1f2026;border-radius:12px}
.app h3{margin:0 0 8px;font-weight:600}.app small{color:#888}
.row{display:flex;flex-wrap:wrap;gap:10px}
.c{width:104px;padding:6px;border:2px solid transparent;border-radius:12px;cursor:pointer;text-align:center;font-size:11px;color:#999}
.c img{width:96px;height:96px;object-fit:contain;display:block;margin:0 auto 4px}.c.sel{border-color:#4da3ff;background:#2a3140}
.c.auto{border-color:#3a3f4d}"""

# All third-party strings (app names, candidate names) are only ever set via textContent / properties.
JS = r"""
let S;
async function load(){S=await (await fetch('/api/state')).json();render()}
function sel(a,i){const p=S.picks[a.id];if(p&&p.source=='papirus')return i==-1;if(p&&p.url)return a.cands.findIndex(c=>c.url==p.url)==i;return false}
function auto(a,i){return !S.picks[a.id]&&((a.cands.length&&i==0)||(!a.cands.length&&i==-1))}
async function post(body){await fetch('/api/pick',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)})}
async function pick(a,i){const pk=i==-1?{source:'papirus'}:{source:a.cands[i].source,url:a.cands[i].url,name:a.name};
 await post({id:a.id,pick:pk});S.picks[a.id]=pk;render()}
async function clear_(a){await post({id:a.id,pick:null});delete S.picks[a.id];render()}
const el=(t,cls,txt)=>{const e=document.createElement(t);if(cls)e.className=cls;if(txt!==undefined)e.textContent=txt;return e};
function render(){const r=document.getElementById('root');r.replaceChildren();for(const a of S.apps){
 const d=el('div','app');const h=el('h3',null,a.name+' ');h.append(el('small',null,a.id));d.append(h);
 const row=el('div','row');
 const mk=(i,src,label)=>{const c=el('div','c'+(sel(a,i)?' sel':'')+(auto(a,i)?' auto':''));
  const im=document.createElement('img');im.loading='lazy';im.src=src;c.append(im,document.createTextNode(label));c.onclick=()=>pick(a,i);row.append(c)};
 a.cands.forEach((c,i)=>mk(i,'/thumb?id='+encodeURIComponent(a.id)+'&i='+i,'['+c.source+'] '+(c.appName||'')+(i==0?' (auto)':'')));
 mk(-1,'/plate?id='+encodeURIComponent(a.id),'keep Papirus (plated)'+(a.cands.length?'':' (auto)'));
 if(S.picks[a.id]){const b=el('button',null,'reset to auto');b.onclick=()=>clear_(a);row.append(b)}
 d.append(row);r.append(d)}}
load()
"""

class H(BaseHTTPRequestHandler):
    server_version = "picker"
    def log_message(self, *a): pass
    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        if isinstance(body, str): body = body.encode()
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body))); self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; base-uri 'none'; form-action 'none'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers(); self.wfile.write(body)
    def _host_ok(self):
        return self.headers.get("Host", "") in ("127.0.0.1:%d" % self.server.server_port, "localhost:%d" % self.server.server_port)
    def _app(self, id_):
        return next((a for a in lib.load_apps() if a["id"] == id_), None)
    def do_GET(self):
        if not self._host_ok(): return self._send(403, "bad host")
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        if u.path == "/": return self._send(200, PAGE)
        if u.path == "/picker.js": return self._send(200, JS, "text/javascript; charset=utf-8")
        if u.path == "/picker.css": return self._send(200, CSS, "text/css; charset=utf-8")
        if u.path == "/api/state":
            apps = [{"id": a["id"], "name": a["name"] or a["id"], "cands": lib.candidates_for(a)} for a in lib.load_apps()]
            return self._send(200, json.dumps({"apps": apps, "picks": lib.load_picks()}), "application/json")
        app = self._app((q.get("id") or [""])[0])
        if u.path == "/thumb" and app:
            try:
                c = lib.candidates_for(app)[int(q["i"][0])]
                p = lib.download(c["url"], lib.url_cache_path(c["url"]), sha256=c.get("sha256"))
                im = Image.open(lib.to_png(p)).convert("RGBA"); im.thumbnail((192, 192))
                b = io.BytesIO(); im.save(b, "PNG")
                return self._send(200, b.getvalue(), "image/png")
            except Exception:
                return self._send(404, "x")
        if u.path == "/plate" and app:
            try:
                import plate
                for n in lib.icon_names_for(app):
                    s = lib.find_icon(n)
                    if s:
                        b = io.BytesIO(); plate.plate_icon(s).resize((192, 192)).save(b, "PNG")
                        return self._send(200, b.getvalue(), "image/png")
            except Exception:
                pass
            return self._send(404, "x")
        self._send(404, "nf")
    def do_POST(self):
        if not self._host_ok() or self.path != "/api/pick": return self._send(403, "no")
        if "application/json" not in self.headers.get("Content-Type", ""): return self._send(415, "json only")
        try:
            n = int(self.headers.get("Content-Length", "0"))
            d = json.loads(self.rfile.read(min(n, 65536)))
            id_, pick = d["id"], d["pick"]
        except Exception:
            return self._send(400, "bad")
        if not self._app(id_): return self._send(404, "unknown app")
        picks = lib.load_picks()
        if pick is None:
            picks.pop(id_, None)
        elif pick.get("source") == "papirus":
            picks[id_] = {"source": "papirus"}
        elif (pick.get("source") in ("macosicons-official", "official", "itunes", "macosicons") and
              pick.get("url") in {c["url"] for c in lib.candidates_for(self._app(id_))}) or \
             (pick.get("source") == "url" and lib.url_allowed(pick.get("url"), lib.ALL_IMAGE_HOSTS)):
            picks[id_] = {k: pick[k] for k in ("source", "url", "name") if k in pick}
            sha = next((c.get("sha256") for c in lib.candidates_for(self._app(id_)) if c["url"] == pick["url"]), None)
            if sha: picks[id_]["sha256"] = sha
        else:
            return self._send(400, "bad pick")
        lib.save_json(lib.PICKS, picks)
        self._send(200, "{}", "application/json")

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--port", type=int, default=7820)
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    print("picker on http://127.0.0.1:%d/  (Ctrl-C to stop)" % a.port, flush=True)
    try: srv.serve_forever()
    except KeyboardInterrupt: pass
