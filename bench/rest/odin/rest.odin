// The REST benchmark's tiers (task 021) apart from any HTTP layer, for the Odin
// servers, odin-http and Tina: bench/rest/hyper's routes and answers behind a
// request head and a response of this package's own. A server parses a
// request's head into a Head, and sends the Resp it gets back:
//
//   handle(&head, body)     tiers A to C, with the whole body
//   writes_start(&head)     tier D, under /api/v3, which takes the body as the
//                           server reads it (writes.odin)
//
// Tier A is HttpArena's production-stack application layer, tier B snowtime's
// k6 hot path (snow.odin), tier C a clinic's schedule and records
// (heavy.odin), and tier D writes with large bodies, served beside tier C.
//
//   REST_DATA=DIR TIER=a|b|c|d WORKERS=n [JSON=template] <server> [port]
//
// Records are read from the dataset files with core:encoding/json into
// structs of the answers' shapes, times kept as the files write them, and
// serialized per request with core:encoding/json, Odin's JSON library.
// JSON=template answers from each record's JSON, written once at startup,
// with the per-request values added. Tier D's answers are written the one
// way. A response's body is allocated with context.temp_allocator, which the
// server frees after the response.
package rest

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Method :: enum u8 {
	Get,
	Head,
	Post,
	Patch,
	Other,
}

method_of :: proc(m: string) -> Method {
	switch m {
	case "GET":
		return .Get
	case "HEAD":
		return .Head
	case "POST":
		return .Post
	case "PATCH":
		return .Patch
	}
	return .Other
}

MAX_COOKIES :: 8

// The parts of a request's head the routes read. Of a field sent more than
// once, the first counts, but for Cookie.
Head :: struct {
	method:         Method,
	path:           string,
	query:          Maybe(string),
	authorization:  Maybe(string),
	origin:         Maybe(string),
	user_id:        Maybe(string),
	content_type:   Maybe(string),
	content_length: Maybe(string),
	cookies:        [MAX_COOKIES]string,
	n_cookies:      int,
}

// A head of method and the request target, its path and query apart.
head_init :: proc(method: Method, target: string) -> (h: Head) {
	h.method = method
	if q := strings.index_byte(target, '?'); q >= 0 {
		h.path = target[:q]
		h.query = target[q + 1:]
	} else {
		h.path = target
	}
	return
}

// Takes a field the routes read, of any case, and leaves the others.
head_field :: proc(h: ^Head, name: string, value: string) {
	slot: ^Maybe(string)
	switch len(name) {
	case 6:
		if strings.equal_fold(name, "cookie") {
			if h.n_cookies < MAX_COOKIES {
				h.cookies[h.n_cookies] = value
				h.n_cookies += 1
			}
			return
		}
		if strings.equal_fold(name, "origin") do slot = &h.origin
	case 9:
		if strings.equal_fold(name, "x-user-id") do slot = &h.user_id
	case 12:
		if strings.equal_fold(name, "content-type") do slot = &h.content_type
	case 13:
		if strings.equal_fold(name, "authorization") do slot = &h.authorization
	case 14:
		if strings.equal_fold(name, "content-length") do slot = &h.content_length
	}
	if slot != nil && slot^ == nil {
		slot^ = value
	}
}

// A response: its status, whether its body is JSON, and whether the server
// closes the connection after it, rather than read the rest of a body.
Resp :: struct {
	status: int,
	json:   bool,
	close:  bool,
	body:   []u8,
}

empty :: proc(status: int) -> Resp {
	return Resp{status = status}
}

json_status :: proc(status: int, body: []u8) -> Resp {
	return Resp{status = status, json = true, body = body}
}

json_text :: proc(status: int, body: string) -> Resp {
	return Resp{status = status, json = true, body = transmute([]u8)body}
}

