// Tier B, snowtime's k6 hot path, under /api/v1, answered as snowtime's Hono
// routes answer (bench/rest/hyper/src/snow.rs):
//
//   GET   /api/v1/session                        the session, or null
//   GET   /api/v1/timer                          the running timer, or null
//   GET   /api/v1/organizations/:org/entries     ?from=&to=&userId=
//   GET   /api/v1/organizations/:org/projects    ?includeArchived=
//   PATCH /api/v1/organizations/:org/entries/:id {"description"}
//   POST  /api/v1/organizations/:org/timer/start {"id","description",...}
//   POST  /api/v1/timer/stop                     {"id"}
//
// A session cookie names the user, by its token; a write needs Origin to be
// the app's. The data doesn't change: a PATCH answers the entry with the
// description it was sent, and timer start and stop answer as of now, as if
// the timer had started.
package rest

import "core:encoding/json"
import "core:slice"
import "core:strings"

APP_URL :: "https://time.bench.example.com"
SESSION_COOKIE :: "__Secure-better-auth.session_token"

Project :: struct {
	id:         string,
	name:       string,
	color:      Maybe(string),
	archivedAt: Maybe(string),
	hasEntries: bool,
	teamIds:    []string,
}

Org_File :: struct {
	id:         string,
	name:       string,
	slug:       string,
	issueLinks: Maybe(string),
	projects:   []Project,
}

Org :: struct {
	id:    string,
	name:  string,
	slug:  string,
	links: Maybe(string),
	first: int, // its projects, projects[first:first + count]
	count: int,
}

Settings :: struct {
	timeZone:            string,
	weekStart:           string,
	locale:              string,
	theme:               string,
	timerLayout:         string,
	showSummary:         bool,
	compactRows:         bool,
	wideTimer:           bool,
	timerView:           string,
	calendarWeekend:     bool,
	appIcon:             string,
	sceneCollection:     string,
	scenePin:            Maybe(string),
	sceneBackground:     bool,
	sceneStrength:       string,
	surfaces:            string,
	sceneWeather:        bool,
	sceneIntro:          bool,
	sceneTagline:        bool,
	durationFormat:      string,
	dateFormat:          string,
	timeFormat:          string,
	copyDurationPattern: string,
	copyDurationControl: string,
	country:             Maybe(string),
}

Last_Day :: struct {
	date:   string,
	filled: bool,
}

Fill :: struct {
	date:           string,
	timerStartedAt: Maybe(i64),
	today:          string,
	lastWorkingDay: Maybe(Last_Day),
	lastWeek:       Maybe(bool),
	lastMonth:      Maybe(bool),
	caughtUp:       bool,
	emptyDays:      i64,
	streak:         i64,
}

Member_File :: struct {
	id:   string,
	role: string,
}

Person_File :: struct {
	id:                   string,
	name:                 string,
	email:                string,
	image:                Maybe(string),
	token:                string,
	signedInAt:           Maybe(string),
	organizations:        []Member_File,
	activeOrganizationId: string,
	teamIds:              []string,
	settings:             Settings,
	fill:                 Fill,
}

Member :: struct {
	org:  int,
	role: string,
}

Person :: struct {
	file:    Person_File,
	orgs:    []Member, // as the session lists them
	active:  int,
	first:   int, // the person's entries, entries[first:first + count]
	count:   int,
	running: int, // the running entry, or -1
}

// An entry as the routes answer it, and as the file holds it.
Entry_Json :: struct {
	id:             string,
	organizationId: string,
	userId:         string,
	projectId:      Maybe(string),
	description:    string,
	ticket:         Maybe(string),
	startedAt:      string,
	stoppedAt:      Maybe(string),
}

Entry :: struct {
	json:    Entry_Json,
	user:    int,
	org:     int,
	started: i64,
	stopped: i64, // or -1, running
}

// An entry's prebuilt JSON, and where its description's value starts and
// ends, for a PATCH to put another there.
Entry_Prebuilt :: struct {
	json: []u8,
	desc: int,
	tail: int,
}

Snow :: struct {
	orgs:         []Org,
	projects:     [dynamic]Project,
	people:       []Person,
	entries:      [dynamic]Entry, // by person, then by start
	by_token:     map[string]int,
	by_person_id: map[string]int,
	by_entry_id:  map[string]int,
	// JSON=template's: each session, each running timer as GET /timer
	// answers it, each project, and each entry.
	session_json: [][]u8,
	timer_json:   [][]u8,
	project_json: [][]u8,
	entry_json:   []Entry_Prebuilt,
}

