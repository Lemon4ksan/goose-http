// Tier C, a clinic's schedule and records, under /api/v2, behind a bearer JWT
// that isn't verified (bench/rest/hyper/src/heavy.rs):
//
//   GET   /api/v2/schedule/version               ?since=, the schedule's poll
//   GET   /api/v2/schedule/bookings              ?start=&end=&staff=1,2,...
//   GET   /api/v2/schedule/shifts                ?start=&end=&staff=1,2,...
//   GET   /api/v2/encounters/:id                 the visit, and its case's notes
//   GET   /api/v2/clients/:id/encounters         ?limit=, the past visits
//   GET   /api/v2/clients/:id                    the client
//
// Ids are 1, 2, ... in each file, and the schedule's days are UTC's. The
// files hold each record in the shape the routes answer it, so the records
// are kept as read, with the times and staff the selections need beside them.
package rest

import "core:slice"
import "core:strings"

Meta :: struct {
	versionEpoch: i64,
}

Staffer :: struct {
	id:    i64,
	name:  string,
	title: string,
}

Address :: struct {
	street:   string,
	city:     string,
	postcode: string,
}

Preferences :: struct {
	channel:  string,
	language: string,
}

Contact :: struct {
	name:     string,
	phone:    string,
	relation: string,
}

Consents :: struct {
	sms:      bool,
	email:    bool,
	research: bool,
}

Client :: struct {
	id:               i64,
	name:             string,
	code:             string,
	born:             string,
	phone:            string,
	email:            string,
	address:          Address,
	preferences:      Preferences,
	flags:            []string,
	emergencyContact: Contact,
	consents:         Consents,
	createdAt:        string,
	updatedAt:        string,
}

Client_Ref :: struct {
	id:   i64,
	name: string,
	code: string,
}

Staff_Ref :: struct {
	id:   i64,
	name: string,
}

Line :: struct {
	id:      i64,
	code:    string,
	name:    string,
	minutes: i64,
	price:   i64,
}

Note :: struct {
	id:     i64,
	author: Staffer,
	text:   string,
	at:     string,
}

Notes :: struct {
	intake:   []Note,
	findings: []Note,
	plan:     []Note,
	internal: []Note,
}

Encounter :: struct {
	id:       i64,
	caseId:   i64,
	client:   Client_Ref,
	staff:    Staffer,
	status:   string,
	kind:     string,
	priority: string,
	start:    string,
	end:      string,
	items:    []Line,
	codes:    []string,
	notes:    Notes,
}

Case_Note :: struct {
	id:          i64,
	encounterId: i64,
	kind:        string,
	author:      Staffer,
	text:        string,
	at:          string,
}

// GET /encounters/:id's answer: the visit, and the notes of every visit of
// its case.
Encounter_Out :: struct {
	using _:   Encounter,
	caseNotes: []Case_Note,
}

Slot :: struct {
	start: string,
	end:   string,
}

Encounter_Ref :: struct {
	id:     i64,
	status: string,
	start:  string,
	end:    string,
}

Reminder :: struct {
	channel: string,
	kind:    string,
	status:  string,
	at:      string,
}

Booking :: struct {
	id:        i64,
	slot:      Slot,
	client:    Client_Ref,
	staff:     Staff_Ref,
	encounter: Encounter_Ref,
	items:     []Line,
	reminders: []Reminder,
	status:    string,
	source:    string,
	note:      Maybe(string),
	createdAt: string,
	updatedAt: string,
}

Room :: struct {
	id:   i64,
	name: string,
}

Shift :: struct {
	id:    i64,
	staff: Staff_Ref,
	start: string,
	end:   string,
	kind:  string,
	room:  Room,
	note:  Maybe(string),
}

Bookings_Out :: struct {
	bookings: []Booking,
	count:    int,
}

Shifts_Out :: struct {
	shifts: []Shift,
	count:  int,
}

History_Out :: struct {
	items: []Encounter,
	total: int,
}

Version_Out :: struct {
	version:   i64,
	changedAt: string,
}

// Where a record falls in the schedule: its start and its staff member's
// index.
At :: struct {
	start: i64,
	staff: int,
}