// The reason phrase hyper writes for each status the routes answer.
reason :: proc(status: int) -> string {
	switch status {
	case 200:
		return "OK"
	case 201:
		return "Created"
	case 204:
		return "No Content"
	case 400:
		return "Bad Request"
	case 401:
		return "Unauthorized"
	case 403:
		return "Forbidden"
	case 404:
		return "Not Found"
	case 409:
		return "Conflict"
	case 411:
		return "Length Required"
	case 413:
		return "Payload Too Large"
	case 415:
		return "Unsupported Media Type"
	case 422:
		return "Unprocessable Entity"
	}
	return "Internal Server Error"
}

Rating :: struct {
	score: i64,
	count: i64,
}

Item :: struct {
	id:       i64,
	name:     string,
	category: string,
	price:    i64,
	quantity: i64,
	active:   bool,
	tags:     []string,
	rating:   Rating,
}

User :: struct {
	id:    i64,
	name:  string,
	email: string,
	plan:  string,
}

// A record with servedAt after its fields, as one JSON object.
Served_Item :: struct {
	using _:  Item,
	servedAt: i64,
}

Served_User :: struct {
	using _:  User,
	servedAt: i64,
}

Data :: struct {
	items:     []Item,
	users:     []User,
	// JSON=template's records, each without its closing brace.
	item_json: [][]u8,
	user_json: [][]u8,
	template:  bool,
}

data: Data

DAY :: 86_400_000
MINUTE :: 60_000

// The worker count and the port, from WORKERS and the first argument.
Config :: struct {
	workers: int,
	port:    int,
}

// Loads TIER's dataset from REST_DATA, and says so as server.
init :: proc(server: string) -> (c: Config) {
	dir := os.lookup_env("REST_DATA", context.allocator) or_else "build/rest"
	tier := os.lookup_env("TIER", context.allocator) or_else "a"
	data.template = (os.lookup_env("JSON", context.allocator) or_else "") == "template"
	records := 0
	switch tier {
	case "a":
		read_into(dir, "arena-items.json", &data.items)
		read_into(dir, "arena-users.json", &data.users)
		if data.template {
			data.item_json = make([][]u8, len(data.items))
			for &it, i in data.items do data.item_json[i] = without_brace(marshal(it, context.allocator))
			data.user_json = make([][]u8, len(data.users))
			for &u, i in data.users do data.user_json[i] = without_brace(marshal(u, context.allocator))
		}
		records = len(data.items)
	case "b":
		records = snow_load(dir, data.template)
	case "c", "d":
		records = heavy_load(dir, data.template)
	case:
		fmt.eprintln("TIER is a, b, c, or d")
		os.exit(2)
	}
	c.workers = os.get_processor_core_count()
	if v, ok := os.lookup_env("WORKERS", context.allocator); ok {
		if n, nok := strconv.parse_int(v, 10); nok && n > 0 do c.workers = n
	}
	c.port = 8080
	if len(os.args) > 1 {
		if p, ok := strconv.parse_int(os.args[1], 10); ok do c.port = p
	}
	fmt.printfln("%s: tier %s, %d records, %d workers on port %d, %s", server, tier, records, c.workers, c.port,
		"template" if data.template else "serialize")
	return
}

read_file :: proc(dir: string, name: string) -> []u8 {
	path := fmt.tprintf("%s/%s", dir, name)
	bytes, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("%s: %v; run bench/rest/gen.goose", path, err)
		os.exit(1)
	}
	return bytes
}

read_into :: proc(dir: string, name: string, ptr: ^$T) {
	if err := json.unmarshal(read_file(dir, name), ptr, .JSON); err != nil {
		fmt.eprintfln("%s: %v", name, err)
		os.exit(1)
	}
}

check :: proc(ok: bool, what: string) {
	if !ok {
		fmt.eprintln(what)
		os.exit(1)
	}
}

marshal :: proc(v: any, allocator := context.temp_allocator) -> []u8 {
	out, err := json.marshal(v, {}, allocator)
	assert(err == nil)
	return out
}

// Appends v's JSON.
write_json :: proc(b: ^strings.Builder, v: any) {
	opt: json.Marshal_Options
	err := json.marshal_to_builder(b, v, &opt)
	assert(err == nil)
}

