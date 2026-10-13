// Tier D, writes with large bodies, under /api/v3, behind tier C's token,
// answered from the body alone as bench/rest/hyper's writes.rs answers them:
//
//   POST  /api/v3/imports                        a CSV: its rows, and each column's count and sum
//   POST  /api/v3/attachments                    multipart: the fields, the file's size and Adler-32
//   POST  /api/v3/bookings/batch                 JSON: each booking's id, or 422 with the errors
//   POST  /api/v3/forms                          a form: its fields, decoded
//
// writes_start reads the head. A Writes then takes the body in the pieces the
// server reads it in: the CSV by a port of Goose's reader, and the multipart
// body by a reader of this file's own, since Odin has no multipart library;
// it accepts and refuses what multer, hyper's, does for the checker's bodies.
// The batch and the form are collected whole, and the batch read by
// core:encoding/json.
//
// A server that has an answer before the body's end, from writes_push or
// from writes_start, reads the rest of the body and drops it, unless the
// answer is to close. A Writes allocates with context.temp_allocator, which
// must last until writes_finish.
package rest

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"

IMPORT_LIMIT :: 16 << 20
BATCH_LIMIT :: 1 << 20
FORM_LIMIT :: 64 << 10
MAX_TEXT :: 1024
MAX_TEXTS :: 8

writes_error :: proc(status: int) -> Resp {
	switch status {
	case 400:
		return json_text(status, "{\"error\":\"bad_request\",\"status\":400}")
	case 401:
		return json_text(status, "{\"error\":\"unauthorized\",\"status\":401}")
	case 415:
		return json_text(status, "{\"error\":\"unsupported_media_type\",\"status\":415}")
	}
	return json_text(status, "{\"error\":\"not_found\",\"status\":404}")
}

// 413, closing the connection rather than reading the rest.
too_large :: proc() -> Resp {
	return Resp{status = 413, close = true}
}

// Whether the Content-Type's media type is want, ignoring case and parameters.
has_type :: proc(h: ^Head, want: string) -> bool {
	v := h.content_type.? or_return
	if semi := strings.index_byte(v, ';'); semi >= 0 do v = v[:semi]
	return strings.equal_fold(strings.trim_space(v), want)
}

// Whether path is one of tier D's, for a server that frames a body by its
// route.
is_writes :: proc(path: string) -> bool {
	return strings.has_prefix(path, "/api/v3/")
}

Writes_Kind :: enum u8 {
	Import,
	Attachment,
	Batch,
	Form,
}

// The head's route and its body's limit, or the answer it gets: 404, 401, or
// 415 after the body, or 413 for a declared length over the limit.
route_of :: proc(h: ^Head) -> (kind: Writes_Kind, limit: int, refused: Resp, ok: bool) {
	post := h.method == .Post
	params: [2]string
	want: string
	switch {
	case post && matches(h.path, "/api/v3/imports", &params):
		kind, want, limit = .Import, "text/csv", IMPORT_LIMIT
	case post && matches(h.path, "/api/v3/attachments", &params):
		kind, want, limit = .Attachment, "multipart/form-data", IMPORT_LIMIT
	case post && matches(h.path, "/api/v3/bookings/batch", &params):
		kind, want, limit = .Batch, "application/json", BATCH_LIMIT
	case post && matches(h.path, "/api/v3/forms", &params):
		kind, want, limit = .Form, "application/x-www-form-urlencoded", FORM_LIMIT
	case:
		refused = writes_error(404)
		return
	}
	if !has_bearer(h) {
		refused = writes_error(401)
		return
	}
	if !has_type(h, want) {
		refused = writes_error(415)
		return
	}
	if v, has := h.content_length.?; has {
		if n, nok := strconv.parse_int(v, 10); nok && n > limit {
			refused = too_large()
			return
		}
	}
	return kind, limit, {}, true
}

