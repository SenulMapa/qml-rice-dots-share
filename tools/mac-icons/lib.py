"""Shared helpers for the mac-icons pipeline (run scripts with python3 -I)."""
import configparser, glob, hashlib, http.client, ipaddress, json, os, re, socket, ssl, subprocess, sys, tempfile, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "qml-rice", "mac-icons")
PICKS = os.path.join(HERE, "picks.json")
OFFICIAL = os.path.join(HERE, "official_sources.json")
APPS_JSON = os.path.join(CACHE, "apps.json")
CAND_DIR = os.path.join(CACHE, "candidates")
IMG_DIR = os.path.join(CACHE, "images")
MASTER_DIR = os.path.join(CACHE, "masters")
SIZES = [16, 22, 24, 32, 48, 64, 96, 128, 256, 512]
API_BASE = os.environ.get("MACOSICONS_API_BASE", "https://api.macosicons.com/api/v1")
# Host allowlists: exact hostnames, or ".suffix" entries (match any subdomain on a '.' boundary, never the bare suffix).
ALLOWED_HOSTS = ("api.macosicons.com", "macosicons.com", "s3-new.macosicons.com", "s3.macosicons.com")  # macOSicons API + image CDN
ITUNES_API_HOSTS = ("itunes.apple.com",)
ITUNES_HOSTS = (".mzstatic.com",)            # is1-ssl.mzstatic.com etc. (artwork CDN)
OFFICIAL_HOSTS = ("raw.githubusercontent.com", "github.com")
ALL_IMAGE_HOSTS = ALLOWED_HOSTS + ITUNES_HOSTS + OFFICIAL_HOSTS
SOURCES = ("macosicons-official", "official", "itunes", "macosicons", "url")
MAX_BYTES = 20 * 1024 * 1024

# canonical icon name -> extra names the same app is known by
ALIAS_GROUPS = [
    ["spotify", "spotify-client", "com.spotify.Client", "spotify-launcher"],
    ["discord", "Discord", "com.discordapp.Discord"],
    ["vesktop", "dev.vencord.Vesktop"], ["webcord"],
    ["slack", "com.slack.Slack", "Slack"],
    ["code", "visual-studio-code", "vscode", "com.visualstudio.code", "code-oss", "code-url-handler"],
    ["brave-browser", "brave", "com.brave.Browser", "brave-desktop", "Brave-browser"],
    ["kitty", "kitty-open", "net.kovidgoyal.kitty"],
    ["zen", "zen-browser", "zen-alpha", "zen-twilight", "app.zen_browser.zen"],
    ["firefox", "org.mozilla.firefox"],
    ["thunar", "org.xfce.thunar", "Thunar"],
    ["telegram", "org.telegram.desktop", "telegram-desktop", "org.telegram.desktop.desktop"],
]

def norm(s):
    return re.sub(r"[^a-z0-9]+", "", (s or "").lower())

def alias_names(name):
    out = set()
    for g in ALIAS_GROUPS:
        if norm(name) in {norm(x) for x in g}:
            out.update(g)
    return out

def app_dirs():
    return [os.path.join(HOME, ".local/share/applications"),
            os.path.join(HOME, ".local/share/flatpak/exports/share/applications"),
            "/var/lib/flatpak/exports/share/applications",
            "/usr/share/applications"]

def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default

def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)

def icon_names_for(app):
    """Every theme name this app's icon should be installed under."""
    names = set()
    ic = app.get("icon") or ""
    if ic and not ic.startswith("/"):
        names.add(ic)
    elif ic:
        names.add(os.path.splitext(os.path.basename(ic))[0])
    stem = app["id"][:-8] if app["id"].endswith(".desktop") else app["id"]
    if not stem.startswith("class:"):
        names.add(stem)
    wm = app.get("wmclass")
    if wm:
        names.update({wm, wm.lower()})
    for n in list(names):
        names.update(alias_names(n))
    return sorted(n for n in names if n and "/" not in n)

def load_apps():
    apps = load_json(APPS_JSON, None)
    if apps is None:
        sys.exit("apps.json missing in %s -- run scan.py first" % CACHE)
    return apps

def load_picks():
    return load_json(PICKS, {})

class FetchError(ValueError):
    pass

def url_allowed(url, hosts):
    """True iff url is https, has no userinfo/odd chars/non-default port, and its host matches the allowlist exactly
    (or is a subdomain of a '.suffix' entry on a dot boundary)."""
    try:
        if not isinstance(url, str) or re.search(r"[\x00-\x20\x7f\\]", url):
            return False
        p = urllib.parse.urlsplit(url)
        host = p.hostname
        if p.scheme != "https" or not host or "@" in p.netloc or p.port not in (None, 443):
            return False
        host = host.lower()
        if host.endswith("."):
            return False
        for h in hosts:
            if h.startswith("."):
                if host.endswith(h) and len(host) > len(h):
                    return True
            elif host == h:
                return True
        return False
    except ValueError:
        return False