// Appends s as a JSON string.
write_string :: proc(b: ^strings.Builder, s: string) {
	write_json(b, s)
}

builder :: proc(cap := 256) -> strings.Builder {
	return strings.builder_make(0, cap, context.temp_allocator)
}

done :: proc(b: ^strings.Builder) -> []u8 {
	return b.buf[:]
}

without_brace :: proc(v: []u8) -> []u8 {
	return v[:len(v) - 1]
}

// The time in seconds, which a coarse clock gives as cheaply.
now_s :: proc() -> i64 {
	return time.time_to_unix(time.now())
}

now_ms :: proc() -> i64 {
	return time.time_to_unix_nano(time.now()) / 1_000_000
}

// s as a number of decimal digits only, as Rust's parse takes one, but for a
// sign; ok is false for an empty s, another byte, or an overflow.
parse_digits :: proc(s: string) -> (v: i64, ok: bool) {
	if len(s) == 0 || len(s) > 18 do return
	for c in transmute([]u8)s {
		if c < '0' || c > '9' do return
		v = v * 10 + i64(c - '0')
	}
	return v, true
}

// A decimal integer with an optional sign, as Rust's i64 parse takes one.
parse_int :: proc(s: string) -> (v: i64, ok: bool) {
	if len(s) > 0 && (s[0] == '-' || s[0] == '+') {
		v, ok = parse_digits(s[1:])
		if s[0] == '-' do v = -v
		return
	}
	return parse_digits(s)
}

// id as a record's index, if it's one of n.
index_of :: proc(id: string, n: int) -> (int, bool) {
	s := id[1:] if len(id) > 0 && id[0] == '+' else id
	v, ok := parse_digits(s)
	if !ok || v < 1 || v > i64(n) do return 0, false
	return int(v - 1), true
}

// Whether path, split at '/', matches pattern's segments, a ":name" one taking
// any segment but an empty one, into params in order.
matches :: proc(path: string, pattern: string, params: ^[2]string) -> bool {
	n := 0
	p := path
	l := pattern
	for {
		seg, lit: string
		seg_ok, lit_ok: bool
		seg, p, seg_ok = next_segment(p)
		lit, l, lit_ok = next_segment(l)
		if !seg_ok && !lit_ok do return true
		if seg_ok != lit_ok do return false
		if len(lit) > 0 && lit[0] == ':' {
			if len(seg) == 0 do return false
			params[n] = seg
			n += 1
		} else if lit != seg {
			return false
		}
	}
}

// The segment of s up to its next '/', as Rust's split gives them: an empty
// s is one empty segment, and ok is false only after the last.
@(private)
next_segment :: proc(s: string) -> (seg: string, rest: string, ok: bool) {
	if s == "\x00" do return "", "", false
	if i := strings.index_byte(s, '/'); i >= 0 {
		return s[:i], s[i + 1:], true
	}
	return s, "\x00", true
}

// The value of key in the query, as sent; the first, if it repeats. A key
// without '=' has an empty value.
query_of :: proc(query: Maybe(string), key: string) -> (value: string, ok: bool) {
	q := query.? or_return
	for pair in strings.split_iterator(&q, "&") {
		if len(pair) == 0 do continue
		k, v := pair, ""
		if eq := strings.index_byte(pair, '='); eq >= 0 {
			k, v = pair[:eq], pair[eq + 1:]
		}
		if k == key do return v, true
	}
	return "", false
}