// 413, for a server that collects a body whole before writes_start, if the
// body is over its route's limit, declared or with taken bytes of it read
// so far.
over_limit :: proc(h: ^Head, taken: int) -> (Resp, bool) {
	_, limit, refused, ok := route_of(h)
	if ok && taken > limit do return too_large(), true
	if !ok && refused.close do return refused, true
	return {}, false
}

// A tier D body being read.
Writes :: struct {
	kind:  Writes_Kind,
	taken: int,
	limit: int,
	csv:   Csv,
	parts: Parts,
	whole: [dynamic]u8,
}

// What a request's head makes of it: an answer, or ok and a body to read.
writes_start :: proc(h: ^Head) -> (w: Writes, refused: Resp, ok: bool) {
	kind, limit, r, rok := route_of(h)
	if !rok do return {}, r, false
	w.kind, w.limit = kind, limit
	switch kind {
	case .Import:
		w.csv = csv_init()
	case .Attachment:
		boundary, bok := parse_boundary(h.content_type.? or_else "")
		if !bok do return {}, writes_error(400), false
		w.parts = parts_init(boundary)
	case .Batch, .Form:
		w.whole = make([dynamic]u8, 0, 4096, context.temp_allocator)
	}
	return w, {}, true
}

// Takes the next piece of the body, and answers if the answer comes before
// its end.
writes_push :: proc(w: ^Writes, piece: []u8) -> (Resp, bool) {
	w.taken += len(piece)
	if w.taken > w.limit do return too_large(), true
	switch w.kind {
	case .Import:
		csv_piece(&w.csv, piece)
	case .Attachment:
		return parts_push(&w.parts, piece)
	case .Batch, .Form:
		append(&w.whole, ..piece)
	}
	return {}, false
}

// The answer at the body's end.
writes_finish :: proc(w: ^Writes) -> Resp {
	switch w.kind {
	case .Import:
		return import_answer(&w.csv)
	case .Attachment:
		return parts_finish(&w.parts)
	case .Batch:
		return batch(w.whole[:])
	case .Form:
		return form(w.whole[:])
	}
	unreachable()
}

// An import's columns, of three kinds.
Kind :: enum u8 {
	Text,
	Int,
	Dec,
}

Column :: struct {
	name: string,
	kind: Kind,
}

COLUMNS :: [6]Column{{"id", .Int}, {"date", .Text}, {"account", .Text}, {"description", .Text}, {"quantity", .Int},
	{"amount", .Dec}}

Quote :: enum u8 {
	Outside,
	Inside,
	After,
}

// A CSV body (RFC 4180, with LF or CRLF line ends) read piece by piece, as
// rest.goose's Csv: where the reader is, the field it's in, and each column's
// count of non-empty cells and its sum, or its bytes for text.
Csv :: struct {
	record:  i64,
	column:  int,
	quote:   Quote,
	closed:  bool,
	cr:      bool,
	len:     int,
	value:   i64,
	neg:     bool,
	digits:  i64,
	point:   i64,
	number:  bool,
	header:  [16]u8,
	n_head:  int,
	counts:  [6]i64,
	sums:    [6]i64,
	bad:     i64,
}

csv_init :: proc() -> Csv {
	return Csv{record = 1, point = -1, number = true}
}

csv_fail :: proc(c: ^Csv) {
	if c.bad == 0 do c.bad = c.record
}

csv_text :: proc(c: ^Csv, s: []u8) {
	before := c.len
	c.len += len(s)
	if c.record == 1 {
		if c.n_head + len(s) <= 16 {
			copy(c.header[c.n_head:], s)
			c.n_head += len(s)
		}
		return
	}
	if c.column >= len(COLUMNS) do return
	columns := COLUMNS
	kind := columns[c.column].kind
	if kind == .Text do return
	for ch, i in s {
		if ch >= '0' && ch <= '9' {
			if c.digits < 18 {
				c.value = c.value * 10 + i64(ch - '0')
			} else {
				c.number = false
			}
			c.digits += 1
			if c.point >= 0 do c.point += 1
		} else if ch == '-' && before + i == 0 {
			c.neg = true
		} else if ch == '.' && kind == .Dec && c.point < 0 && c.digits > 0 {
			c.point = 0
		} else {
			c.number = false
		}
	}
}

