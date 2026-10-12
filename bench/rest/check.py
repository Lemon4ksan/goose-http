"""Checks a REST benchmark server's answers against the generator's dataset
files (task 021), before its load runs, as HttpArena's validate.sh does.

    python3 bench/rest/check.py PORT DATADIR [TIER]    (TIER: a, the default, b, c, or d)

Tier A, HttpArena's production-stack: items and users by id, each with
servedAt within 2 s of now, 404 and 401 where the id or the user is missing,
and writes answered 204, or 422 for a body that isn't an object of name,
price, and quantity.

Tier B, snowtime's k6 hot path: every user's session, timer, 14-day entries,
and projects, member for member and in order; other windows, and an admin's
look at another user's entries; PATCH echoing the description, trimmed;
timer start and stop as of now; and snowtime's errors, from 400 to 409.

Tier C, a clinic's schedule and records: the version as of now; each week's
bookings and shifts, and other ranges and staff, with their counts; a sample
of encounters with their case's notes; every client, and the past visits of
the first 100 and others, at three limits; and 400, 401, and 404.

Tier D, writes with large bodies: each of the generator's imports, attachments,
batches, and forms, sent whole, in large chunks, and in small ones, answered
as this file computes from the body; CSVs, multipart bodies, batches, and
forms that don't validate (400, 422); and 401, 404, 413, and 415.

Exits non-zero with a message on the first failure.
"""

import calendar
import csv
import decimal
import http.client
import io
import json
import os
import random
import re
import socket
import sys
import time
import urllib.parse
import zlib

# A 147-byte token, as long as HttpArena's data/jwt-token.txt.
TOKEN = "Bearer " + "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTc5MDAwMDAwMH0" + "." + "x" * 70


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


class Server:
    def __init__(self, port):
        self.conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)

    def ask(self, method, path, body=None, headers=None):
        h = {"Authorization": TOKEN, "Accept-Encoding": "br;q=1, gzip;q=0.8"}
        h.update(headers or {})
        h = {k: v for k, v in h.items() if v is not None}
        if body is not None:
            h["Content-Type"] = "application/json"
        self.conn.request(method, path, body=body, headers=h)
        r = self.conn.getresponse()
        return r.status, r.getheader("content-type"), r.read()


def record(status, ctype, body, want, what):
    """The response's record, checked against want with servedAt aside."""
    if status != 200 or not (ctype or "").startswith("application/json"):
        fail(f"{what}: {status} {ctype}")
    got = json.loads(body)
    served = got.pop("servedAt", None)
    if not isinstance(served, int) or abs(served - time.time()) > 2:
        fail(f"{what}: servedAt {served!r}")
    if got != want:
        fail(f"{what}: {got} != {want}")


def tier_a(port, data):
    items = json.load(open(os.path.join(data, "arena-items.json")))
    users = json.load(open(os.path.join(data, "arena-users.json")))
    s = Server(port)
    rng = random.Random(1)
    for i in [1, len(items)] + [rng.randint(1, len(items)) for _ in range(200)]:
        record(*s.ask("GET", f"/api/items/{i}"), items[i - 1], f"/api/items/{i}")
    for i in [1, len(users)] + [rng.randint(1, len(users)) for _ in range(50)]:
        record(*s.ask("GET", "/api/me", headers={"X-User-Id": str(i)}), users[i - 1], f"/api/me as {i}")
    for path, headers, want in [(f"/api/items/{len(items) + 1}", {}, 404), ("/api/items/0", {}, 404),
                                ("/api/items/x", {}, 404), ("/api/me", {}, 401),
                                ("/api/me", {"X-User-Id": str(len(users) + 1)}, 401)]:
        status, _, _ = s.ask("GET", path, headers=headers)
        if status != want:
            fail(f"GET {path} {headers}: {status}, want {want}")
    for body, want in [('{"name":"bench-updated","price":250,"quantity":10}', 204), ('{"price":1}', 204),
                       ("{}", 204), ('{"name":5}', 422), ('{"price":"x"}', 422), ("[1]", 422), ("{", 422)]:
        status, _, _ = s.ask("POST", "/api/items/7", body=body)
        if status != want:
            fail(f"POST /api/items/7 {body}: {status}, want {want}")
    print("tier a: ok")


APP_URL = "https://time.bench.example.com"
DAY = 86400000


def iso(ms):
    """ms since the epoch as JavaScript's toISOString writes it."""
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ms // 1000)) + f".{ms % 1000:03d}Z"