snow: Snow

User_Out :: struct {
	id:    string,
	name:  string,
	email: string,
	image: Maybe(string),
}

Org_Out :: struct {
	id:         string,
	name:       string,
	slug:       string,
	issueLinks: Maybe(string),
	role:       string,
}

Session_Out :: struct {
	user:                 User_Out,
	signedInAt:           Maybe(string),
	organizations:        []Org_Out,
	activeOrganizationId: string,
	settings:             Settings,
	fill:                 Fill,
	invitationId:         json.Null,
	appUrl:               string,
}

Project_Ref :: struct {
	id:    string,
	name:  string,
	color: Maybe(string),
}

// GET /timer's answer: the running entry and its project.
Timer_Out :: struct {
	using _: Entry_Json,
	project: Maybe(Project_Ref),
}

Start_Out :: struct {
	started: Entry_Json,
	stopped: Maybe(Entry_Json),
}

snow_load :: proc(dir: string, template: bool) -> int {
	s := &snow
	orgs: []Org_File
	read_into(dir, "snow-orgs.json", &orgs)
	s.orgs = make([]Org, len(orgs))
	for o, k in orgs {
		s.orgs[k] = Org{o.id, o.name, o.slug, o.issueLinks, len(s.projects), len(o.projects)}
		append(&s.projects, ..o.projects)
	}
	people: []Person_File
	read_into(dir, "snow-users.json", &people)
	s.people = make([]Person, len(people))
	for p, k in people {
		orgs := make([]Member, len(p.organizations))
		for m, j in p.organizations {
			o, ok := snow_org_index(m.id)
			check(ok, "a member of an organization snow-orgs.json lacks")
			orgs[j] = Member{o, m.role}
		}
		active, ok := snow_org_index(p.activeOrganizationId)
		check(ok, "a user without an organization")
		check(len(p.token) == 64, "a user without a token")
		s.people[k] = Person{p, orgs, active, 0, 0, -1}
		s.by_token[p.token] = k
		s.by_person_id[p.id] = k
	}
	entries: []Entry_Json
	read_into(dir, "snow-entries.json", &entries)
	reserve(&s.entries, len(entries))
	for e in entries {
		org, ook := snow_org_index(e.organizationId)
		check(ook, "an entry of an organization snow-orgs.json lacks")
		user, uok := s.by_person_id[e.userId]
		check(uok, "an entry of a user snow-users.json lacks")
		if j, has := e.projectId.?; has {
			_, pok := snow_project_index(j, org)
			check(pok, "an entry of a project snow-orgs.json lacks")
		}
		n := len(s.entries)
		started := must_iso(e.startedAt, "an entry's startedAt")
		stopped: i64 = -1
		if t, has := e.stoppedAt.?; has do stopped = must_iso(t, "an entry's stoppedAt")
		p := &s.people[user]
		if p.count == 0 do p.first = n
		check(p.first + p.count == n, "snow-entries.json doesn't have each user's entries together")
		check(p.count == 0 || s.entries[n - 1].started < started, "a user's entries out of order")
		p.count += 1
		if stopped < 0 do p.running = n
		append(&s.entries, Entry{e, user, org, started, stopped})
		s.by_entry_id[e.id] = n
	}
	if template do snow_prebuild()
	return len(s.entries)
}

snow_prebuild :: proc() {
	s := &snow
	s.session_json = make([][]u8, len(s.people))
	s.timer_json = make([][]u8, len(s.people))
	for p, u in s.people {
		s.session_json[u] = marshal(snow_session_out(u, context.allocator), context.allocator)
		s.timer_json[u] = marshal(snow_timer_out(p.running), context.allocator) if p.running >= 0 else
			transmute([]u8)string("null")
	}
	s.project_json = make([][]u8, len(s.projects))
	for &j, k in s.projects do s.project_json[k] = marshal(j, context.allocator)
	s.entry_json = make([]Entry_Prebuilt, len(s.entries))
	for &e, k in s.entries {
		j := marshal(e.json, context.allocator)
		// A string's quotes are escaped, so these members' keys are the
		// first such bytes.
		desc := strings.index(string(j), ",\"description\":") + 15
		tail := desc + strings.index(string(j[desc:]), ",\"ticket\":")
		s.entry_json[k] = Entry_Prebuilt{j, desc, tail}
	}
}