csv_field_end :: proc(c: ^Csv) {
	columns := COLUMNS
	k := c.column
	if k >= len(columns) {
		csv_fail(c)
	} else if c.record == 1 {
		if c.len > 16 || string(c.header[:c.n_head]) != columns[k].name do csv_fail(c)
	} else if c.len > 0 {
		kind := columns[k].kind
		if kind == .Text {
			c.counts[k] += 1
			c.sums[k] += i64(c.len)
		} else if c.number && c.digits > 0 && (c.point == 2 if kind == .Dec else c.point < 0) {
			c.counts[k] += 1
			c.sums[k] += -c.value if c.neg else c.value
		} else {
			csv_fail(c)
		}
	}
	c.column += 1
	c.len = 0
	c.value = 0
	c.neg = false
	c.digits = 0
	c.point = -1
	c.number = true
	c.closed = false
	c.n_head = 0
}

csv_record_end :: proc(c: ^Csv) {
	csv_field_end(c)
	if c.column != len(COLUMNS) do csv_fail(c)
	c.record += 1
	c.column = 0
}

csv_piece :: proc(c: ^Csv, p: []u8) {
	i := 0
	for i < len(p) && c.bad == 0 {
		ch := p[i]
		if c.quote == .Inside {
			q := index_byte(p[i:], '"')
			if q < 0 {
				csv_text(c, p[i:])
				return
			}
			csv_text(c, p[i:i + q])
			c.quote = .After
			i += q + 1
			continue
		}
		if c.quote == .After {
			c.quote = .Outside
			if ch == '"' {
				csv_text(c, p[i:i + 1])
				c.quote = .Inside
				i += 1
				continue
			}
			c.closed = true
		}
		if c.cr {
			c.cr = false
			if ch != '\n' {
				csv_fail(c)
				return
			}
		}
		if ch == ',' {
			csv_field_end(c)
			i += 1
		} else if ch == '\n' {
			csv_record_end(c)
			i += 1
		} else if ch == '\r' {
			c.cr = true
			i += 1
		} else if c.closed || (ch == '"' && c.len > 0) {
			csv_fail(c)
		} else if ch == '"' {
			c.quote = .Inside
			i += 1
		} else {
			j := i + 1
			for j < len(p) && p[j] != ',' && p[j] != '\n' && p[j] != '\r' && p[j] != '"' do j += 1
			csv_text(c, p[i:j])
			i = j
		}
	}
}

csv_end :: proc(c: ^Csv) {
	if c.bad != 0 do return
	if c.quote == .Inside || c.cr {
		csv_fail(c)
		return
	}
	if c.quote == .After || c.closed || c.column > 0 || c.len > 0 do csv_record_end(c)
	if c.record == 1 do csv_fail(c)
}

index_byte :: proc(s: []u8, c: u8) -> int {
	return strings.index_byte(string(s), c)
}

write_cents :: proc(b: ^strings.Builder, v: i64) {
	a := v if v >= 0 else -v
	if v < 0 do strings.write_byte(b, '-')
	strings.write_i64(b, a / 100)
	strings.write_byte(b, '.')
	if a % 100 < 10 do strings.write_byte(b, '0')
	strings.write_i64(b, a % 100)
}