def ms_of(s):
    return calendar.timegm(time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")) * 1000 + int(s[20:23] or 0)


def uuid7(ms=None):
    """A uuidv7 as k6's scenario makes one."""
    t = f"{int(time.time() * 1000) if ms is None else ms:012x}"
    h = lambda n: "".join(random.choice("0123456789abcdef") for _ in range(n))
    return f"{t[:8]}-{t[8:]}-7{h(3)}-{random.choice('89ab')}{h(3)}-{h(12)}"


def same(got, want, what):
    """Equal, with the members in the same order."""
    if json.dumps(got) != json.dumps(want):
        fail(f"{what}:\n  got  {json.dumps(got)[:600]}\n  want {json.dumps(want)[:600]}")


class Snow:
    """Tier B's dataset, and what each request should answer from it."""

    def __init__(self, data):
        self.orgs = json.load(open(os.path.join(data, "snow-orgs.json")))
        self.users = json.load(open(os.path.join(data, "snow-users.json")))
        self.entries = json.load(open(os.path.join(data, "snow-entries.json")))
        self.org = {o["id"]: o for o in self.orgs}
        self.entry = {e["id"]: e for e in self.entries}
        self.load = [line.split("\t") for line in open(os.path.join(data, "snow-load.txt")).read().splitlines()]
        self.running = {e["userId"]: e for e in self.entries if e["stoppedAt"] is None}

    def cookie(self, u):
        return {"Cookie": f"__Secure-better-auth.session_token={u['cookie']}; "
                          f"PARAGLIDE_LOCALE={u['settings']['locale']}"}

    def session(self, u):
        orgs = [dict(id=m["id"], name=self.org[m["id"]]["name"], slug=self.org[m["id"]]["slug"],
                     issueLinks=self.org[m["id"]]["issueLinks"], role=m["role"]) for m in u["organizations"]]
        return dict(user=dict(id=u["id"], name=u["name"], email=u["email"], image=u["image"]),
                    signedInAt=u["signedInAt"], organizations=orgs,
                    activeOrganizationId=u["activeOrganizationId"], settings=u["settings"], fill=u["fill"],
                    invitationId=None, appUrl=APP_URL)

    def timer(self, u):
        e = self.running.get(u["id"])
        if e is None:
            return None
        project = None
        if e["projectId"]:
            p = next(p for p in self.org[e["organizationId"]]["projects"] if p["id"] == e["projectId"])
            project = dict(id=p["id"], name=p["name"], color=p["color"])
        return dict(e, project=project)

    def role(self, u, org):
        return next(m["role"] for m in u["organizations"] if m["id"] == org)

    def projects(self, u, org, archived):
        admin = self.role(u, org) in ("owner", "admin")
        teams = u["teamIds"] if org == u["activeOrganizationId"] else []
        return [p for p in self.org[org]["projects"]
                if (archived or p["archivedAt"] is None)
                and (admin or not p["teamIds"] or any(t in teams for t in p["teamIds"]))]

    def listed(self, user_id, org, frm, to):
        f, t = ms_of(frm), ms_of(to)
        got = [e for e in self.entries
               if e["userId"] == user_id and e["organizationId"] == org and ms_of(e["startedAt"]) > f - DAY
               and ms_of(e["startedAt"]) < t and (e["stoppedAt"] is None or ms_of(e["stoppedAt"]) > f)]
        return sorted(got, key=lambda e: e["startedAt"], reverse=True)


def stopped_at(entry, now):
    s = ms_of(entry["startedAt"])
    return min(max(now, s + 1), s + DAY)


def near(got, want, what, slack=2000):
    if abs(ms_of(got) - want) > slack:
        fail(f"{what}: {got}, want about {iso(want)}")


def tier_b(port, data):
    d = Snow(data)
    s = Server(port)
    rng = random.Random(2)

    def ask(method, path, user=None, body=None, origin=True, headers=None):
        h = dict(d.cookie(user)) if user else {}
        if origin and method != "GET":
            h["Origin"] = APP_URL
        h.update(headers or {})
        status, ctype, raw = s.ask(method, path, body=body, headers=h)
        if not (ctype or "").startswith("application/json"):
            fail(f"{method} {path}: {status} {ctype}")
        return status, json.loads(raw)

    def ok(method, path, user=None, body=None):
        status, got = ask(method, path, user, body)
        if status != 200:
            fail(f"{method} {path}: {status} {got}")
        return got

    def refused(method, path, want, user=None, body=None, **kw):
        status, got = ask(method, path, user, body, **kw)
        if status != want or "error" not in got:
            fail(f"{method} {path} {body}: {status} {got}, want {want}")

    for k, u in enumerate(d.users):
        cookie, uid, org, last, frm, to = d.load[k]
        if uid != u["id"] or org != u["activeOrganizationId"] or not cookie.endswith(f"={u['settings']['locale']}"):
            fail(f"snow-load.txt line {k + 1} isn't user {u['id']}'s")
        same(ok("GET", "/api/v1/session", u), d.session(u), f"session of {uid}")
        same(ok("GET", "/api/v1/timer", u), d.timer(u), f"timer of {uid}")
        got = ok("GET", f"/api/v1/organizations/{org}/entries?from={frm}&to={to}&userId={uid}", u)
        same(got, d.listed(uid, org, frm.replace("%3A", ":"), to.replace("%3A", ":")), f"entries of {uid}")
        if not 25 <= len(got) <= 60:
            fail(f"entries of {uid}: {len(got)} in the 14 days")
        for m in u["organizations"]:
            same(ok("GET", f"/api/v1/organizations/{m['id']}/projects?includeArchived=true", u),
                 d.projects(u, m["id"], True), f"projects of {m['id']} for {uid}")
        same(ok("GET", f"/api/v1/organizations/{org}/projects", u), d.projects(u, org, False),
             f"unarchived projects of {org} for {uid}")

    # Other windows, and an admin's look at another user's entries.
    for _ in range(100):
        u = rng.choice(d.users)
        org = u["activeOrganizationId"]
        f = ms_of("2026-08-10T00:00:00.000Z") + rng.randint(0, 60) * DAY + rng.randint(0, DAY)
        t = f + rng.randint(1, 30 * DAY)
        other = rng.choice([v for v in d.users if v["activeOrganizationId"] == org])
        path = f"/api/v1/organizations/{org}/entries?from={iso(f)}&to={iso(t)}&userId={other['id']}"
        if other is u or d.role(u, org) in ("owner", "admin"):
            same(ok("GET", path, u), d.listed(other["id"], org, iso(f), iso(t)), path)
        else:
            refused("GET", path, 403, u)
    u = d.users[0]
    org = u["activeOrganizationId"]
    same(ok("GET", f"/api/v1/organizations/{org}/entries?from=2026-10-01T00:00:00Z&to=2026-10-12T21:00:00Z", u),
         d.listed(u["id"], org, "2026-10-01T00:00:00.000Z", "2026-10-12T21:00:00.000Z"), "entries without userId")

    # PATCH, the edit action's write.
    for k in rng.sample(range(len(d.users)), 40):
        u = d.users[k]
        _, uid, org, last, _, _ = d.load[k]
        for text in [f"Benchmark edit {int(time.time() * 1000)}", '  a "quoted" \\ édit\t ', "", "x" * 500]:
            got = ok("PATCH", f"/api/v1/organizations/{org}/entries/{last}", u, json.dumps({"description": text}))
            same(got, dict(d.entry[last], description=text.strip()), f"PATCH {last} {text!r}")
    k = 3
    u = d.users[k]
    _, uid, org, last, _, _ = d.load[k]
    path = f"/api/v1/organizations/{org}/entries/{last}"
    same(ok("PATCH", path, u, '{"other":1}'), d.entry[last], "PATCH without a description")
    refused("PATCH", path, 400, u, json.dumps({"description": "x" * 501}))
    refused("PATCH", path, 400, u, '{"description":5}')
    refused("PATCH", path, 400, u, "[1]")
    refused("PATCH", path, 400, u, "{")
    refused("PATCH", path, 403, u, '{"description":"x"}', origin=False)
    refused("PATCH", path, 403, u, '{"description":"x"}', headers={"Origin": "https://elsewhere.example.com"})
    refused("PATCH", path, 401, None, '{"description":"x"}')
    refused("PATCH", f"/api/v1/organizations/{org}/entries/{uuid7()}", 404, u, '{"description":"x"}')
    refused("PATCH", f"/api/v1/organizations/{org}/entries/not-a-uuid", 400, u, '{"description":"x"}')
    other_org = next(o["id"] for o in d.orgs if all(m["id"] != o["id"] for m in u["organizations"]))
    refused("PATCH", f"/api/v1/organizations/{other_org}/entries/{last}", 403, u, '{"description":"x"}')
    member = next(v for v in d.users if v["activeOrganizationId"] == org and d.role(v, org) == "member")
    refused("PATCH", path, 403, member, '{"description":"x"}')
    owner = next(v for v in d.users if v["activeOrganizationId"] == org and d.role(v, org) == "owner")
    if owner is not u:
        same(ok("PATCH", path, owner, '{"description":"by the owner"}'),
             dict(d.entry[last], description="by the owner"), "PATCH by the owner")

    # Timer start and stop, for users with a running timer and without.
    runners = [i for i, u in enumerate(d.users) if u["id"] in d.running][:10]
    for k in rng.sample(range(len(d.users)), 60) + runners:
        u = d.users[k]
        _, uid, org, _, _, _ = d.load[k]
        new = uuid7()
        got = ok("POST", f"/api/v1/organizations/{org}/timer/start", u,
                 json.dumps({"id": new, "description": "", "ticket": None, "projectId": None}))
        now = int(time.time() * 1000)
        if list(got) != ["started", "stopped"]:
            fail(f"timer start: {got}")
        near(got["started"].pop("startedAt"), now, "timer start's startedAt")
        same(got["started"], dict(id=new, organizationId=org, userId=uid, projectId=None, description="",
                                  ticket=None, stoppedAt=None), "timer start's started")
        run = d.running.get(uid)
        if run is None:
            same(got["stopped"], None, "timer start's stopped")
        else:
            near(got["stopped"].pop("stoppedAt"), stopped_at(run, now), "timer start's stopped")
            same(got["stopped"], {k: v for k, v in run.items() if k != "stoppedAt"}, "timer start's stopped")
        got = ok("POST", "/api/v1/timer/stop", u, json.dumps({"id": new}))
        near(got.pop("stoppedAt"), now, "timer stop's stoppedAt")
        near(got.pop("startedAt"), now, "timer stop's startedAt")
        same(got, dict(id=new, organizationId=org, userId=uid, projectId=None, description="", ticket=None),
             "timer stop")
        if run is not None:
            got = ok("POST", "/api/v1/timer/stop", u, json.dumps({"id": run["id"]}))
            near(got.pop("stoppedAt"), stopped_at(run, now), "the running timer's stop")
            same(got, {k: v for k, v in run.items() if k != "stoppedAt"}, "the running timer's stop")
    k = 7
    u = d.users[k]
    _, uid, org, last, _, _ = d.load[k]
    start = f"/api/v1/organizations/{org}/timer/start"
    projects = d.projects(u, org, True)
    live = next(p for p in projects if p["archivedAt"] is None)
    got = ok("POST", start, u, json.dumps({"id": uuid7(), "description": "  CORE1-42 work ", "ticket": "CORE1-42",
                                           "projectId": live["id"]}))
    if (got["started"]["description"], got["started"]["ticket"], got["started"]["projectId"]) != (
            "CORE1-42 work", "CORE1-42", live["id"]):
        fail(f"timer start with a project and a ticket: {got['started']}")
    archived = next((p for p in projects if p["archivedAt"] is not None), None)
    if archived:
        refused("POST", start, 409, u, json.dumps({"id": uuid7(), "projectId": archived["id"]}))
    refused("POST", start, 404, u, json.dumps({"id": uuid7(), "projectId": uuid7()}))
    refused("POST", start, 409, u, json.dumps({"id": last}))
    refused("POST", start, 400, u, json.dumps({"id": "nope"}))
    refused("POST", start, 400, u, json.dumps({"id": uuid7(), "ticket": "lower-1"}))
    refused("POST", start, 400, u, json.dumps({"description": "no id"}))
    refused("POST", start, 400, u, "not json")
    refused("POST", start, 403, u, json.dumps({"id": uuid7()}), origin=False)
    refused("POST", f"/api/v1/organizations/{other_org}/timer/start", 403, d.users[3], json.dumps({"id": uuid7()}))
    refused("POST", "/api/v1/timer/stop", 404, u, json.dumps({"id": uuid7(int(time.time() * 1000) - 2 * DAY)}))
    refused("POST", "/api/v1/timer/stop", 404, u, json.dumps({"id": last}))
    refused("POST", "/api/v1/timer/stop", 400, u, json.dumps({"id": 7}))
    refused("POST", "/api/v1/timer/stop", 401, None, json.dumps({"id": uuid7()}))

    # The sign-in, and calls that don't exist or don't validate.
    same(ask("GET", "/api/v1/session")[1], None, "session without a cookie")
    bad = dict(d.users[0], cookie="0" * 64 + ".x")
    same(ask("GET", "/api/v1/session", bad)[1], None, "session of an unknown token")
    refused("GET", "/api/v1/timer", 401)
    refused("GET", "/api/v1/timer", 401, bad)
    refused("GET", f"/api/v1/organizations/{org}/projects", 401)
    refused("GET", "/api/v1/nothing", 404, u)
    refused("DELETE", "/api/v1/session", 404, u)
    for q in ["from=2026-10-01T00:00:00.000Z", "from=x&to=y",
              "from=2026-10-02T00:00:00.000Z&to=2026-10-01T00:00:00.000Z",
              "from=2026-01-01T00:00:00.000Z&to=2026-10-01T00:00:00.000Z",
              "from=2026-10-01T00:00:00.000Z&to=2026-10-02T00:00:00.000Z&userId=42"]:
        refused("GET", f"/api/v1/organizations/{org}/entries?{q}", 400, u)
    refused("GET", f"/api/v1/organizations/{org}/projects?includeArchived=maybe", 400, u)
    refused("GET", f"/api/v1/organizations/{other_org}/projects", 403, d.users[3])
    print("tier b: ok")


NOTE_KINDS = ["intake", "findings", "plan", "internal"]


def tier_c(port, data):
    rd = lambda name: json.load(open(os.path.join(data, name)))
    bookings, shifts = rd("heavy-bookings.json"), rd("heavy-shifts.json")
    encounters, clients = rd("heavy-encounters.json"), rd("heavy-clients.json")
    epoch = rd("heavy-meta.json")["versionEpoch"]
    load = [line.split("\t") for line in open(os.path.join(data, "heavy-load.txt")).read().splitlines()]
    tokens = [f[1] for f in load if f[0] == "token"]
    weeks = [(f[1], f[2]) for f in load if f[0] == "week"]
    s = Server(port)
    rng = random.Random(3)

    def ask(path, auth=True, headers=None):
        h = {"Authorization": "Bearer " + rng.choice(tokens) if auth else None}
        h.update(headers or {})
        status, ctype, raw = s.ask("GET", path, headers=h)
        if not (ctype or "").startswith("application/json"):
            fail(f"GET {path}: {status} {ctype}")
        return status, json.loads(raw)

    def ok(path):
        status, got = ask(path)
        if status != 200:
            fail(f"GET {path}: {status} {got}")
        return got

    def refused(path, want, **kw):
        status, got = ask(path, **kw)
        if status != want or got.get("status") != want:
            fail(f"GET {path}: {status} {got}, want {want}")

    got = ok("/api/v2/schedule/version?since=0")
    v = (int(time.time() * 1000) - epoch) // 60000
    if list(got) != ["version", "changedAt"] or abs(got["version"] - v) > 1 or \
            got["changedAt"] != iso(epoch + got["version"] * 60000):
        fail(f"version: {got}, want about {v}")

    def select(records, start, end, staff, at):
        return [r for r in records if start <= at(r)[:10] < end and r["staff"]["id"] in staff]

    def check_range(start, end, staff):
        q = f"start={start}&end={end}&staff={','.join(map(str, staff))}"
        want = select(bookings, start, end, set(staff), lambda r: r["slot"]["start"])
        same(ok(f"/api/v2/schedule/bookings?{q}"), dict(bookings=want, count=len(want)), f"bookings {q}")
        want = select(shifts, start, end, set(staff), lambda r: r["start"])
        same(ok(f"/api/v2/schedule/shifts?{q}"), dict(shifts=want, count=len(want)), f"shifts {q}")

    for start, end in weeks:
        check_range(start, end, list(range(1, 11)))
    for staff in range(1, 11):
        check_range("2026-09-07", "2026-10-05", [staff])
    days = ["2026-09-%02d" % d for d in range(1, 31)] + ["2026-10-%02d" % d for d in range(1, 10)]
    for _ in range(30):
        a, b = sorted(rng.sample(range(len(days)), 2))
        if b - a <= 31:
            check_range(days[a], days[b], rng.sample(range(1, 11), rng.randint(1, 10)))
    print(f"tier c: version, bookings, and shifts ok")

    by_case = {}
    for e in encounters:
        by_case.setdefault(e["caseId"], []).append(e)
    history = len([e for e in encounters if e["start"] < "2026-09-07"])
    for i in [1, history, history + 1, len(encounters)] + rng.sample(range(1, history + 1), 250) + \
            rng.sample(range(history + 1, len(encounters) + 1), 100):
        e = encounters[i - 1]
        case = [dict(id=n["id"], encounterId=c["id"], kind=k, author=n["author"], text=n["text"], at=n["at"])
                for c in by_case[e["caseId"]] for k in NOTE_KINDS for n in c["notes"][k]]
        same(ok(f"/api/v2/encounters/{i}"), dict(e, caseNotes=case), f"encounter {i}")
    print(f"tier c: encounters ok")

    past = {}
    for e in encounters:
        if e["status"] == "completed":
            past.setdefault(e["client"]["id"], []).append(e)
    for c, client in enumerate(clients, 1):
        same(ok(f"/api/v2/clients/{c}"), client, f"client {c}")
    for c in list(range(1, 101)) + rng.sample(range(101, len(clients) + 1), 50):
        mine = sorted(past.get(c, []), key=lambda e: (e["start"], e["id"]), reverse=True)
        for limit, q in [(20, ""), (20, "?limit=20"), (5, "?limit=5"), (50, "?limit=50")]:
            same(ok(f"/api/v2/clients/{c}/encounters{q}"), dict(items=mine[:limit], total=len(mine)),
                 f"client {c}'s encounters{q}")
    print(f"tier c: clients ok")

    week = "start=2026-09-07&end=2026-09-14&staff=1,2,3"
    refused("/api/v2/schedule/version?since=0", 401, auth=False)
    refused("/api/v2/clients/1", 401, auth=False, headers={"Authorization": "Bearer abc"})
    refused("/api/v2/clients/1", 401, auth=False, headers={"Authorization": "Basic YTpi"})
    refused("/api/v2/nothing", 404)
    for path in [f"/api/v2/encounters/{len(encounters) + 1}", "/api/v2/encounters/0", "/api/v2/encounters/x",
                 f"/api/v2/clients/{len(clients) + 1}", f"/api/v2/clients/{len(clients) + 1}/encounters"]:
        refused(path, 404)
    for q in ["since=", "since=x", "since=-1", ""]:
        refused(f"/api/v2/schedule/version?{q}", 400)
    for q in ["start=2026-09-07&end=2026-09-07&staff=1", "start=2026-09-01&end=2026-10-05&staff=1",
              "start=2026-09-07&end=2026-09-14&staff=", "start=2026-09-07&end=2026-09-14&staff=11",
              "start=2026-09-07&end=2026-09-14&staff=1,x", "start=2026-09-07&staff=1", "start=7&end=8&staff=1",
              "end=2026-09-14&staff=1", "start=2026-09-07&end=2026-09-14"]:
        refused(f"/api/v2/schedule/bookings?{q}", 400)
        refused(f"/api/v2/schedule/shifts?{q}", 400)
    for q in ["limit=0", "limit=51", "limit=x"]:
        refused(f"/api/v2/clients/1/encounters?{q}", 400)
    same(ok(f"/api/v2/schedule/bookings?{week.replace(',', '%2C')}"), ok(f"/api/v2/schedule/bookings?{week}"),
         "a staff list with escaped commas")
    print("tier c: ok")


COLUMNS = [("id", "int"), ("date", "text"), ("account", "text"), ("description", "text"),
           ("quantity", "int"), ("amount", "dec")]


def import_answer(raw):
    """What POST /api/v3/imports answers for a valid CSV."""
    rows = list(csv.reader(io.StringIO(raw.decode(), newline=""), strict=True))
    if rows[0] != [c for c, _ in COLUMNS]:
        fail(f"import header {rows[0]}")
    columns = []
    for k, (name, kind) in enumerate(COLUMNS):
        cells = [r[k] for r in rows[1:] if r[k]]
        col = dict(name=name, count=len(cells))
        if kind == "text":
            col["bytes"] = sum(len(c.encode()) for c in cells)
        elif kind == "int":
            col["sum"] = sum(int(c) for c in cells)
        else:
            col["sum"] = sum(decimal.Decimal(c) for c in cells)
        columns.append(col)
    return dict(rows=len(rows) - 1, columns=columns)


def multipart_answer(raw, boundary):
    """What POST /api/v3/attachments answers for a multipart body with one file."""
    fields, file = [], None
    for part in (b"\r\n" + raw).split(b"\r\n--" + boundary.encode())[1:]:
        if part.startswith(b"--"):
            break
        head, _, content = part[2:].partition(b"\r\n\r\n")
        head = head.decode()
        name = re.search(r'; name="([^"]*)"', head).group(1)
        filename = re.search(r'; filename="([^"]*)"', head)
        if filename:
            ctype = re.search(r"(?i)content-type: *([^\r]*)", head)
            file = dict(field=name, filename=filename.group(1),
                        contentType=ctype.group(1) if ctype else "application/octet-stream", size=len(content),
                        adler32=zlib.adler32(content))
        else:
            fields.append((name, content.decode()))
    return dict(fields=fields, file=file)


def days_from(y, m, d):
    """Howard Hinnant's days_from_civil, as the servers compute it."""
    y -= m <= 2
    era = (y if y >= 0 else y - 399) // 400
    yoe = y - era * 400
    doy = (153 * (m + (-3 if m > 2 else 9)) + 2) // 5 + d - 1
    return era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468


def iso_ms(s):
    """An ISO time as the servers read one, in ms, or None."""
    m = re.fullmatch(r"(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(\.\d{3})?Z", s) if isinstance(s, str) else None
    if not m:
        return None
    y, mo, d, h, mi, sec = map(int, m.groups()[:6])
    if not (1 <= mo <= 12 and 1 <= d <= 31 and h < 24 and mi < 60 and sec < 60):
        return None
    return days_from(y, mo, d) * DAY + ((h * 60 + mi) * 60 + sec) * 1000 + int((m.group(7) or ".0")[1:])


def batch_answer(raw):
    """POST /api/v3/bookings/batch's status and answer for a well-formed batch."""
    b = json.loads(raw)

    def number(v, lo, hi):
        return isinstance(v, (int, float)) and not isinstance(v, bool) and lo <= v <= hi and v == int(v)

    errors, minutes = [], 0
    for k, x in enumerate(b["bookings"]):
        if not isinstance(x, dict):
            errors.append(dict(index=k, field="booking", message="must be an object"))
            continue

        def check(field, ok, message):
            if field not in x:
                errors.append(dict(index=k, field=field, message="is required"))
            elif not ok(x[field]):
                errors.append(dict(index=k, field=field, message=message))

        check("clientId", lambda v: number(v, 1, 1000000), "must be an integer from 1 to 1000000")
        check("staffId", lambda v: number(v, 1, 10), "must be an integer from 1 to 10")
        check("service", lambda v: isinstance(v, str) and re.fullmatch(r"[A-Z]{2,4}-\d\d", v),
              "must be a service code")
        check("start", lambda v: iso_ms(v) is not None, "must be an ISO 8601 time")
        check("end", lambda v: iso_ms(v) is not None, "must be an ISO 8601 time")
        start, end = iso_ms(x.get("start")), iso_ms(x.get("end"))
        if start is not None and end is not None:
            if not 0 < end - start <= 8 * 3600000:
                errors.append(dict(index=k, field="end", message="must be after start, by at most 8 hours"))
            minutes += (end - start) // 60000
        check("room", lambda v: number(v, 1, 6), "must be an integer from 1 to 6")
        if "note" in x and not (x["note"] is None or isinstance(x["note"], str) and len(x["note"].encode()) <= 500):
            errors.append(dict(index=k, field="note", message="must be a string of at most 500 bytes"))
    if errors:
        return 422, dict(error="invalid", errors=errors)
    n = len(b["bookings"])
    return 201, dict(batchId=b["batchId"], count=n, minutes=minutes, ids=[f"{b['batchId']}-{k}" for k in
                                                                            range(1, n + 1)])


def raw_exchange(port, head, body, chunk=1 << 20):
    """Sends a request on a connection of its own, and returns the status the
    server answers, which may come before it takes the whole body."""
    s = socket.create_connection(("127.0.0.1", port), timeout=10)
    try:
        s.sendall(head)
        for k in range(0, len(body), chunk):
            s.sendall(body[k:k + chunk])
    except OSError:
        pass
    got = b""
    try:
        while b"\r\n" not in got:
            more = s.recv(4096)
            if not more:
                break
            got += more
    except OSError:
        pass
    s.close()
    return int(got.split(b" ", 2)[1]) if got.startswith(b"HTTP/1.1 ") else None


def tier_d(port, data):
    load = [line.split("\t") for line in open(os.path.join(data, "writes-load.txt")).read().splitlines()]
    tokens = [f[1] for f in (line.split("\t") for line in open(os.path.join(data, "heavy-load.txt"))
                             .read().splitlines()) if f[0] == "token"]
    token = "Bearer " + tokens[0]
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
    rng = random.Random(4)

    def post(path, ctype, body, chunks=None, auth=True):
        h = {"Authorization": token if auth else None, "Content-Type": ctype}
        h = {k: v for k, v in h.items() if v is not None}
        if chunks:
            pieces, k = [], 0
            while k < len(body):
                n = rng.randint(1, chunks)
                pieces.append(body[k:k + n])
                k += n
            conn.request("POST", path, body=iter(pieces), headers=h, encode_chunked=True)
        else:
            conn.request("POST", path, body=body, headers=h)
        r = conn.getresponse()
        raw = r.read()
        if not (r.getheader("content-type") or "").startswith("application/json"):
            fail(f"POST {path}: {r.status} {r.getheader('content-type')} {raw[:200]}")
        return r.status, json.loads(raw, parse_float=decimal.Decimal, object_pairs_hook=list)

    def expect(what, got, status, want):
        if got[0] != status or got[1] != want:
            fail(f"{what}: {got[0]} {str(got[1])[:600]}\n  want {status} {str(want)[:600]}")

    def pairs(v):
        """want as the answers' object_pairs_hook reads them."""
        if isinstance(v, dict):
            return [(k, pairs(x)) for k, x in v.items()]
        if isinstance(v, list) and not (len(v) and isinstance(v[0], tuple)):
            return [pairs(x) for x in v]
        if isinstance(v, list):
            return [(k, pairs(x)) for k, x in v]
        return v

    def read(name):
        return open(os.path.join(data, name), "rb").read()

    imports = [f[1] for f in load if f[0] == "import"]
    for k, name in enumerate(imports):
        body = read(name)
        expect(name, post("/api/v3/imports", "text/csv", body, chunks=65536 if k % 2 == 0 else None), 201,
               pairs(import_answer(body)))
    small = read(imports[0])
    small = small[:small.index(b"\n", 40000) + 1]
    for k in range(5):
        expect(f"{imports[0]} in small chunks", post("/api/v3/imports", "text/csv; charset=utf-8", small,
                                                     chunks=[3, 50, 300, 2000, 9000][k]),
               201, pairs(import_answer(small)))
    head = b"id,date,account,description,quantity,amount\r\n"
    for body, want in [(head + b'1,2026-01-01,A,"x, ""y""\r\nz",5,-0.05', 201),
                       (head + b"1,d,a,,,1.00\r\n2,d,a,,,2.50\r\n", 201),
                       (head, 201)]:
        expect(f"import {body!r}", post("/api/v3/imports", "text/csv", body), want, pairs(import_answer(body)))
    for body, record in [(b"", 1), (b"id,date,account,description,quantity\n", 1),
                         (b"id,date,account,description,quantity,amount,x\n", 1),
                         (head + b"1,d,a,b,2,3.00\n2,d,a,b,2\n", 3), (head + b"1,d,a,b,2,3.0\n", 2),
                         (head + b"1,d,a,b,x,3.00\n", 2), (head + b"1,d,a,b,2,3.00\n,\n", 3),
                         (head + b'1,d,a,"b,2,3.00\n', 2), (head + b'1,d,a,b"c,2,3.00\n', 2),
                         (head + b'1,d,a,"b"c,2,3.00\n', 2), (head + b"1,d,a,b,2,3.00\r2", 2),
                         (head + b"\n", 2), (head + b"-,d,a,b,2,3.00\n", 2), (head + b"1-2,d,a,b,2,3.00\n", 2)]:
        expect(f"import {body!r}", post("/api/v3/imports", "text/csv", body), 400,
               pairs(dict(error="bad_csv", record=record)))
    print("tier d: imports ok")

    attachments = [(f[1], f[2]) for f in load if f[0] == "attachment"]
    for k, (name, b) in enumerate(attachments):
        body = read(name)
        want = multipart_answer(body, b)
        expect(name, post("/api/v3/attachments", f"multipart/form-data; boundary={b}", body,
                          chunks=[None, 65536, 1500][k % 3]), 201, pairs(want))
    name, b = attachments[0]
    body = read(name)
    small = body[:body.index(b"%PDF") + 30000] + f"\r\n--{b}--\r\n".encode()
    for size in [1, 7, 60, 999]:
        expect(f"an attachment in chunks of up to {size}",
               post("/api/v3/attachments", f'multipart/form-data; boundary="{b}"', small, chunks=size), 201,
               pairs(multipart_answer(small, b)))
    no_file = body[:body.index(b"--" + b.encode() + b"\r\nContent-Disposition: form-data; name=\"file\"")] + \
        f"--{b}--\r\n".encode()
    expect("an attachment without its file", post("/api/v3/attachments", f"multipart/form-data; boundary={b}",
                                                  no_file),
           422, pairs(dict(error="invalid", errors=[dict(field="file", message="is required")])))
    long_text = f"--{b}\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n{'x' * 1025}\r\n--{b}--\r\n"
    for what, ctype, body in [("no close delimiter", f"multipart/form-data; boundary={b}", small[:-4]),
                              ("another boundary", "multipart/form-data; boundary=other", small),
                              ("no boundary", "multipart/form-data", small),
                              ("a text field of 1,025 bytes", f"multipart/form-data; boundary={b}", long_text.encode())]:
        expect(f"an attachment with {what}", post("/api/v3/attachments", ctype, body), 400,
               pairs(dict(error="bad_request", status=400)))
    print("tier d: attachments ok")

    batches = [f[1] for f in load if f[0] == "batch"]
    invalid = 0
    for k, name in enumerate(batches):
        body = read(name)
        status, want = batch_answer(body)
        invalid += status == 422
        expect(name, post("/api/v3/bookings/batch", "application/json", body, chunks=65536 if k % 2 else None),
               status, pairs(want))
    if invalid != len(batches) // 4:
        fail(f"{invalid} invalid batches of {len(batches)}")
    one = dict(clientId=5, staffId=2, service="PT-01", start="2026-10-14T09:00:00Z", end="2026-10-14T09:45:00.000Z",
               room=3)
    for bookings in [[one], [], [dict(one, note=None), dict(one, note="ä" * 250, clientId=7.0)],
                     [dict(one, staffId=0), dict(one, service="PT-1", room=7, extra=[1, {"a": 2}]), 5,
                      {k: v for k, v in one.items() if k != "start"}, dict(one, end="2026-10-14T18:00:00Z"),
                      dict(one, start="2026-10-14", clientId="5", note="x" * 501), dict(one, staffId=True),
                      dict(one, clientId=1.5, end=one["start"])]]:
        body = json.dumps(dict(batchId="b-7", bookings=bookings)).encode()
        status, want = batch_answer(body)
        expect(f"batch {body[:300]!r}", post("/api/v3/bookings/batch", "application/json", body), status, pairs(want))
    for body in [b"{", b"[]", b'{"bookings":[]}', b'{"batchId":"","bookings":[]}', b'{"batchId":"b","bookings":{}}',
                 b'{"batchId":5,"bookings":[]}', b'{"batchId":"b","bookings":[]} x']:
        expect(f"batch {body!r}", post("/api/v3/bookings/batch", "application/json", body), 400,
               pairs(dict(error="bad_request", status=400)))
    print("tier d: batches ok")

    forms = [f[1] for f in load if f[0] == "form"]
    for k, name in enumerate(forms):
        body = read(name)
        want = urllib.parse.parse_qsl(body.decode(), keep_blank_values=True)
        expect(name, post("/api/v3/forms", "application/x-www-form-urlencoded", body,
                          chunks=1000 if k % 4 == 1 else None), 200, pairs(dict(fields=want, count=len(want))))
    for body in [b"", b"a=1&&b=&c&d=%C3%A4+%2B", b"q=" + b"x" * 60000]:
        want = urllib.parse.parse_qsl(body.decode(), keep_blank_values=True)
        expect(f"form {body[:80]!r}", post("/api/v3/forms", "application/x-www-form-urlencoded", body), 200,
               pairs(dict(fields=want, count=len(want))))
    for body in [b"a=%zz", b"a=%4", b"%=1"]:
        expect(f"form {body!r}", post("/api/v3/forms", "application/x-www-form-urlencoded", body), 400,
               pairs(dict(error="bad_request", status=400)))
    print("tier d: forms ok")

    for path, ctype in [("/api/v3/imports", "text/plain"), ("/api/v3/attachments", "application/json"),
                        ("/api/v3/bookings/batch", "text/csv"), ("/api/v3/forms", "multipart/form-data; boundary=x")]:
        expect(f"POST {path} as {ctype}", post(path, ctype, b"x"), 415,
               pairs(dict(error="unsupported_media_type", status=415)))
        expect(f"POST {path} without a token", post(path, ctype, b"x", auth=False), 401,
               pairs(dict(error="unauthorized", status=401)))
    expect("POST /api/v3/nothing", post("/api/v3/nothing", "text/csv", b"x"), 404,
           pairs(dict(error="not_found", status=404)))
    conn.request("GET", "/api/v3/imports", headers={"Authorization": token})
    r = conn.getresponse()
    r.read()
    if r.status != 404:
        fail(f"GET /api/v3/imports: {r.status}")

    def head_of(path, ctype, length=None):
        framing = f"Content-Length: {length}" if length is not None else "Transfer-Encoding: chunked"
        return (f"POST {path} HTTP/1.1\r\nHost: bench\r\nAuthorization: {token}\r\nContent-Type: {ctype}\r\n"
                f"{framing}\r\n\r\n").encode()

    def chunked(body):
        return b"".join(b"%x\r\n%s\r\n" % (len(body[k:k + 65536]), body[k:k + 65536])
                        for k in range(0, len(body), 65536)) + b"0\r\n\r\n"

    big = b"q=" + b"x" * 70000
    for what, request, body in [
            ("an import over 16 MB", head_of("/api/v3/imports", "text/csv", 16777217), b""),
            ("a chunked import over 16 MB", head_of("/api/v3/imports", "text/csv"), chunked(b"x" * 16777300)),
            ("a batch over 1 MB", head_of("/api/v3/bookings/batch", "application/json", 1048577), b"{"),
            ("a chunked batch over 1 MB", head_of("/api/v3/bookings/batch", "application/json"),
             chunked(b" " * 1048600)),
            ("a form over 64 KB", head_of("/api/v3/forms", "application/x-www-form-urlencoded", len(big)), big),
            ("a chunked form over 64 KB", head_of("/api/v3/forms", "application/x-www-form-urlencoded"),
             chunked(big))]:
        status = raw_exchange(port, request, body)
        if status != 413:
            fail(f"{what}: {status}, want 413")
    # The connection still answers after the refusals on others.
    expect("an import after the refusals", post("/api/v3/imports", "text/csv", head), 201,
           pairs(import_answer(head)))
    print("tier d: ok")


def main():
    port, data = int(sys.argv[1]), sys.argv[2]
    tier = sys.argv[3] if len(sys.argv) > 3 else "a"
    {"a": tier_a, "b": tier_b, "c": tier_c, "d": tier_d}[tier](port, data)


if __name__ == "__main__":
    main()