Heavy :: struct {
	staff:         []Staffer,
	clients:       []Client,
	encounters:    []Encounter,
	bookings:      []Booking, // by start
	booking_at:    []At,
	shifts:        []Shift, // by start
	shift_at:      []At,
	// Every encounter's notes as caseNotes lists them, in encounter order: an
	// encounter's are case_notes[note_first[i]:note_first[i + 1]].
	case_notes:    []Case_Note,
	note_first:    []int,
	case_first:    []int, // the first encounter of each one's case
	case_last:     []int, // and its last
	// Completed visits, by client, newest first: a client's are
	// past[past_first[c]:past_first[c] + past_count[c]].
	past:          []Encounter,
	past_first:    []int,
	past_count:    []int,
	version_epoch: i64,
	// JSON=template's: each booking, shift, and client whole; each encounter
	// without its closing brace; and each case note.
	booking_json:  [][]u8,
	shift_json:    [][]u8,
	client_json:   [][]u8,
	visit_json:    [][]u8,
	note_json:     [][]u8,
}

heavy: Heavy

NOTE_KINDS :: [4]string{"intake", "findings", "plan", "internal"}

heavy_load :: proc(dir: string, template: bool) -> int {
	h := &heavy
	meta: Meta
	read_into(dir, "heavy-meta.json", &meta)
	h.version_epoch = meta.versionEpoch
	check(h.version_epoch > 0, "heavy-meta.json has no versionEpoch")
	read_into(dir, "heavy-staff.json", &h.staff)
	read_into(dir, "heavy-clients.json", &h.clients)
	read_into(dir, "heavy-encounters.json", &h.encounters)
	read_into(dir, "heavy-bookings.json", &h.bookings)
	read_into(dir, "heavy-shifts.json", &h.shifts)
	for s, i in h.staff do check(s.id == i64(i + 1), "heavy-staff.json's ids aren't 1, 2, ...")
	for c, i in h.clients do check(c.id == i64(i + 1), "heavy-clients.json's ids aren't 1, 2, ...")
	n := len(h.encounters)
	h.note_first = make([]int, n + 1)
	h.case_first = make([]int, n)
	h.case_last = make([]int, n)
	notes := make([dynamic]Case_Note)
	note_kinds := NOTE_KINDS
	for &e, i in h.encounters {
		check(e.id == i64(i + 1), "heavy-encounters.json's ids aren't 1, 2, ...")
		check(e.client.id >= 1 && e.client.id <= i64(len(h.clients)), "an encounter of a client heavy-clients.json lacks")
		h.note_first[i] = len(notes)
		kinds := [4][]Note{e.notes.intake, e.notes.findings, e.notes.plan, e.notes.internal}
		for ns, k in kinds {
			for x in ns do append(&notes, Case_Note{x.id, e.id, note_kinds[k], x.author, x.text, x.at})
		}
		// A case's encounters are together in the file.
		if i > 0 && h.encounters[i - 1].caseId == e.caseId {
			h.case_first[i] = h.case_first[i - 1]
		} else {
			check(i == 0 || h.encounters[i - 1].caseId < e.caseId, "a case's encounters apart")
			h.case_first[i] = i
		}
	}
	h.note_first[n] = len(notes)
	h.case_notes = notes[:]
	for i := n - 1; i >= 0; i -= 1 {
		last := i
		if i + 1 < n && h.case_first[i + 1] == h.case_first[i] do last = h.case_last[i + 1]
		h.case_last[i] = last
	}
	h.booking_at = make([]At, len(h.bookings))
	for b, i in h.bookings {
		check(b.id == i64(i + 1), "heavy-bookings.json's ids aren't 1, 2, ...")
		start := must_iso(b.slot.start, "a booking's start")
		check(i == 0 || h.booking_at[i - 1].start <= start, "bookings out of order")
		h.booking_at[i] = At{start, int(b.staff.id - 1)}
	}
	h.shift_at = make([]At, len(h.shifts))
	for s, i in h.shifts {
		check(s.id == i64(i + 1), "heavy-shifts.json's ids aren't 1, 2, ...")
		start := must_iso(s.start, "a shift's start")
		check(i == 0 || h.shift_at[i - 1].start <= start, "shifts out of order")
		h.shift_at[i] = At{start, int(s.staff.id - 1)}
	}
	past := make([dynamic]int)
	for e, i in h.encounters do if e.status == "completed" do append(&past, i)
	// Newest first, and of two at once the later id first.
	slice.sort_by(past[:], proc(a, b: int) -> bool {
		va, vb := &heavy.encounters[a], &heavy.encounters[b]
		if va.client.id != vb.client.id do return va.client.id < vb.client.id
		if va.start != vb.start do return va.start > vb.start
		return a > b
	})
	h.past = make([]Encounter, len(past))
	h.past_first = make([]int, len(h.clients))
	h.past_count = make([]int, len(h.clients))
	for i, k in past {
		h.past[k] = h.encounters[i]
		c := h.encounters[i].client.id - 1
		if h.past_count[c] == 0 do h.past_first[c] = k
		h.past_count[c] += 1
	}
	if template {
		h.booking_json = make([][]u8, len(h.bookings))
		for &b, i in h.bookings do h.booking_json[i] = marshal(b, context.allocator)
		h.shift_json = make([][]u8, len(h.shifts))
		for &s, i in h.shifts do h.shift_json[i] = marshal(s, context.allocator)
		h.client_json = make([][]u8, len(h.clients))
		for &c, i in h.clients do h.client_json[i] = marshal(c, context.allocator)
		h.visit_json = make([][]u8, n)
		for &e, i in h.encounters do h.visit_json[i] = without_brace(marshal(e, context.allocator))
		h.note_json = make([][]u8, len(h.case_notes))
		for &x, i in h.case_notes do h.note_json[i] = marshal(x, context.allocator)
	}
	return len(h.bookings) + n
}