import_answer :: proc(c: ^Csv) -> Resp {
	csv_end(c)
	b := builder(512)
	if c.bad != 0 {
		strings.write_string(&b, "{\"error\":\"bad_csv\",\"record\":")
		strings.write_i64(&b, c.bad)
		strings.write_byte(&b, '}')
		return json_status(400, done(&b))
	}
	strings.write_string(&b, "{\"rows\":")
	strings.write_i64(&b, c.record - 2)
	strings.write_string(&b, ",\"columns\":[")
	columns := COLUMNS
	for col, k in columns {
		if k > 0 do strings.write_byte(&b, ',')
		strings.write_string(&b, "{\"name\":\"")
		strings.write_string(&b, col.name)
		strings.write_string(&b, "\",\"count\":")
		strings.write_i64(&b, c.counts[k])
		switch col.kind {
		case .Text:
			strings.write_string(&b, ",\"bytes\":")
			strings.write_i64(&b, c.sums[k])
		case .Int:
			strings.write_string(&b, ",\"sum\":")
			strings.write_i64(&b, c.sums[k])
		case .Dec:
			strings.write_string(&b, ",\"sum\":")
			write_cents(&b, c.sums[k])
		}
		strings.write_byte(&b, '}')
	}
	strings.write_string(&b, "]}")
	return json_status(201, done(&b))
}

// The boundary parameter of a multipart Content-Type, unquoted.
parse_boundary :: proc(ctype: string) -> (string, bool) {
	rest := ctype
	if semi := strings.index_byte(rest, ';'); semi >= 0 {
		rest = rest[semi + 1:]
	} else {
		return "", false
	}
	for param in strings.split_iterator(&rest, ";") {
		param := strings.trim_space(param)
		eq := strings.index_byte(param, '=')
		if eq < 0 || !strings.equal_fold(strings.trim_space(param[:eq]), "boundary") do continue
		v := strings.trim_space(param[eq + 1:])
		if len(v) >= 2 && v[0] == '"' && v[len(v) - 1] == '"' do v = v[1:len(v) - 1]
		if len(v) == 0 || len(v) > 200 do return "", false
		return v, true
	}
	return "", false
}

Parts_State :: enum u8 {
	Preamble, // before the first delimiter
	After_Delimiter, // a delimiter read: CRLF, or "--" for the last
	Head, // a part's head, up to its blank line
	Content, // a part's content, up to CRLF and the next delimiter
	Done,
}

// A multipart body read as it arrives. buf holds what isn't yet taken: a
// part's head, or the tail of a part's content that may start a delimiter.
Parts :: struct {
	delimiter: string, // "\r\n--" and the boundary
	state:     Parts_State,
	buf:       [dynamic]u8,
	// The part being read: a file's, or a text field's value.
	is_file:   bool,
	text:      [dynamic]u8,
	name:      string,
	// The fields so far, as JSON members, and the file.
	fields:    strings.Builder,
	texts:     int,
	has_file:  bool,
	file:      struct {
		field, filename, ctype: string,
		size:                   int,
		a, b:                   u32,
	},
}

parts_init :: proc(boundary: string) -> (p: Parts) {
	p.delimiter = strings.concatenate({"\r\n--", boundary}, context.temp_allocator)
	p.buf = make([dynamic]u8, 0, 4096, context.temp_allocator)
	p.text = make([dynamic]u8, 0, 256, context.temp_allocator)
	p.fields = builder(256)
	// The first delimiter has no CRLF before it; a body is read as if it had
	// one.
	append(&p.buf, "\r\n")
	return
}

// A Content-Disposition parameter's value, quoted or not.
disposition_param :: proc(v: string, key: string) -> (string, bool) {
	rest := v
	for param in strings.split_iterator(&rest, ";") {
		param := strings.trim_space(param)
		eq := strings.index_byte(param, '=')
		if eq < 0 || !strings.equal_fold(strings.trim_space(param[:eq]), key) do continue
		x := strings.trim_space(param[eq + 1:])
		if len(x) >= 2 && x[0] == '"' && x[len(x) - 1] == '"' do x = x[1:len(x) - 1]
		return x, true
	}
	return "", false
}

