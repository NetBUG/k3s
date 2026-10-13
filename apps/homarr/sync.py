#!/usr/bin/env python3
"""Apply panel.yaml to Homarr through its API.

    HOMARR_API_KEY=... UNIFI_CLOUD_URL=... ./sync.py [--dry-run]

Variables can also live in a gitignored .env next to this script
(KEY=value lines); real environment variables take precedence.

Apps are matched by name and created or updated in place. Each board in
panel.yaml is created if missing and its content is replaced wholesale, so
the result does not depend on what the UI did in between. Boards and apps
not named in panel.yaml are left alone.

Section and item ids are derived from board/group/app names, so a re-run
produces byte-identical content.
"""
import argparse
import hashlib
import json
import math
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
TILE = {"base": 2, "mobile": 1}  # tile width in grid columns per layout role


class Homarr:
    def __init__(self, url, key, dry_run):
        self.url, self.key, self.dry_run = url.rstrip("/"), key, dry_run

    def call(self, method, path, body=None):
        if self.dry_run and method != "GET":
            print(f"  [dry-run] {method} {path}")
            return None
        req = urllib.request.Request(
            self.url + path,
            method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={
                "ApiKey": self.key,
                "Content-Type": "application/json",
                # Cloudflare answers 1010 to the default Python-urllib agent.
                "User-Agent": "homarr-sync/1",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                text = r.read().decode()
        except urllib.error.HTTPError as e:
            sys.exit(f"{method} {path}: HTTP {e.code}: {e.read().decode()[:500]}")
        return json.loads(text) if text else None

    def board(self, name):
        q = urllib.parse.quote(json.dumps({"json": {"name": name}}))
        return self.call("GET", f"/api/trpc/board.getBoardByName?input={q}")["result"]["data"]["json"]


def stable_id(*parts):
    digest = hashlib.sha256("\n".join(parts).encode()).digest()
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
    return "".join(alphabet[b % 36] for b in digest[:24])


def substitute(value):
    def repl(m):
        if m.group(1) not in os.environ:
            sys.exit(f"panel.yaml needs ${{{m.group(1)}}} in the environment")
        return os.environ[m.group(1)]

    return re.sub(r"\$\{([A-Z0-9_]+)\}", repl, value)


def sync_apps(api, panel):
    existing = {a["name"]: a for a in api.call("GET", "/api/apps")}
    ids = {}
    for name, spec in panel["apps"].items():
        want = {
            "name": name,
            "description": spec.get("description"),
            "iconUrl": f"{panel['icons']}/{spec['icon']}.svg",
            "href": substitute(spec["href"]),
            "pingUrl": spec.get("ping"),
        }
        have = existing.get(name)
        if have is None:
            print(f"app {name}: create")
            created = api.call("POST", "/api/apps", want)
            ids[name] = created["appId"] if created else f"<new:{name}>"
        elif any(have.get(k) != v for k, v in want.items()):
            print(f"app {name}: update")
            api.call("PATCH", f"/api/apps/{have['id']}", want)
            ids[name] = have["id"]
        else:
            print(f"app {name}: ok")
            ids[name] = have["id"]
    return ids


def build_content(board_name, board, groups, app_ids):
    root = next(s["id"] for s in board["sections"] if s["kind"] == "empty")
    layouts = {l["role"]: l for l in board["layouts"] if l["role"] in TILE}
    sections, items = [{"id": root, "kind": "empty", "xOffset": 0, "yOffset": 0}], []
    y = {role: 0 for role in layouts}
    for title, apps in groups.items():
        sid = stable_id(board_name, "section", title)
        sec_layouts = []
        for role, lay in layouts.items():
            cols, w = lay["columnCount"], TILE[role]
            per_row = cols // w
            height = max(1, math.ceil(len(apps) / per_row))
            sec_layouts.append({"layoutId": lay["id"], "xOffset": 0, "yOffset": y[role],
                                "width": cols, "height": height, "parentSectionId": root})
            y[role] += height
        sections.append({"id": sid, "kind": "container", "collapsed": False,
                         "options": {"title": title, "showLabel": True}, "layouts": sec_layouts})
        for i, app in enumerate(apps):
            item_layouts = []
            for role, lay in layouts.items():
                w = TILE[role]
                per_row = lay["columnCount"] // w
                item_layouts.append({"layoutId": lay["id"], "sectionId": sid, "width": w, "height": 1,
                                     "xOffset": (i % per_row) * w, "yOffset": i // per_row})
            items.append({"id": stable_id(board_name, "item", title, app), "kind": "app",
                          "options": {"appId": app_ids[app]}, "integrationIds": [],
                          "advancedOptions": {"title": None, "customCssClasses": [], "borderColor": ""},
                          "layouts": item_layouts})
    return {"sections": sections, "items": items}


def sync_boards(api, panel, app_ids):
    existing = {b["name"]: b for b in api.call("GET", "/api/boards")}
    board_ids = {}
    for name, spec in panel["boards"].items():
        unknown = {a for apps in spec["groups"].values() for a in apps} - set(panel["apps"])
        if unknown:
            sys.exit(f"board {name}: unknown apps {sorted(unknown)}")
        have = existing.get(name)
        if have is None:
            print(f"board {name}: create")
            created = api.call("POST", "/api/boards", {"name": name, "columnCount": 12, "isPublic": spec["public"]})
            if created is None:
                board_ids[name] = f"<new:{name}>"
                continue
        elif have["isPublic"] != spec["public"]:
            print(f"board {name}: visibility -> {'public' if spec['public'] else 'private'}")
            api.call("PATCH", f"/api/boards/{have['id']}/visibility",
                     {"visibility": "public" if spec["public"] else "private"})
        board = api.board(name)
        board_ids[name] = board["id"]
        content = build_content(name, board, spec["groups"], app_ids)
        print(f"board {name}: content {len(content['sections']) - 1} groups, {len(content['items'])} tiles")
        api.call("PUT", f"/api/boards/{board['id']}/content", content)
    return board_ids


def sync_home(api, panel, board_ids):
    anon, user = board_ids[panel["home"]["anonymous"]], board_ids[panel["home"]["user"]]
    print(f"home: anonymous -> {panel['home']['anonymous']}, user -> {panel['home']['user']}")
    api.call("PATCH", "/api/settings/board", {"homeBoardId": anon, "mobileHomeBoardId": anon})
    api.call("PATCH", f"/api/boards/{user}/home", {})
    api.call("PATCH", f"/api/boards/{user}/mobile-home", {})


def load_env_file(path):
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip("'\""))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="read only; print the writes it would make")
    ap.add_argument("--panel", default=HERE / "panel.yaml", type=Path)
    args = ap.parse_args()
    load_env_file(HERE / ".env")
    key = os.environ.get("HOMARR_API_KEY") or sys.exit("HOMARR_API_KEY is not set")
    api = Homarr(os.environ.get("HOMARR_URL", "https://home.nb3.me"), key, args.dry_run)
    panel = yaml.safe_load(args.panel.read_text())
    app_ids = sync_apps(api, panel)
    board_ids = sync_boards(api, panel, app_ids)
    sync_home(api, panel, board_ids)


if __name__ == "__main__":
    main()