hex_digit :: proc(c: u8) -> (u8, bool) {
	switch c {
	case '0' ..= '9':
		return c - '0', true
	case 'a' ..= 'f':
		return c - 'a' + 10, true
	case 'A' ..= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}

// s with its percent-escapes decoded, and '+' as a space for a form, or ok
// false for a '%' without two hex digits after it.
decode :: proc(s: string, form := false) -> (out: string, ok: bool) {
	if strings.index_byte(s, '%') < 0 && (!form || strings.index_byte(s, '+') < 0) do return s, true
	b := make([dynamic]u8, 0, len(s), context.temp_allocator)
	for i := 0; i < len(s); {
		c := s[i]
		if c == '%' {
			if i + 2 >= len(s) do return
			a, aok := hex_digit(s[i + 1])
			d, dok := hex_digit(s[i + 2])
			if !aok || !dok do return
			append(&b, a * 16 + d)
			i += 3
		} else {
			append(&b, ' ' if form && c == '+' else c)
			i += 1
		}
	}
	return string(b[:]), true
}

// The whole of data as one JSON value, or ok false for anything else,
// trailing bytes included, which json.parse leaves unread.
parse_whole :: proc(data: []u8) -> (v: json.Value, ok: bool) {
	p := json.make_parser(data, .JSON, true, context.temp_allocator)
	context.allocator = context.temp_allocator
	value, err := json.parse_value(&p)
	if err != nil || p.curr_token.kind != .EOF do return
	return value, true
}

trim_ws :: proc(s: string) -> string {
	return strings.trim(s, " \t\n\r")
}

// Whether body's JSON value, if any, is an object.
is_object :: proc(body: []u8) -> bool {
	s := strings.trim_left(string(body), " \t\n\r")
	return len(s) > 0 && s[0] == '{'
}

// ms since the epoch as JavaScript's toISOString writes it, from Howard
// Hinnant's civil_from_days.
iso :: proc(ms: i64) -> (b: [24]u8) {
	digits :: proc(b: []u8, v: i64) {
		v := v
		#reverse for &c in b {
			c = '0' + u8(v % 10)
			v /= 10
		}
	}
	day := floor_div(ms, DAY)
	t := ms - day * DAY
	z := day + 719_468
	era := (z if z >= 0 else z - 146_096) / 146_097
	doe := z - era * 146_097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	m := mp + 3 if mp < 10 else mp - 9
	copy(b[:], "0000-00-00T00:00:00.000Z")
	digits(b[0:4], yoe + era * 400 + (1 if m <= 2 else 0))
	digits(b[5:7], m)
	digits(b[8:10], doy - (153 * mp + 2) / 5 + 1)
	digits(b[11:13], t / 3_600_000)
	digits(b[14:16], t / MINUTE % 60)
	digits(b[17:19], t / 1000 % 60)
	digits(b[20:23], t % 1000)
	return
}

floor_div :: proc(a, b: i64) -> i64 {
	q := a / b
	if (a % b != 0) && ((a < 0) != (b < 0)) do q -= 1
	return q
}

// A time as a JSON string, for a template's splice.
write_iso :: proc(b: ^strings.Builder, ms: i64) {
	s := iso(ms)
	strings.write_byte(b, '"')
	strings.write_bytes(b, s[:])
	strings.write_byte(b, '"')
}

// A time as a string in the temp allocator, for a struct to serialize.
iso_string :: proc(ms: i64) -> string {
	s := iso(ms)
	return strings.clone(string(s[:]), context.temp_allocator)
}

number_at :: proc(s: string, at: int, n: int) -> i64 {
	v: i64
	for c in transmute([]u8)s[at:at + n] {
		if c < '0' || c > '9' do return -1
		v = v * 10 + i64(c - '0')
	}
	return v
}

// Howard Hinnant's days_from_civil.
days_from :: proc(y, m, d: i64) -> i64 {
	yy := y - 1 if m <= 2 else y
	era := (yy if yy >= 0 else yy - 399) / 400
	yoe := yy - era * 400
	doy := (153 * (m - 3 if m > 2 else m + 9) + 2) / 5 + d - 1
	return era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
}