// Starts a part from its head: its name, and a file's name and type.
part_head :: proc(p: ^Parts, head: string) -> (Resp, bool) {
	name, filename, ctype: string
	has_name, has_file, has_type: bool
	rest := head
	for line in strings.split_iterator(&rest, "\r\n") {
		colon := strings.index_byte(line, ':')
		if colon < 0 do return writes_error(400), true
		key := strings.trim_space(line[:colon])
		value := strings.trim_space(line[colon + 1:])
		if strings.equal_fold(key, "content-disposition") {
			name, has_name = disposition_param(value, "name")
			filename, has_file = disposition_param(value, "filename")
		} else if strings.equal_fold(key, "content-type") {
			ctype, has_type = value, true
		}
	}
	if !has_name || len(name) == 0 || len(name) > 64 do return writes_error(400), true
	p.name = name
	p.is_file = has_file && len(filename) > 0
	if p.is_file {
		if !has_type do ctype = "application/octet-stream"
		if p.has_file || len(filename) > 256 || len(ctype) > 128 do return writes_error(400), true
		p.has_file = true
		p.file.field, p.file.filename, p.file.ctype = name, filename, ctype
		p.file.a, p.file.b = 1, 0
	} else {
		if p.texts == MAX_TEXTS do return writes_error(400), true
		clear(&p.text)
	}
	return {}, false
}

// Takes some of a part's content.
part_content :: proc(p: ^Parts, data: []u8) -> (Resp, bool) {
	if p.is_file {
		p.file.size += len(data)
		adler(&p.file.a, &p.file.b, data)
		return {}, false
	}
	if len(p.text) + len(data) > MAX_TEXT do return writes_error(400), true
	append(&p.text, ..data)
	return {}, false
}

// Ends a part at its delimiter.
part_end :: proc(p: ^Parts) {
	if p.is_file do return
	if p.texts > 0 do strings.write_byte(&p.fields, ',')
	write_string(&p.fields, p.name)
	strings.write_byte(&p.fields, ':')
	write_string(&p.fields, string(p.text[:]))
	p.texts += 1
}

parts_push :: proc(p: ^Parts, piece: []u8) -> (Resp, bool) {
	if p.state == .Done do return {}, false
	append(&p.buf, ..piece)
	return parts_run(p)
}

// Reads as far as buf allows.
parts_run :: proc(p: ^Parts) -> (Resp, bool) {
	d := transmute([]u8)p.delimiter
	for {
		buf := p.buf[:]
		switch p.state {
		case .Preamble, .Content:
			at := strings.index(string(buf), p.delimiter)
			if at < 0 {
				// Keep what may start a delimiter.
				keep := min(len(buf), len(d) - 1)
				if p.state == .Content {
					if r, done := part_content(p, buf[:len(buf) - keep]); done do return r, true
				}
				consume(p, len(buf) - keep)
				return {}, false
			}
			if p.state == .Content {
				if r, done := part_content(p, buf[:at]); done do return r, true
				part_end(p)
			}
			consume(p, at + len(d))
			p.state = .After_Delimiter
		case .After_Delimiter:
			if len(buf) < 2 do return {}, false
			if buf[0] == '-' && buf[1] == '-' {
				p.state = .Done
				return parts_answer(p), true
			}
			if buf[0] != '\r' || buf[1] != '\n' do return writes_error(400), true
			consume(p, 2)
			p.state = .Head
		case .Head:
			end := strings.index(string(buf), "\r\n\r\n")
			if end < 0 {
				if len(buf) > 8192 do return writes_error(400), true
				return {}, false
			}
			if r, refused := part_head(p, string(buf[:end])); refused do return r, true
			// The head's strings outlive buf's bytes.
			p.name = strings.clone(p.name, context.temp_allocator)
			if p.is_file {
				p.file.field = p.name
				p.file.filename = strings.clone(p.file.filename, context.temp_allocator)
				p.file.ctype = strings.clone(p.file.ctype, context.temp_allocator)
			}
			consume(p, end + 4)
			p.state = .Content
		case .Done:
			return {}, false
		}
	}
}

consume :: proc(p: ^Parts, n: int) {
	if n <= 0 do return
	copy(p.buf[:], p.buf[n:])
	resize(&p.buf, len(p.buf) - n)
}

