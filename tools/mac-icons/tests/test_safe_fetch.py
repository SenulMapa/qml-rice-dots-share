"""Offline tests for lib.safe_fetch. Run: python3 -I tests/test_safe_fetch.py  (no network; _http/_resolve are mocked)."""
import hashlib, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import lib

GOOD = b"\x89PNG\r\n\x1a\nfake"
H = hashlib.sha256(GOOD).hexdigest()
HOSTS = lib.OFFICIAL_HOSTS

class T(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.dns = {}
        self.routes = {}
        self._h, self._r = lib._http, lib._resolve
        lib._resolve = lambda host: self.dns.get(host, ["93.184.216.34"])
        def fake(host, ip, method, target, headers, body, timeout, max_bytes):
            self.calls.append((host, ip, target))
            return self.routes.get(host, (200, {}, GOOD))
        lib._http = fake
        self.tmp = tempfile.mkdtemp()
    def tearDown(self):
        lib._http, lib._resolve = self._h, self._r

    def refuse(self, url, hosts=HOSTS):
        with self.assertRaises(lib.FetchError, msg=url):
            lib.safe_fetch(url, hosts, 1000)
        self.assertEqual(self.calls, [], url)

    def test_rejects(self):
        for u in ["https://evil-raw.githubusercontent.com/x", "https://evilraw.githubusercontent.com/x",
                  "https://raw.githubusercontent.com.evil.com/x", "https://raw.githubusercontent.com@evil.com/x",
                  "https://user:pw@raw.githubusercontent.com/x", "http://raw.githubusercontent.com/x",
                  "file:///etc/passwd", "ftp://raw.githubusercontent.com/x", "https://raw.githubusercontent.com:8443/x",
                  "https://raw.githubusercontent.com./x", "https://127.0.0.1/x", "https://raw.githubusercontent.com\\@evil.com/x"]:
            self.refuse(u)
        self.refuse("https://evil-apple.com/x", lib.ITUNES_API_HOSTS)
        self.refuse("https://evilmzstatic.com/a.png", lib.ITUNES_HOSTS)
        self.refuse("https://mzstatic.com/a.png", lib.ITUNES_HOSTS)      # bare suffix is not a subdomain
        self.refuse("https://x.mzstatic.com.evil.com/a.png", lib.ITUNES_HOSTS)

    def test_accepts(self):
        self.assertEqual(lib.safe_fetch("https://is1-ssl.mzstatic.com/a.png", lib.ITUNES_HOSTS, 1000), GOOD)
        self.assertEqual(lib.safe_fetch("https://itunes.apple.com/search?term=x", lib.ITUNES_API_HOSTS, 1000), GOOD)

    def test_redirect_to_loopback_and_bad_hosts(self):
        for loc in ["https://127.0.0.1/x", "http://raw.githubusercontent.com/x", "https://evil.com/x", "file:///etc/passwd"]:
            self.routes = {"raw.githubusercontent.com": (302, {"location": loc}, b"")}
            self.calls.clear()
            with self.assertRaises(lib.FetchError, msg=loc):
                lib.safe_fetch("https://raw.githubusercontent.com/a", HOSTS, 1000)
            self.assertEqual(len(self.calls), 1, loc)      # never followed

    def test_redirect_limit_and_allowed_redirect(self):
        self.routes = {"raw.githubusercontent.com": (302, {"location": "/b"}, b"")}
        with self.assertRaises(lib.FetchError):
            lib.safe_fetch("https://raw.githubusercontent.com/a", HOSTS, 1000)
        self.assertEqual(len(self.calls), 4)
        n = [0]
        def fake(host, ip, m, t, h, b, to, mx):
            n[0] += 1
            return (302, {"location": "https://github.com/z"}, b"") if n[0] == 1 else (200, {}, GOOD)
        lib._http = fake
        self.assertEqual(lib.safe_fetch("https://raw.githubusercontent.com/a", HOSTS, 1000), GOOD)

    def test_private_ip_resolution(self):
        for ip in ["127.0.0.1", "10.0.0.5", "169.254.169.254", "192.168.1.1", "::1", "::ffff:127.0.0.1", "0.0.0.0"]:
            self.dns["raw.githubusercontent.com"] = ["93.184.216.34", ip]
            self.refuse("https://raw.githubusercontent.com/x")

    def test_size_cap(self):
        self.routes = {"raw.githubusercontent.com": (200, {}, b"x" * 1001)}
        self.refuse_after("https://raw.githubusercontent.com/x")

    def refuse_after(self, url):
        with self.assertRaises(lib.FetchError):
            lib.safe_fetch(url, HOSTS, 1000)

    def test_sha_download_mismatch_not_cached(self):
        c = os.path.join(self.tmp, "c.img")
        with self.assertRaises(lib.FetchError):
            lib.safe_fetch("https://raw.githubusercontent.com/x", HOSTS, 1000, "0" * 64, cache_path=c)
        self.assertFalse(os.path.exists(c))

    def test_cache_pinned_ok_and_tampered(self):
        c = os.path.join(self.tmp, "c.img")
        open(c, "wb").write(GOOD)
        self.assertEqual(lib.safe_fetch("https://raw.githubusercontent.com/x", HOSTS, 1000, H, cache_path=c), GOOD)
        self.assertEqual(self.calls, [])                 # served from verified cache
        open(c, "wb").write(b"tampered")
        with self.assertRaises(lib.FetchError):
            lib.safe_fetch("https://raw.githubusercontent.com/x", HOSTS, 1000, H, cache_path=c)
        self.assertFalse(os.path.exists(c))              # entry deleted
        self.assertEqual(self.calls, [])                 # no silent refetch / fallback

    def test_cache_read_exception_fails_closed(self):
        c = os.path.join(self.tmp, "dir.img"); os.mkdir(c)   # unreadable as a file
        with self.assertRaises((lib.FetchError, OSError)):
            lib.safe_fetch("https://raw.githubusercontent.com/x", HOSTS, 1000, H, cache_path=c)

    def test_download_wrapper_and_malformed_sha(self):
        with self.assertRaises(lib.FetchError):
            lib.safe_fetch("https://raw.githubusercontent.com/x", HOSTS, 1000, "abc")
        d = os.path.join(self.tmp, "ok.img")
        self.assertEqual(lib.download("https://raw.githubusercontent.com/x", d, HOSTS, H), d)
        self.assertEqual(open(d, "rb").read(), GOOD)
        with self.assertRaises(lib.FetchError):
            lib.download("https://evil.com/x", os.path.join(self.tmp, "e.img"))

    def test_picks_url_allowlist(self):
        self.assertFalse(lib.url_allowed("https://evil.com/a.png", lib.ALL_IMAGE_HOSTS))
        self.assertTrue(lib.url_allowed("https://s3.macosicons.com/a.png", lib.ALL_IMAGE_HOSTS))

if __name__ == "__main__":
    unittest.main()