// "YYYY-MM-DDTHH:MM:SS.sssZ", or without the milliseconds, as ms since the
// epoch.
parse_iso :: proc(s: string) -> (i64, bool) {
	n := len(s)
	if !((n == 24 || n == 20) && s[4] == '-' && s[7] == '-' && s[10] == 'T' && s[13] == ':' && s[16] == ':' &&
		   s[n - 1] == 'Z') {
		return 0, false
	}
	y, m, d := number_at(s, 0, 4), number_at(s, 5, 2), number_at(s, 8, 2)
	h, mi, sec := number_at(s, 11, 2), number_at(s, 14, 2), number_at(s, 17, 2)
	ms: i64 = -1
	if n == 24 && s[19] == '.' {
		ms = number_at(s, 20, 3)
	} else if n == 20 {
		ms = 0
	}
	ok := y >= 0 && m >= 1 && m <= 12 && d >= 1 && d <= 31 && h >= 0 && h < 24 && mi >= 0 && mi < 60 &&
		sec >= 0 && sec < 60 && ms >= 0
	if !ok do return 0, false
	return days_from(y, m, d) * DAY + ((h * 60 + mi) * 60 + sec) * 1000 + ms, true
}

// "YYYY-MM-DD" as ms since the epoch at its midnight in UTC.
parse_day :: proc(s: string) -> (i64, bool) {
	if !(len(s) == 10 && s[4] == '-' && s[7] == '-') do return 0, false
	y, m, d := number_at(s, 0, 4), number_at(s, 5, 2), number_at(s, 8, 2)
	if !(y >= 0 && m >= 1 && m <= 12 && d >= 1 && d <= 31) do return 0, false
	return days_from(y, m, d) * DAY, true
}

// A file's time, which must be toISOString's.
must_iso :: proc(s: string, what: string) -> i64 {
	ms, ok := parse_iso(s)
	check(ok, what)
	return ms
}

// Prebuilt records joined with ',' between open and close.
join :: proc(b: ^strings.Builder, open: string, parts: [][]u8, close: string) {
	strings.write_string(b, open)
	for p, k in parts {
		if k > 0 do strings.write_byte(b, ',')
		strings.write_bytes(b, p)
	}
	strings.write_string(b, close)
}

// A record's response: its prebuilt JSON with servedAt spliced in, or the
// record and servedAt serialized.
served :: proc(record: any, prebuilt: []u8) -> Resp {
	now := now_s()
	if prebuilt != nil {
		b := builder(len(prebuilt) + 24)
		strings.write_bytes(&b, prebuilt)
		strings.write_string(&b, ",\"servedAt\":")
		strings.write_i64(&b, now)
		strings.write_byte(&b, '}')
		return json_status(200, done(&b))
	}
	switch r in record {
	case Item:
		return json_status(200, marshal(Served_Item{r, now}))
	case User:
		return json_status(200, marshal(Served_User{r, now}))
	}
	unreachable()
}

// A write's body: an object whose name, price, and quantity are each absent,
// null, or of their type.
valid_write :: proc(body: []u8) -> bool {
	if len(body) == 0 || body[0] != '{' do return false
	v := parse_whole(body) or_return
	obj := v.(json.Object) or_return
	for k, x in obj {
		if _, null := x.(json.Null); null do continue
		switch k {
		case "name":
			_ = x.(json.String) or_return
		case "price", "quantity":
			_ = x.(json.Integer) or_return
		}
	}
	return true
}

// Tiers A to C, and a 404 for any other path but tier D's, with the request's
// whole body.
handle :: proc(h: ^Head, body: []u8) -> Resp {
	path := h.path
	// Tier D's paths take only POST, through writes_start.
	if is_writes(path) do return writes_error(404)
	if strings.has_prefix(path, "/api/v1/") do return snow_handle(h, body)
	if strings.has_prefix(path, "/api/v2/") do return heavy_handle(h)
	if strings.has_prefix(path, "/api/items/") {
		i, ok := index_of(path[len("/api/items/"):], len(data.items))
		if !ok do return empty(404)
		if h.method == .Get {
			return served(data.items[i], data.item_json[i] if data.template else nil)
		}
		if h.method == .Post {
			return empty(204 if valid_write(body) else 422)
		}
	} else if path == "/api/me" && h.method == .Get {
		if v, ok := h.user_id.?; ok {
			if i, iok := index_of(v, len(data.users)); iok {
				return served(data.users[i], data.user_json[i] if data.template else nil)
			}
		}
		return empty(401)
	}
	return empty(404)
}