// The answer at the body's end: a body without its close delimiter is
// refused, as multer refuses it.
parts_finish :: proc(p: ^Parts) -> Resp {
	if p.state == .Done do return parts_answer(p)
	return writes_error(400)
}

parts_answer :: proc(p: ^Parts) -> Resp {
	if !p.has_file {
		return json_text(422, "{\"error\":\"invalid\",\"errors\":[{\"field\":\"file\",\"message\":\"is required\"}]}")
	}
	b := builder(256 + strings.builder_len(p.fields))
	strings.write_string(&b, "{\"fields\":{")
	strings.write_string(&b, strings.to_string(p.fields))
	strings.write_string(&b, "},\"file\":{\"field\":")
	write_string(&b, p.file.field)
	strings.write_string(&b, ",\"filename\":")
	write_string(&b, p.file.filename)
	strings.write_string(&b, ",\"contentType\":")
	write_string(&b, p.file.ctype)
	strings.write_string(&b, ",\"size\":")
	strings.write_int(&b, p.file.size)
	strings.write_string(&b, ",\"adler32\":")
	strings.write_u64(&b, u64(p.file.b << 16 | p.file.a))
	strings.write_string(&b, "}}")
	return json_status(201, done(&b))
}

// Adler-32 (RFC 1950), deferring the modulo as zlib does.
adler :: proc(a: ^u32, b: ^u32, data: []u8) {
	rest := data
	for len(rest) > 0 {
		n := min(len(rest), 5552)
		for c in rest[:n] {
			a^ += u32(c)
			b^ += a^
		}
		a^ %= 65521
		b^ %= 65521
		rest = rest[n:]
	}
}

// How a booking's member read: absent, wrong, or fine.
How :: enum u8 {
	Absent,
	Wrong,
	Fine,
}

// An integer from lo to hi: a JSON number with no fraction.
int_member :: proc(obj: json.Object, key: string, lo, hi: f64) -> How {
	v, has := obj[key]
	if !has do return .Absent
	n: f64
	#partial switch x in v {
	case json.Integer:
		n = f64(x)
	case json.Float:
		n = x
	case:
		return .Wrong
	}
	return .Fine if n >= lo && n <= hi && n == f64(i64(n)) else .Wrong
}

is_service :: proc(s: string) -> bool {
	d := strings.index_byte(s, '-')
	if d < 2 || d > 4 || len(s) != d + 3 do return false
	for c in transmute([]u8)s[:d] do if c < 'A' || c > 'Z' do return false
	return s[d + 1] >= '0' && s[d + 1] <= '9' && s[d + 2] >= '0' && s[d + 2] <= '9'
}

time_member :: proc(obj: json.Object, key: string) -> (How, i64) {
	v, has := obj[key]
	if !has do return .Absent, 0
	s, is := v.(json.String)
	if !is do return .Wrong, 0
	t, ok := parse_iso(s)
	if !ok do return .Wrong, 0
	return .Fine, t
}

booking_error :: proc(errors: ^strings.Builder, k: int, field: string, message: string) {
	if strings.builder_len(errors^) > 0 do strings.write_byte(errors, ',')
	strings.write_string(errors, "{\"index\":")
	strings.write_int(errors, k)
	strings.write_string(errors, ",\"field\":\"")
	strings.write_string(errors, field)
	strings.write_string(errors, "\",\"message\":\"")
	strings.write_string(errors, message)
	strings.write_string(errors, "\"}")
}

check_field :: proc(errors: ^strings.Builder, k: int, how: How, field: string, message: string) {
	switch how {
	case .Absent:
		booking_error(errors, k, field, "is required")
	case .Wrong:
		booking_error(errors, k, field, message)
	case .Fine:
	}
}