heavy_error :: proc(status: int) -> Resp {
	switch status {
	case 400:
		return json_text(status, "{\"error\":\"bad_request\",\"status\":400}")
	case 401:
		return json_text(status, "{\"error\":\"unauthorized\",\"status\":401}")
	}
	return json_text(status, "{\"error\":\"not_found\",\"status\":404}")
}

is_base64url :: proc(s: string) -> bool {
	if len(s) == 0 do return false
	for c in transmute([]u8)s {
		ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_'
		if !ok do return false
	}
	return true
}

// Whether Authorization is a bearer token of three base64url segments.
has_bearer :: proc(h: ^Head) -> bool {
	auth := h.authorization.? or_return
	if !strings.has_prefix(auth, "Bearer ") do return false
	t := auth[len("Bearer "):]
	a := strings.index_byte(t, '.')
	if a < 0 do return false
	b := strings.index_byte(t[a + 1:], '.')
	if b < 0 do return false
	b += a + 1
	return is_base64url(t[:a]) && is_base64url(t[a + 1:b]) && is_base64url(t[b + 1:])
}

heavy_handle :: proc(h: ^Head) -> Resp {
	get := h.method == .Get || h.method == .Head
	params: [2]string
	route := 0
	switch {
	case get && matches(h.path, "/api/v2/schedule/version", &params):
		route = 1
	case get && matches(h.path, "/api/v2/schedule/bookings", &params):
		route = 2
	case get && matches(h.path, "/api/v2/schedule/shifts", &params):
		route = 3
	case get && matches(h.path, "/api/v2/encounters/:id", &params):
		route = 4
	case get && matches(h.path, "/api/v2/clients/:id/encounters", &params):
		route = 5
	case get && matches(h.path, "/api/v2/clients/:id", &params):
		route = 6
	case:
		return heavy_error(404)
	}
	if !has_bearer(h) do return heavy_error(401)
	switch route {
	case 1:
		return schedule_version(h.query)
	case 2:
		return list_bookings(h.query)
	case 3:
		return list_shifts(h.query)
	case 4:
		i, ok := index_of(params[0], len(heavy.encounters))
		if !ok do return heavy_error(404)
		return show_encounter(i)
	}
	c, ok := index_of(params[0], len(heavy.clients))
	if !ok do return heavy_error(404)
	if route == 5 do return client_history(h.query, c)
	if data.template do return json_status(200, heavy.client_json[c])
	return json_status(200, marshal(heavy.clients[c]))
}

Range :: struct {
	start, end: i64,
	mask:       u64,
}

// A start and an end day, end after start and at most 31 days on, and the
// staff of a list of their ids as bits.
range_of :: proc(query: Maybe(string)) -> (r: Range, ok: bool) {
	r.start = parse_day(query_of(query, "start") or_return) or_return
	r.end = parse_day(query_of(query, "end") or_return) or_return
	list := decode(query_of(query, "staff") or_return) or_return
	if !(r.end > r.start && r.end - r.start <= 31 * DAY) || len(list) == 0 do return
	for id in strings.split_iterator(&list, ",") {
		n := parse_int(id) or_return
		if n < 1 || n > i64(len(heavy.staff)) do return
		r.mask |= 1 << u64(n - 1)
	}
	return r, true
}

