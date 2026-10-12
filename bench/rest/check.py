"""Checks a REST benchmark server's answers against the generator's dataset
files (task 021), before its load runs, as HttpArena's validate.sh does.

    python3 bench/rest/check.py PORT DATADIR [TIER]    (TIER: a, the default, b, or c)

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

Exits non-zero with a message on the first failure.
"""

import calendar
import http.client
import json
import os
import random
import sys
import time

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


def main():
    port, data = int(sys.argv[1]), sys.argv[2]
    tier = sys.argv[3] if len(sys.argv) > 3 else "a"
    {"a": tier_a, "b": tier_b, "c": tier_c}[tier](port, data)


if __name__ == "__main__":
    main()
