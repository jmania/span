from __future__ import annotations

import csv
import json
import threading
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Summit Network Review</title>
<style>
:root{font-family:Inter,ui-sans-serif,system-ui,sans-serif;color:#16231e;background:#eef2ed}
body{margin:0}.shell{max-width:860px;margin:4rem auto;padding:0 1.25rem}.eyebrow{color:#537064;font-size:.8rem;letter-spacing:.12em;text-transform:uppercase}.card{background:#fff;border:1px solid #dbe3dd;border-radius:22px;padding:2rem;box-shadow:0 18px 50px #163b2414}h1{font-size:2rem;margin:.4rem 0}.details{color:#587067;min-height:1.5rem}.progress{height:7px;background:#e6ece8;border-radius:20px;overflow:hidden;margin:1.5rem 0}.bar{height:100%;background:#e9734b;width:0}.query{font:600 1.05rem ui-monospace,SFMono-Regular,monospace;background:#f4f6f3;padding:1rem;border-radius:12px;margin:1rem 0}.actions{display:flex;flex-wrap:wrap;gap:.7rem;margin-top:1.25rem}button,a.button{border:0;border-radius:10px;padding:.8rem 1rem;font-weight:700;cursor:pointer;text-decoration:none;color:#16231e;background:#dce7df}.primary{background:#e9734b!important;color:#fff!important}.degree{background:#183d2d!important;color:#fff!important}.meta{display:flex;justify-content:space-between;color:#708079;font-size:.9rem}.note{margin-top:1.5rem;color:#718078;font-size:.88rem;line-height:1.5}.done{text-align:center;padding:3rem 0}</style></head>
<body><main class="shell"><p class="eyebrow">Private, local review</p><section class="card" id="card"></section></main>
<script>
let rows=[], current=0;
async function init(){rows=await (await fetch('/api/rows')).json(); const pending=rows.findIndex(r=>r.degree==='review'||r.degree==='skip'); current=pending===-1?rows.length:pending; render()}
function searchText(r){return [r.name,r.details].filter(Boolean).join(' ')}
function render(){const c=document.querySelector('#card'); if(current>=rows.length){c.innerHTML='<div class="done"><h1>Review complete</h1><p>Your CSV has been updated. You can close this tab.</p></div>';return}
 const r=rows[current], done=rows.filter(x=>!['review','skip',''].includes(x.degree)).length;
 c.innerHTML=`<div class="meta"><span>${current+1} of ${rows.length}</span><span>${done} classified</span></div><div class="progress"><div class="bar" style="width:${done/rows.length*100}%"></div></div><h1>${esc(r.name)}</h1><p class="details">${esc(r.details||'No company or title in the event list')}</p><div class="query">${esc(searchText(r))}</div><div class="actions"><button class="primary" onclick="copyQuery()">Copy search text</button><a class="button" href="https://www.linkedin.com/" target="_blank" rel="noreferrer">Open LinkedIn</a></div><div class="actions"><button class="degree" onclick="classify('2nd')">2nd degree</button><button onclick="classify('not_connected')">Not connected</button><button onclick="classify('skip')">Skip</button><button onclick="classify('1st')">Correct to 1st</button></div><p class="note">Paste the search text into LinkedIn’s own search. This page never reads LinkedIn, stores credentials, or sends attendee data anywhere.</p>`}
function esc(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
async function copyQuery(){await navigator.clipboard.writeText(searchText(rows[current]));}
async function classify(degree){const response=await fetch('/api/classify',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({index:current,degree})}); if(!response.ok){alert(await response.text());return} rows[current].degree=degree; do{current++}while(current<rows.length&&!['review','skip',''].includes(rows[current].degree));render()}
init();
</script></body></html>"""


class ReviewStore:
    def __init__(self, path: Path):
        self.path = path
        self.lock = threading.Lock()
        with path.open(newline="", encoding="utf-8-sig") as source:
            reader = csv.DictReader(source)
            self.fieldnames = reader.fieldnames or []
            self.rows = list(reader)
        if not self.rows or "degree" not in self.fieldnames:
            raise ValueError("Run the match command first; the review CSV is missing degree")

    def classify(self, index: int, degree: str) -> None:
        if degree not in {"1st", "2nd", "not_connected", "skip"}:
            raise ValueError("Unsupported classification")
        with self.lock:
            if index < 0 or index >= len(self.rows):
                raise IndexError("Row is out of range")
            self.rows[index]["degree"] = degree
            self.rows[index]["reviewed_at"] = datetime.now(timezone.utc).isoformat()
            temporary = self.path.with_suffix(self.path.suffix + ".tmp")
            with temporary.open("w", newline="", encoding="utf-8") as destination:
                writer = csv.DictWriter(destination, fieldnames=self.fieldnames)
                writer.writeheader()
                writer.writerows(self.rows)
            temporary.replace(self.path)


def make_handler(store: ReviewStore):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/":
                self.respond(PAGE.encode(), "text/html; charset=utf-8")
            elif path == "/api/rows":
                self.respond(json.dumps(store.rows).encode(), "application/json")
            else:
                self.send_error(404)

        def do_POST(self):
            if urlparse(self.path).path != "/api/classify":
                self.send_error(404)
                return
            try:
                length = int(self.headers.get("content-length", "0"))
                data = json.loads(self.rfile.read(length))
                store.classify(int(data["index"]), str(data["degree"]))
                self.respond(b'{"ok":true}', "application/json")
            except (ValueError, KeyError, IndexError, json.JSONDecodeError) as exc:
                self.send_error(400, str(exc))

        def respond(self, body: bytes, content_type: str):
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            return

    return Handler


def serve_review(path: Path, port: int = 0, open_browser: bool = True) -> None:
    store = ReviewStore(path)
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(store))
    url = f"http://127.0.0.1:{server.server_port}/"
    print(f"Reviewing {path}\nOpen {url}\nPress Control-C when finished.")
    if open_browser:
        threading.Timer(0.25, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nSaved. Review server stopped.")
    finally:
        server.server_close()