// The indices of records by start in [start, end) of the range's staff.
select :: proc(at: []At, r: Range) -> []int {
	lo, hi := 0, len(at)
	for lo < hi {
		mid := (lo + hi) / 2
		if at[mid].start < r.start {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	out := make([dynamic]int, 0, 1024, context.temp_allocator)
	for i in lo ..< len(at) {
		if at[i].start >= r.end do break
		if r.mask >> u64(at[i].staff) & 1 != 0 do append(&out, i)
	}
	return out[:]
}

list_bookings :: proc(query: Maybe(string)) -> Resp {
	r, ok := range_of(query)
	if !ok do return heavy_error(400)
	listed := select(heavy.booking_at, r)
	if data.template {
		b := builder(len(listed) * 1100 + 64)
		strings.write_string(&b, "{\"bookings\":[")
		for i, k in listed {
			if k > 0 do strings.write_byte(&b, ',')
			strings.write_bytes(&b, heavy.booking_json[i])
		}
		strings.write_string(&b, "],\"count\":")
		strings.write_int(&b, len(listed))
		strings.write_byte(&b, '}')
		return json_status(200, done(&b))
	}
	out := make([]Booking, len(listed), context.temp_allocator)
	for i, k in listed do out[k] = heavy.bookings[i]
	b := builder(len(listed) * 1100 + 64)
	write_json(&b, Bookings_Out{out, len(listed)})
	return json_status(200, done(&b))
}

list_shifts :: proc(query: Maybe(string)) -> Resp {
	r, ok := range_of(query)
	if !ok do return heavy_error(400)
	listed := select(heavy.shift_at, r)
	if data.template {
		b := builder(len(listed) * 220 + 64)
		strings.write_string(&b, "{\"shifts\":[")
		for i, k in listed {
			if k > 0 do strings.write_byte(&b, ',')
			strings.write_bytes(&b, heavy.shift_json[i])
		}
		strings.write_string(&b, "],\"count\":")
		strings.write_int(&b, len(listed))
		strings.write_byte(&b, '}')
		return json_status(200, done(&b))
	}
	out := make([]Shift, len(listed), context.temp_allocator)
	for i, k in listed do out[k] = heavy.shifts[i]
	b := builder(len(listed) * 220 + 64)
	write_json(&b, Shifts_Out{out, len(listed)})
	return json_status(200, done(&b))
}

// The encounter, and the notes of every visit of its case, oldest first.
show_encounter :: proc(i: int) -> Resp {
	h := &heavy
	first, last := h.note_first[h.case_first[i]], h.note_first[h.case_last[i] + 1]
	b := builder(16 * 1024)
	if data.template {
		strings.write_bytes(&b, h.visit_json[i])
		strings.write_string(&b, ",\"caseNotes\":[")
		for j in first ..< last {
			if j > first do strings.write_byte(&b, ',')
			strings.write_bytes(&b, h.note_json[j])
		}
		strings.write_string(&b, "]}")
	} else {
		write_json(&b, Encounter_Out{h.encounters[i], h.case_notes[first:last]})
	}
	return json_status(200, done(&b))
}

// The client's completed visits, newest first, up to limit, and how many
// there are.
client_history :: proc(query: Maybe(string), c: int) -> Resp {
	h := &heavy
	limit := 20
	if v, has := query_of(query, "limit"); has {
		n, ok := parse_int(v)
		if !ok || n < 1 || n > 50 do return heavy_error(400)
		limit = int(n)
	}
	first, count := h.past_first[c], h.past_count[c]
	mine := h.past[first:first + min(limit, count)]
	b := builder(64 * 1024)
	if data.template {
		strings.write_string(&b, "{\"items\":[")
		for &e, k in mine {
			if k > 0 do strings.write_byte(&b, ',')
			strings.write_bytes(&b, h.visit_json[e.id - 1])
			strings.write_byte(&b, '}')
		}
		strings.write_string(&b, "],\"total\":")
		strings.write_int(&b, count)
		strings.write_byte(&b, '}')
	} else {
		write_json(&b, History_Out{mine, count})
	}
	return json_status(200, done(&b))
}

// GET /schedule/version: the schedule's version, the minutes since
// version_epoch, and when it changed to it.
schedule_version :: proc(query: Maybe(string)) -> Resp {
	since, has := query_of(query, "since")
	n, ok := parse_int(since)
	if !has || !ok || n < 0 do return heavy_error(400)
	version := (now_ms() - heavy.version_epoch) / MINUTE
	return json_status(200, marshal(Version_Out{version, iso_string(heavy.version_epoch + version * MINUTE)}))
}