def host_ok(url, hosts=None):
    return url_allowed(url, hosts or ALL_IMAGE_HOSTS)

def _resolve(host):
    return [ai[4][0] for ai in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)]

def _public_ips(host):
    ips = _resolve(host)
    if not ips:
        raise FetchError("no address for %s" % host)
    for ip in ips:
        a = ipaddress.ip_address(ip.split("%")[0])
        if isinstance(a, ipaddress.IPv6Address) and a.ipv4_mapped:
            a = a.ipv4_mapped
        if not a.is_global or a.is_multicast:
            raise FetchError("host %s resolves to non-public address %s" % (host, ip))
    return ips

class _PinnedHTTPS(http.client.HTTPSConnection):
    """Connect to an already-validated IP but verify TLS against the hostname (defeats DNS rebinding)."""
    def __init__(self, host, ip, timeout):
        super().__init__(host, 443, timeout=timeout, context=ssl.create_default_context())
        self._ip = ip
    def connect(self):
        sock = socket.create_connection((self._ip, 443), self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)

def _http(host, ip, method, target, headers, body, timeout, max_bytes):
    """One request, no redirect following. Returns (status, headers dict(lower), body bytes). Patched in tests."""
    c = _PinnedHTTPS(host, ip, timeout)
    try:
        c.request(method, target, body=body, headers=headers)
        r = c.getresponse()
        hd = {k.lower(): v for k, v in r.getheaders()}
        if 300 <= r.status < 400:
            return r.status, hd, b""
        if int(hd.get("content-length", "0") or 0) > max_bytes:
            raise FetchError("response too large")
        return r.status, hd, r.read(max_bytes + 1)
    finally:
        c.close()

def _sha(data):
    return hashlib.sha256(data).hexdigest()

def safe_fetch(url, allowed_hosts, max_bytes=MAX_BYTES, expect_sha256=None, *, data=None, method=None, headers=None,
               timeout=30, cache_path=None):
    """The ONLY network entry point. Fail-closed: any problem raises, nothing unverified is ever returned or cached.
    https only, exact host allowlist, no userinfo/ports, manual redirects (<=3, each re-validated), public IPs only,
    size cap, optional pinned sha256 verified on download AND on every cache read."""
    if expect_sha256 is not None and not re.fullmatch(r"[0-9a-f]{64}", str(expect_sha256)):
        raise FetchError("malformed expect_sha256")
    if cache_path and os.path.exists(cache_path):
        try:
            with open(cache_path, "rb") as f:
                cached = f.read(max_bytes + 1)
            ok = 0 < len(cached) <= max_bytes and (expect_sha256 is None or _sha(cached) == expect_sha256)
        except Exception:
            ok = False
        if ok:
            return cached
        try:
            os.unlink(cache_path)
        except OSError:
            pass
        if expect_sha256 is not None:
            raise FetchError("cache integrity check failed for %s (entry removed)" % os.path.basename(cache_path))
    cur, hops = url, 0
    hdrs = dict(headers or {}); hdrs.setdefault("User-Agent", "qml-rice-mac-icons/1")
    while True:
        if not url_allowed(cur, allowed_hosts):
            raise FetchError("refusing url %r" % cur)
        p = urllib.parse.urlsplit(cur)
        host = p.hostname.lower()
        ip = _public_ips(host)[0]
        target = (p.path or "/") + ("?" + p.query if p.query else "")
        status, rh, body = _http(host, ip, method or ("POST" if data is not None else "GET"), target,
                                 dict(hdrs, Host=host), data, timeout, max_bytes)
        if 300 <= status < 400:
            hops += 1
            loc = rh.get("location")
            if not loc or hops > 3:
                raise FetchError("bad or too many redirects")
            cur = urllib.parse.urljoin(cur, loc)
            continue
        if status != 200:
            raise FetchError("HTTP %s" % status)
        break
    if len(body) > max_bytes:
        raise FetchError("response too large")
    if expect_sha256 is not None and _sha(body) != expect_sha256:
        raise FetchError("sha256 mismatch")
    if cache_path:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(cache_path + ".part", "wb") as f:
            f.write(body)
        os.replace(cache_path + ".part", cache_path)
    return body

def download(url, dest, hosts=None, sha256=None):
    """Fetch an image into the cache via safe_fetch (allowlist, integrity, cached reads re-verified)."""
    safe_fetch(url, hosts or ALL_IMAGE_HOSTS, MAX_BYTES, sha256, cache_path=dest)
    return dest

def url_cache_path(url):
    import hashlib
    return os.path.join(IMG_DIR, hashlib.sha256(url.encode()).hexdigest()[:24] + ".img")

def app_slug(app_id):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", app_id)

def app_name_clean(app):
    return re.sub(r"\s*\([^)]*\)\s*$", "", app.get("name") or "").strip()