// POST /bookings/batch: each booking's id, the batch's id and its number,
// and their minutes, or 422 with each field that doesn't validate.
batch :: proc(body: []u8) -> Resp {
	if !is_object(body) do return writes_error(400)
	v, ok := parse_whole(body)
	if !ok do return writes_error(400)
	b, is_obj := v.(json.Object)
	if !is_obj do return writes_error(400)
	id, is_id := b["batchId"].(json.String)
	if !is_id || len(id) == 0 || len(id) > 64 do return writes_error(400)
	list, is_list := b["bookings"].(json.Array)
	if !is_list do return writes_error(400)
	errors := builder(256)
	minutes: i64
	for raw, k in list {
		x, is_obj := raw.(json.Object)
		if !is_obj {
			booking_error(&errors, k, "booking", "must be an object")
			continue
		}
		check_field(&errors, k, int_member(x, "clientId", 1, 1_000_000), "clientId",
			"must be an integer from 1 to 1000000")
		check_field(&errors, k, int_member(x, "staffId", 1, 10), "staffId", "must be an integer from 1 to 10")
		service := How.Absent
		if s, has := x["service"]; has {
			str, is := s.(json.String)
			service = .Fine if is && is_service(str) else .Wrong
		}
		check_field(&errors, k, service, "service", "must be a service code")
		start, from := time_member(x, "start")
		end, to := time_member(x, "end")
		check_field(&errors, k, start, "start", "must be an ISO 8601 time")
		check_field(&errors, k, end, "end", "must be an ISO 8601 time")
		if start == .Fine && end == .Fine && (to <= from || to - from > 8 * 3_600_000) {
			booking_error(&errors, k, "end", "must be after start, by at most 8 hours")
		}
		check_field(&errors, k, int_member(x, "room", 1, 6), "room", "must be an integer from 1 to 6")
		note := How.Fine
		if n, has := x["note"]; has {
			#partial switch s in n {
			case json.Null:
			case json.String:
				if len(s) > 500 do note = .Wrong
			case:
				note = .Wrong
			}
		}
		check_field(&errors, k, note, "note", "must be a string of at most 500 bytes")
		minutes += (to - from) / MINUTE
	}
	if strings.builder_len(errors) > 0 {
		out := builder(strings.builder_len(errors) + 64)
		strings.write_string(&out, "{\"error\":\"invalid\",\"errors\":[")
		strings.write_string(&out, strings.to_string(errors))
		strings.write_string(&out, "]}")
		return json_status(422, done(&out))
	}
	out := builder(64 + len(list) * (len(id) + 8))
	strings.write_string(&out, "{\"batchId\":")
	write_string(&out, id)
	strings.write_string(&out, ",\"count\":")
	strings.write_int(&out, len(list))
	strings.write_string(&out, ",\"minutes\":")
	strings.write_i64(&out, minutes)
	strings.write_string(&out, ",\"ids\":[")
	for k in 0 ..< len(list) {
		if k > 0 do strings.write_byte(&out, ',')
		write_string(&out, fmt.tprintf("%s-%d", id, k + 1))
	}
	strings.write_string(&out, "]}")
	return json_status(201, done(&out))
}

// POST /forms: the form's fields, decoded, in order.
form :: proc(body: []u8) -> Resp {
	b := builder(len(body) + 64)
	strings.write_string(&b, "{\"fields\":{")
	n := 0
	rest := string(body)
	for pair in strings.split_iterator(&rest, "&") {
		if len(pair) == 0 do continue
		eq := strings.index_byte(pair, '=')
		k, v := pair, ""
		if eq >= 0 do k, v = pair[:eq], pair[eq + 1:]
		key, kok := decode(k, true)
		value, vok := decode(v, true)
		if !kok || !vok do return writes_error(400)
		if n > 0 do strings.write_byte(&b, ',')
		write_string(&b, key)
		strings.write_byte(&b, ':')
		write_string(&b, value)
		n += 1
	}
	strings.write_string(&b, "},\"count\":")
	strings.write_int(&b, n)
	strings.write_byte(&b, '}')
	return json_status(200, done(&b))
}