snow_org_index :: proc(id: string) -> (int, bool) {
	for o, k in snow.orgs do if o.id == id do return k, true
	return 0, false
}

snow_project_index :: proc(id: string, org: int) -> (int, bool) {
	o := snow.orgs[org]
	for k in o.first ..< o.first + o.count do if snow.projects[k].id == id do return k, true
	return 0, false
}

snow_session_out :: proc(u: int, allocator := context.temp_allocator) -> Session_Out {
	p := &snow.people[u]
	orgs := make([]Org_Out, len(p.orgs), allocator)
	for m, k in p.orgs {
		o := snow.orgs[m.org]
		orgs[k] = Org_Out{o.id, o.name, o.slug, o.links, m.role}
	}
	f := &p.file
	return Session_Out {
		user = User_Out{f.id, f.name, f.email, f.image},
		signedInAt = f.signedInAt,
		organizations = orgs,
		activeOrganizationId = snow.orgs[p.active].id,
		settings = f.settings,
		fill = f.fill,
		appUrl = APP_URL,
	}
}

snow_timer_out :: proc(i: int) -> Timer_Out {
	e := snow.entries[i].json
	out := Timer_Out{e, nil}
	if j, has := e.projectId.?; has {
		k, _ := snow_project_index(j, snow.entries[i].org)
		p := snow.projects[k]
		out.project = Project_Ref{p.id, p.name, p.color}
	}
	return out
}

is_lower_hex :: proc(c: u8) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
}

// snowtime's Uuidv7: 8-4-4-4-12 lower-case hex digits, version 7, variant 8
// to b.
is_uuid7 :: proc(s: string) -> bool {
	if len(s) != 36 || s[14] != '7' do return false
	switch s[19] {
	case '8', '9', 'a', 'b':
	case:
		return false
	}
	for c, i in transmute([]u8)s {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' do return false
		} else if !is_lower_hex(c) {
			return false
		}
	}
	return true
}

// The time a uuidv7 was made, from its first 48 bits.
uuid_ms :: proc(s: string) -> (v: i64) {
	for c in transmute([]u8)s[:13] {
		if c == '-' do continue
		v = v * 16 + i64(c - '0' if c <= '9' else c - 'a' + 10)
	}
	return
}

// snowtime's ticket key: [A-Z][A-Z0-9]{1,9}-[1-9][0-9]{0,6}.
is_ticket :: proc(s: string) -> bool {
	dash := strings.index_byte(s, '-')
	if dash < 2 || dash > 10 || !(s[0] >= 'A' && s[0] <= 'Z') do return false
	for c in transmute([]u8)s[1:dash] {
		if !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) do return false
	}
	n := s[dash + 1:]
	if len(n) < 1 || len(n) > 7 || n[0] < '1' || n[0] > '9' do return false
	for c in transmute([]u8)n do if c < '0' || c > '9' do return false
	return true
}

is_admin :: proc(m: Member) -> bool {
	return m.role == "owner" || m.role == "admin"
}

snow_error :: proc(status: int, body: string) -> Resp {
	return json_text(status, body)
}

coded :: proc(status: int, code: string, key: string) -> Resp {
	b := builder(64)
	strings.write_string(&b, "{\"error\":{\"code\":\"")
	strings.write_string(&b, code)
	strings.write_string(&b, "\",\"key\":\"")
	strings.write_string(&b, key)
	strings.write_string(&b, "\"}}")
	return json_status(status, done(&b))
}

invalid :: proc() -> Resp {
	return snow_error(400, "{\"error\":{\"message\":\"Invalid input.\"}}")
}

not_json :: proc() -> Resp {
	return snow_error(400, "{\"error\":{\"message\":\"The body is not JSON.\"}}")
}