def official_for(app):
    stem = app["id"][:-8] if app["id"].endswith(".desktop") else app["id"]
    ic = app.get("icon") or ""
    # deliberately NOT alias-expanded: discord's alias group contains vesktop, whose icon is a different app's
    names = {norm(os.path.splitext(os.path.basename(ic))[0] if ic.startswith("/") else ic), norm(stem),
             norm(app_name_clean(app)), norm(app.get("wmclass"))}
    names.discard("")
    out = []
    for e in lib_manifest().get("entries", []):
        if e.get("sha256") and names & {norm(x) for x in e["aliases"] + [e["id"]]}:
            out.append({"source": "official", "url": e["url"], "appName": e["name"], "sha256": e["sha256"]})
    return out

def lib_manifest():
    return load_json(OFFICIAL, {"entries": []})

def candidates_for(app):
    """Ranked: macosicons-official (site "Official icons" section) > official > itunes (Mac App Store) > macosicons (only exists with a key) ; plate fallback is implicit."""
    slug = app_slug(app["id"])
    mac = [dict(c, source="macosicons") for c in load_json(os.path.join(CAND_DIR, slug + ".json"), {}).get("candidates", [])]
    it = [dict(c, source="itunes") for c in load_json(os.path.join(CAND_DIR, slug + ".itunes.json"), {}).get("candidates", [])]
    seen, out = set(), []
    pg = [dict(c, source="macosicons-official") for c in
          load_json(os.path.join(CAND_DIR, slug + ".official-page.json"), {}).get("candidates", []) if c.get("sha256")]
    for c in pg + official_for(app) + it + mac:
        if c["url"] not in seen:
            seen.add(c["url"]); out.append(c)
    return out

def to_png(path):
    """Return a PNG/JPEG path Pillow can read. .icns -> largest embedded size; svg -> rsvg. Raises on anything else."""
    head = open(path, "rb").read(64)
    if head[:4] == b"icns":
        out = path + ".png"
        if not os.path.exists(out):
            from PIL import Image
            im = Image.open(path)
            w, h, sc = max(((t + (1,))[:3] for t in im.info.get("sizes", [im.size])), key=lambda t: t[0] * t[2])
            im.size = (w * sc, h * sc)
            im.load()
            im.convert("RGBA").save(out)
        return out
    if head[:8] == b"\x89PNG\r\n\x1a\n" or head[:3] == b"\xff\xd8\xff":
        return path
    if b"<svg" in open(path, "rb").read(2048):
        out = path + ".png"
        if not os.path.exists(out):
            subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", "-a", "-o", out, path], check=True, timeout=30)
        return out
    raise ValueError("not an icns/png/jpeg/svg")

# ---- icon lookup in installed themes (for Papirus plating and check) ----
def theme_chain(theme, seen=None):
    seen = seen if seen is not None else []
    if theme in seen:
        return seen
    seen.append(theme)
    for base in ("/usr/share/icons", os.path.join(HOME, ".local/share/icons")):
        idx = os.path.join(base, theme, "index.theme")
        if os.path.exists(idx):
            cp = configparser.RawConfigParser(strict=False); cp.optionxform = str
            try:
                cp.read(idx, encoding="utf-8")
                for p in cp.get("Icon Theme", "Inherits", fallback="").split(","):
                    if p.strip():
                        theme_chain(p.strip(), seen)
            except configparser.Error:
                pass
            break
    return seen

def _size_of(path):
    m = re.search(r"/(\d+)x\d+(@\d)?/", path)
    return int(m.group(1)) if m else (9999 if "/scalable/" in path else 0)

def find_icon(name, themes=("Papirus-Dark",), extra_chain=True):
    """Return path to best raster/svg for icon name, or None."""
    chain = []
    for t in themes:
        theme_chain(t, chain)
    if "hicolor" not in chain:
        chain.append("hicolor")
    for t in chain:
        for base in ("/usr/share/icons", os.path.join(HOME, ".local/share/icons")):
            hits = [p for p in glob.glob(os.path.join(base, t, "*", "apps", name + ".*")) +
                    glob.glob(os.path.join(base, t, "apps", "*", name + ".*"))
                    if p.endswith((".svg", ".png")) and "@2x" not in p]
            if hits:
                hits.sort(key=lambda p: (not p.endswith(".svg"), -min(_size_of(p), 512)))
                return os.path.realpath(hits[0])
    for ext in (".svg", ".png", ".xpm"):
        p = "/usr/share/pixmaps/" + name + ext
        if os.path.exists(p) and ext != ".xpm":
            return p
    return None

def is_resolvable(name, theme_dir=None):
    if theme_dir:
        if glob.glob(os.path.join(theme_dir, "*", "apps", name + ".png")):
            return True
    return find_icon(name, ("Papirus-Dark", "Adwaita")) is not None