// The value of cookie name in the Cookie fields, without the quotes it may
// have; the first, if it repeats.
cookie_of :: proc(h: ^Head, name: string) -> (string, bool) {
	ows :: proc(s: string) -> string {
		return strings.trim(s, " \t\n\r\f")
	}
	for v in h.cookies[:h.n_cookies] {
		v := v
		for pair in strings.split_iterator(&v, ";") {
			pair := ows(pair)
			eq := strings.index_byte(pair, '=')
			if eq <= 0 || ows(pair[:eq]) != name do continue
			val := ows(pair[eq + 1:])
			if len(val) >= 2 && val[0] == '"' && val[len(val) - 1] == '"' do val = val[1:len(val) - 1]
			return val, true
		}
	}
	return "", false
}

// The person the session cookie names.
person_of :: proc(h: ^Head) -> (u: int, ok: bool) {
	v := cookie_of(h, SESSION_COOKIE) or_return
	if !(len(v) > 65 && v[64] == '.') do return 0, false
	return snow.by_token[v[:64]]
}

// listProjects's visibility: an admin sees every project, a member those
// with no team and those of a team of theirs.
sees :: proc(p: ^Person, m: Member, j: ^Project) -> bool {
	if is_admin(m) || len(j.teamIds) == 0 do return true
	if m.org != p.active do return false
	for t in j.teamIds do if slice.contains(p.file.teamIds, t) do return true
	return false
}

// Tier B's routes, checked in snowtime's order: an unknown call, a write
// from another origin, GET /session, which answers null to no one, the
// sign-in, and the organization's membership.
snow_handle :: proc(h: ^Head, body: []u8) -> Resp {
	s := &snow
	get := h.method == .Get || h.method == .Head
	params: [2]string
	route := 0
	switch {
	case get && matches(h.path, "/api/v1/session", &params):
		route = 1
	case get && matches(h.path, "/api/v1/timer", &params):
		route = 2
	case h.method == .Post && matches(h.path, "/api/v1/timer/stop", &params):
		route = 3
	case get && matches(h.path, "/api/v1/organizations/:org/entries", &params):
		route = 4
	case get && matches(h.path, "/api/v1/organizations/:org/projects", &params):
		route = 5
	case h.method == .Patch && matches(h.path, "/api/v1/organizations/:org/entries/:id", &params):
		route = 6
	case h.method == .Post && matches(h.path, "/api/v1/organizations/:org/timer/start", &params):
		route = 7
	case:
		return snow_error(404, "{\"error\":{\"message\":\"No such call.\"}}")
	}
	if !get {
		if o, ok := h.origin.?; !ok || o != APP_URL {
			return snow_error(403, "{\"error\":{\"message\":\"Cross-origin request refused.\"}}")
		}
	}
	u, signed := person_of(h)
	if route == 1 {
		if !signed do return json_text(200, "null")
		if data.template do return json_status(200, s.session_json[u])
		return json_status(200, marshal(snow_session_out(u)))
	}
	if !signed do return coded(401, "UNAUTHENTICATED", "sign_in_required")
	p := &s.people[u]
	if route == 2 {
		if data.template do return json_status(200, s.timer_json[u])
		if p.running < 0 do return json_text(200, "null")
		return json_status(200, marshal(snow_timer_out(p.running)))
	}
	if route == 3 do return stop_timer(body, u)
	m: Member
	member := false
	for x in p.orgs {
		if s.orgs[x.org].id == params[0] {
			m, member = x, true
			break
		}
	}
	if !member do return coded(403, "FORBIDDEN", "not_organization_member")
	switch route {
	case 4:
		return list_entries(h.query, p, m)
	case 5:
		return list_projects(h.query, p, m)
	case 6:
		return patch_entry(params[1], body, p, m)
	}
	return start_timer(body, u, m)
}

decoded_query :: proc(query: Maybe(string), key: string) -> (value: string, ok: bool) {
	v := query_of(query, key) or_return
	return decode(v)
}

// GET .../entries: the entries of userId, or of the caller, that overlap
// [from, to), newest first, as listEntries selects them.
list_entries :: proc(query: Maybe(string), p: ^Person, m: Member) -> Resp {
	s := &snow
	f, fok := decoded_query(query, "from")
	t, tok := decoded_query(query, "to")
	if !fok || !tok do return invalid()
	from, frok := parse_iso(f)
	to, took := parse_iso(t)
	if !frok || !took do return invalid()
	if !(to > from && to - from <= 93 * DAY) do return invalid()
	who, has_who := s.by_person_id[p.file.id]
	if uid, ok := decoded_query(query, "userId"); ok {
		if !is_uuid7(uid) do return invalid()
		if uid != p.file.id {
			if !is_admin(m) do return coded(403, "FORBIDDEN", "entries_forbidden")
			who, has_who = s.by_person_id[uid]
		}
	}
	listed := make([dynamic]int, 0, 64, context.temp_allocator)
	if has_who && s.people[who].active == m.org {
		w := &s.people[who]
		mine := s.entries[w.first:w.first + w.count]
		lo, hi := 0, len(mine)
		for lo < hi {
			mid := (lo + hi) / 2
			if mine[mid].started < to {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		i := lo
		for i > 0 && mine[i - 1].started > from - DAY {
			i -= 1
			if mine[i].stopped < 0 || mine[i].stopped > from do append(&listed, w.first + i)
		}
	}
	b := builder()
	if data.template {
		strings.write_byte(&b, '[')
		for i, k in listed {
			if k > 0 do strings.write_byte(&b, ',')
			strings.write_bytes(&b, s.entry_json[i].json)
		}
		strings.write_byte(&b, ']')
	} else {
		out := make([]Entry_Json, len(listed), context.temp_allocator)
		for i, k in listed do out[k] = s.entries[i].json
		write_json(&b, out)
	}
	return json_status(200, done(&b))
}

list_projects :: proc(query: Maybe(string), p: ^Person, m: Member) -> Resp {
	s := &snow
	v, has := query_of(query, "includeArchived")
	if has && v != "true" && v != "false" do return invalid()
	archived := has && v == "true"
	o := s.orgs[m.org]
	listed := make([dynamic]int, 0, o.count, context.temp_allocator)
	for i in o.first ..< o.first + o.count {
		j := &s.projects[i]
		if (archived || j.archivedAt == nil) && sees(p, m, j) do append(&listed, i)
	}
	b := builder()
	if data.template {
		strings.write_byte(&b, '[')
		for i, k in listed {
			if k > 0 do strings.write_byte(&b, ',')
			strings.write_bytes(&b, s.project_json[i])
		}
		strings.write_byte(&b, ']')
	} else {
		out := make([]Project, len(listed), context.temp_allocator)
		for i, k in listed do out[k] = s.projects[i]
		write_json(&b, out)
	}
	return json_status(200, done(&b))
}

// A member that must be a string if present: null is refused. ok is false
// for a member of another type.
string_member :: proc(obj: json.Object, key: string) -> (s: string, present: bool, ok: bool) {
	v, has := obj[key]
	if !has do return "", false, true
	str, is := v.(json.String)
	return str, true, is
}

// A member that may be absent or null, or else a string.
optional_string :: proc(obj: json.Object, key: string) -> (s: string, present: bool, ok: bool) {
	v, has := obj[key]
	if !has do return "", false, true
	if _, null := v.(json.Null); null do return "", false, true
	str, is := v.(json.String)
	return str, true, is
}

// body as a JSON object: not_json for a body that isn't JSON, and invalid for
// one that isn't an object.
body_object :: proc(body: []u8) -> (json.Object, Resp, bool) {
	v, ok := parse_whole(body)
	if !ok do return nil, not_json(), false
	obj, is := v.(json.Object)
	if !is || !is_object(body) do return nil, invalid(), false
	return obj, {}, true
}

patch_entry :: proc(id: string, body: []u8, p: ^Person, m: Member) -> Resp {
	s := &snow
	if !is_uuid7(id) do return invalid()
	obj, refused, ok := body_object(body)
	if !ok do return refused
	d, has_desc, dok := string_member(obj, "description")
	if !dok do return invalid()
	d = trim_ws(d)
	if has_desc && len(d) > 500 do return invalid()
	i, found := s.by_entry_id[id]
	if !found || s.entries[i].org != m.org do return coded(404, "NOT_FOUND", "entry_not_found")
	e := &s.entries[i]
	if s.people[e.user].file.id != p.file.id && !is_admin(m) do return coded(403, "FORBIDDEN", "entry_forbidden")
	if !has_desc {
		if data.template do return json_status(200, s.entry_json[i].json)
		return json_status(200, marshal(e.json))
	}
	if data.template {
		t := s.entry_json[i]
		b := builder(len(t.json) + len(d) + 8)
		strings.write_bytes(&b, t.json[:t.desc])
		write_string(&b, d)
		strings.write_bytes(&b, t.json[t.tail:])
		return json_status(200, done(&b))
	}
	out := e.json
	out.description = d
	return json_status(200, marshal(out))
}

// Running entry i stopped at now, as stopRunning stops it: after it
// started, and at most a day after.
stopped_at :: proc(i: int, now: i64) -> i64 {
	started := snow.entries[i].started
	return min(max(now, started + 1), started + DAY)
}

write_stopped :: proc(b: ^strings.Builder, i: int, now: i64) {
	at := stopped_at(i, now)
	if data.template {
		// A running entry's JSON ends in "null}".
		j := snow.entry_json[i].json
		strings.write_bytes(b, j[:len(j) - 5])
		write_iso(b, at)
		strings.write_byte(b, '}')
	} else {
		out := snow.entries[i].json
		out.stoppedAt = iso_string(at)
		write_json(b, out)
	}
}

// POST .../timer/start: the new entry, started now, and the timer it
// stopped, the caller's running one, or null.
start_timer :: proc(body: []u8, u: int, m: Member) -> Resp {
	s := &snow
	obj, refused, ok := body_object(body)
	if !ok do return refused
	id, has_id, iok := string_member(obj, "id")
	desc, _, dok := string_member(obj, "description")
	ticket, has_ticket, tok := optional_string(obj, "ticket")
	project, has_project, pok := optional_string(obj, "projectId")
	if !iok || !dok || !tok || !pok do return invalid()
	desc = trim_ws(desc)
	valid := len(desc) <= 500 && has_id && is_uuid7(id) && (!has_ticket || (len(ticket) <= 18 && is_ticket(ticket))) &&
		(!has_project || is_uuid7(project))
	if !valid do return invalid()
	p := &s.people[u]
	if has_project {
		j, found := snow_project_index(project, m.org)
		if !found || !sees(p, m, &s.projects[j]) do return coded(404, "NOT_FOUND", "project_not_found")
		if s.projects[j].archivedAt != nil do return coded(409, "CONFLICT", "project_archived")
	}
	if id in s.by_entry_id do return coded(409, "CONFLICT", "entry_id_taken")
	now := now_ms()
	started := Entry_Json {
		id             = id,
		organizationId = s.orgs[m.org].id,
		userId         = p.file.id,
		description    = desc,
		startedAt      = iso_string(now),
	}
	if has_project do started.projectId = project
	if has_ticket do started.ticket = ticket
	b := builder(1024)
	if data.template {
		strings.write_string(&b, "{\"started\":")
		write_json(&b, started)
		strings.write_string(&b, ",\"stopped\":")
		if p.running >= 0 {
			write_stopped(&b, p.running, now)
		} else {
			strings.write_string(&b, "null")
		}
		strings.write_byte(&b, '}')
	} else {
		out := Start_Out{started = started}
		if p.running >= 0 {
			stopped := s.entries[p.running].json
			stopped.stoppedAt = iso_string(stopped_at(p.running, now))
			out.stopped = stopped
		}
		write_json(&b, out)
	}
	return json_status(200, done(&b))
}

// POST /timer/stop: the caller's running entry, stopped now. An id the
// dataset doesn't have is taken for a timer started with it, as timer start
// answered it: a uuidv7 made in the last day.
stop_timer :: proc(body: []u8, u: int) -> Resp {
	s := &snow
	v, ok := parse_whole(body)
	if !ok do return not_json()
	obj, is := v.(json.Object)
	if !is || !is_object(body) do return invalid()
	id, has_id, iok := string_member(obj, "id")
	if !iok || !has_id || !is_uuid7(id) do return invalid()
	p := &s.people[u]
	now := now_ms()
	b := builder(512)
	if p.running >= 0 && s.entries[p.running].json.id == id {
		write_stopped(&b, p.running, now)
		return json_status(200, done(&b))
	}
	started := uuid_ms(id)
	if !(started > now - DAY && started <= now + MINUTE && !(id in s.by_entry_id)) {
		return coded(404, "NOT_FOUND", "timer_not_running")
	}
	out := Entry_Json {
		id             = id,
		organizationId = s.orgs[p.active].id,
		userId         = p.file.id,
		description    = "",
		startedAt      = iso_string(started),
		stoppedAt      = iso_string(min(max(now, started + 1), started + DAY)),
	}
	write_json(&b, out)
	return json_status(200, done(&b))
}
