// Tier D, writes with large bodies, under /api/v3, behind tier C's token,
// answered from the body alone as bench/rest/hyper's writes.rs answers them:
//
//   POST  /api/v3/imports                        a CSV: its rows, and each column's count and sum
//   POST  /api/v3/attachments                    multipart: the fields, the file's size and Adler-32
//   POST  /api/v3/bookings/batch                 JSON: each booking's id, or 422 with the errors
//   POST  /api/v3/forms                          a form: its fields, decoded
//
// start reads the head. A Writes then takes the body in the pieces the
// server reads it in: the CSV by hyper's port of Goose's reader, and the
// multipart body by multer, the streaming parser Rust's servers use. The
// batch and the form are collected whole, and the batch read by serde_json.
//
// A server that has an answer before the body's end, from push or from start,
// reads the rest of the body and drops it, unless the answer is to close.

use std::borrow::Cow;
use std::collections::VecDeque;
use std::convert::Infallible;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};

use bytes::Bytes;
use futures_util::Stream;
use serde::Deserialize;
use serde_json::value::RawValue;

use crate::heavy::has_bearer;
use crate::{decode_form, json_status, matches, parse_iso, Head, Method, Resp, StatusCode, MINUTE};

const IMPORT_LIMIT: usize = 16 << 20;
const BATCH_LIMIT: usize = 1 << 20;
const FORM_LIMIT: usize = 64 << 10;
const MAX_TEXT: usize = 1024;
const MAX_TEXTS: usize = 8;

fn error(status: StatusCode) -> Resp {
    let body: &'static str = match status {
        StatusCode::BAD_REQUEST => "{\"error\":\"bad_request\",\"status\":400}",
        StatusCode::UNAUTHORIZED => "{\"error\":\"unauthorized\",\"status\":401}",
        StatusCode::UNSUPPORTED_MEDIA_TYPE => "{\"error\":\"unsupported_media_type\",\"status\":415}",
        _ => "{\"error\":\"not_found\",\"status\":404}",
    };
    json_status(status, body)
}

// 413, closing the connection rather than reading the rest.
fn too_large() -> Resp {
    Resp { status: StatusCode::PAYLOAD_TOO_LARGE.0, json: false, close: true, body: Vec::new() }
}

// Whether the Content-Type's media type is want, ignoring case and parameters.
fn has_type(head: &Head, want: &str) -> bool {
    head.content_type.and_then(|v| std::str::from_utf8(v).ok())
        .is_some_and(|v| v.split(';').next().unwrap_or("").trim().eq_ignore_ascii_case(want))
}

// What a request's head makes of it: an answer, or a body to read.
pub enum Start {
    Answer(Resp),
    Read(Writes),
}

// Whether path is one of tier D's, for a server that frames a body by its
// route.
pub fn is_writes(path: &str) -> bool {
    path.starts_with("/api/v3/")
}

// The head's route and its body's limit, or the answer it gets: 404, 401, or
// 415 after the body, or 413 for a declared length over the limit.
fn route_of(head: &Head) -> Result<(u8, usize), Resp> {
    let post = head.method == Method::POST;
    let mut params = [""; 2];
    let mut on = |pattern: &str| post && matches(head.path, pattern, &mut params);
    let (route, want, limit) = if on("/api/v3/imports") {
        (1, "text/csv", IMPORT_LIMIT)
    } else if on("/api/v3/attachments") {
        (2, "multipart/form-data", IMPORT_LIMIT)
    } else if on("/api/v3/bookings/batch") {
        (3, "application/json", BATCH_LIMIT)
    } else if on("/api/v3/forms") {
        (4, "application/x-www-form-urlencoded", FORM_LIMIT)
    } else {
        return Err(error(StatusCode::NOT_FOUND));
    };
    if !has_bearer(head) {
        return Err(error(StatusCode::UNAUTHORIZED));
    }
    if !has_type(head, want) {
        return Err(error(StatusCode::UNSUPPORTED_MEDIA_TYPE));
    }
    let declared = head.content_length.and_then(|v| std::str::from_utf8(v).ok()?.parse::<usize>().ok());
    if declared.is_some_and(|n| n > limit) {
        return Err(too_large());
    }
    Ok((route, limit))
}

// 413, for a server that collects a body whole before start, if the body is
// over its route's limit, declared or with taken bytes of it read so far.
pub fn over_limit(head: &Head, taken: usize) -> Option<Resp> {
    match route_of(head) {
        Ok((_, limit)) if taken > limit => Some(too_large()),
        Err(r) if r.close => Some(r),
        _ => None,
    }
}

pub fn start(head: &Head) -> Start {
    let route = match route_of(head) {
        Ok((route, _)) => route,
        Err(r) => return Start::Answer(r),
    };
    Start::Read(match route {
        1 => Writes::Import { csv: Csv::new(), taken: 0 },
        2 => {
            let ctype = head.content_type.and_then(|v| std::str::from_utf8(v).ok()).unwrap_or("");
            let Ok(boundary) = multer::parse_boundary(ctype) else {
                return Start::Answer(error(StatusCode::BAD_REQUEST));
            };
            Writes::Attachment(Parts::new(boundary))
        }
        _ => Writes::Whole { batch: route == 3, limit: if route == 3 { BATCH_LIMIT } else { FORM_LIMIT },
                             body: Vec::new() },
    })
}

// A tier D body being read.
pub enum Writes {
    Import { csv: Csv, taken: usize },
    Attachment(Parts),
    Whole { batch: bool, limit: usize, body: Vec<u8> },
}

impl Writes {
    // Takes the next piece of the body, and answers if the answer comes
    // before its end.
    pub fn push(&mut self, data: &[u8]) -> Option<Resp> {
        match self {
            Writes::Import { csv, taken } => {
                *taken += data.len();
                if *taken > IMPORT_LIMIT {
                    return Some(too_large());
                }
                csv.piece(data);
                None
            }
            Writes::Attachment(parts) => parts.push(Bytes::copy_from_slice(data)),
            Writes::Whole { limit, body, .. } => {
                if body.len() + data.len() > *limit {
                    return Some(too_large());
                }
                body.extend_from_slice(data);
                None
            }
        }
    }

    // push for a server whose body comes in Bytes, which multer takes as
    // they are.
    pub fn push_bytes(&mut self, data: Bytes) -> Option<Resp> {
        match self {
            Writes::Attachment(parts) => parts.push(data),
            _ => self.push(&data),
        }
    }

    // The answer at the body's end.
    pub fn finish(self) -> Resp {
        match self {
            Writes::Import { csv, .. } => import(csv),
            Writes::Attachment(parts) => parts.finish(),
            Writes::Whole { batch: true, body, .. } => batch(&body),
            Writes::Whole { body, .. } => form(&body),
        }
    }
}

// An import's columns, of three kinds.
#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Text,
    Int,
    Dec,
}

const COLUMNS: [(&str, Kind); 6] = [("id", Kind::Int), ("date", Kind::Text), ("account", Kind::Text),
                                    ("description", Kind::Text), ("quantity", Kind::Int), ("amount", Kind::Dec)];

#[derive(PartialEq)]
enum Quote {
    Outside,
    Inside,
    After,
}

// A CSV body (RFC 4180, with LF or CRLF line ends) read piece by piece, as
// app.goose's Csv: where the reader is, the field it's in, and each column's
// count of non-empty cells and its sum, or its bytes for text.
pub struct Csv {
    record: i64,
    column: usize,
    quote: Quote,
    closed: bool,
    cr: bool,
    len: usize,
    value: i64,
    neg: bool,
    digits: i64,
    point: i64,
    number: bool,
    header: Vec<u8>,
    counts: [i64; 6],
    sums: [i64; 6],
    bad: i64,
}

impl Csv {
    fn new() -> Csv {
        Csv { record: 1, column: 0, quote: Quote::Outside, closed: false, cr: false, len: 0, value: 0, neg: false,
              digits: 0, point: -1, number: true, header: Vec::new(), counts: [0; 6], sums: [0; 6], bad: 0 }
    }

    fn fail(&mut self) {
        if self.bad == 0 {
            self.bad = self.record;
        }
    }

    fn text(&mut self, s: &[u8]) {
        let before = self.len;
        self.len += s.len();
        if self.record == 1 {
            if self.header.len() + s.len() <= 16 {
                self.header.extend_from_slice(s);
            }
            return;
        }
        let Some(&(_, kind)) = COLUMNS.get(self.column) else { return };
        if kind == Kind::Text {
            return;
        }
        for (i, &ch) in s.iter().enumerate() {
            if ch.is_ascii_digit() {
                if self.digits < 18 {
                    self.value = self.value * 10 + i64::from(ch - b'0');
                } else {
                    self.number = false;
                }
                self.digits += 1;
                if self.point >= 0 {
                    self.point += 1;
                }
            } else if ch == b'-' && before + i == 0 {
                self.neg = true;
            } else if ch == b'.' && kind == Kind::Dec && self.point < 0 && self.digits > 0 {
                self.point = 0;
            } else {
                self.number = false;
            }
        }
    }

    fn field_end(&mut self) {
        let k = self.column;
        if k >= COLUMNS.len() {
            self.fail();
        } else if self.record == 1 {
            if self.len > 16 || self.header != COLUMNS[k].0.as_bytes() {
                self.fail();
            }
        } else if self.len > 0 {
            let kind = COLUMNS[k].1;
            if kind == Kind::Text {
                self.counts[k] += 1;
                self.sums[k] += self.len as i64;
            } else if self.number && self.digits > 0 && (if kind == Kind::Dec { self.point == 2 } else { self.point < 0 }) {
                self.counts[k] += 1;
                self.sums[k] += if self.neg { -self.value } else { self.value };
            } else {
                self.fail();
            }
        }
        self.column += 1;
        self.len = 0;
        self.value = 0;
        self.neg = false;
        self.digits = 0;
        self.point = -1;
        self.number = true;
        self.closed = false;
        self.header.clear();
    }

    fn record_end(&mut self) {
        self.field_end();
        if self.column != COLUMNS.len() {
            self.fail();
        }
        self.record += 1;
        self.column = 0;
    }

    fn piece(&mut self, p: &[u8]) {
        let mut i = 0;
        while i < p.len() && self.bad == 0 {
            let ch = p[i];
            if self.quote == Quote::Inside {
                let Some(q) = memchr(b'"', &p[i..]) else {
                    self.text(&p[i..]);
                    return;
                };
                self.text(&p[i..i + q]);
                self.quote = Quote::After;
                i += q + 1;
                continue;
            }
            if self.quote == Quote::After {
                self.quote = Quote::Outside;
                if ch == b'"' {
                    self.text(&p[i..i + 1]);
                    self.quote = Quote::Inside;
                    i += 1;
                    continue;
                }
                self.closed = true;
            }
            if self.cr {
                self.cr = false;
                if ch != b'\n' {
                    self.fail();
                    return;
                }
            }
            if ch == b',' {
                self.field_end();
                i += 1;
            } else if ch == b'\n' {
                self.record_end();
                i += 1;
            } else if ch == b'\r' {
                self.cr = true;
                i += 1;
            } else if self.closed || ch == b'"' && self.len > 0 {
                self.fail();
            } else if ch == b'"' {
                self.quote = Quote::Inside;
                i += 1;
            } else {
                let j = p[i + 1..].iter().position(|&c| c == b',' || c == b'\n' || c == b'\r' || c == b'"')
                    .map_or(p.len(), |k| i + 1 + k);
                self.text(&p[i..j]);
                i = j;
            }
        }
    }

    fn end(&mut self) {
        if self.bad != 0 {
            return;
        }
        if self.quote == Quote::Inside || self.cr {
            self.fail();
            return;
        }
        if self.quote == Quote::After || self.closed || self.column > 0 || self.len > 0 {
            self.record_end();
        }
        if self.record == 1 {
            self.fail();
        }
    }
}

fn memchr(c: u8, s: &[u8]) -> Option<usize> {
    s.iter().position(|&b| b == c)
}

fn push_cents(out: &mut Vec<u8>, v: i64) {
    let a = v.unsigned_abs();
    out.extend_from_slice(format!("{}{}.{:02}", if v < 0 { "-" } else { "" }, a / 100, a % 100).as_bytes());
}

fn import(mut c: Csv) -> Resp {
    c.end();
    if c.bad != 0 {
        return json_status(StatusCode::BAD_REQUEST, format!("{{\"error\":\"bad_csv\",\"record\":{}}}", c.bad));
    }
    let mut buf = format!("{{\"rows\":{},\"columns\":[", c.record - 2).into_bytes();
    for (k, &(name, kind)) in COLUMNS.iter().enumerate() {
        if k > 0 {
            buf.push(b',');
        }
        buf.extend_from_slice(format!("{{\"name\":\"{name}\",\"count\":{}", c.counts[k]).as_bytes());
        match kind {
            Kind::Text => buf.extend_from_slice(format!(",\"bytes\":{}", c.sums[k]).as_bytes()),
            Kind::Int => buf.extend_from_slice(format!(",\"sum\":{}", c.sums[k]).as_bytes()),
            Kind::Dec => {
                buf.extend_from_slice(b",\"sum\":");
                push_cents(&mut buf, c.sums[k]);
            }
        }
        buf.push(b'}');
    }
    buf.extend_from_slice(b"]}");
    json_status(StatusCode::CREATED, buf)
}

// Adler-32 (RFC 1950), deferring the modulo as zlib does.
fn adler(a: &mut u32, b: &mut u32, data: &[u8]) {
    for block in data.chunks(5552) {
        for &c in block {
            *a += u32::from(c);
            *b += *a;
        }
        *a %= 65521;
        *b %= 65521;
    }
}

fn push_string(out: &mut Vec<u8>, s: &str) {
    serde_json::to_writer(&mut *out, s).unwrap();
}

// The body's pieces so far, for multer, which pulls them from a stream: it
// waits while none is queued and the body hasn't ended.
#[derive(Default)]
struct Queue {
    pieces: VecDeque<Bytes>,
    ended: bool,
}

struct Fed(Arc<Mutex<Queue>>);

impl Stream for Fed {
    type Item = Result<Bytes, Infallible>;

    fn poll_next(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let mut q = self.0.lock().unwrap();
        match q.pieces.pop_front() {
            Some(p) => Poll::Ready(Some(Ok(p))),
            None if q.ended => Poll::Ready(None),
            None => Poll::Pending,
        }
    }
}

// A multipart body read by multer as the server pushes it: each push polls
// the reader until it waits for the next piece. Nothing else wakes it, so
// it is polled with a waker that does nothing.
pub struct Parts {
    queue: Arc<Mutex<Queue>>,
    reader: Pin<Box<dyn Future<Output = Resp> + Send>>,
}

impl Parts {
    fn new(boundary: String) -> Parts {
        let queue = Arc::new(Mutex::new(Queue::default()));
        Parts { reader: Box::pin(read_parts(Fed(queue.clone()), boundary)), queue }
    }

    fn poll(&mut self) -> Option<Resp> {
        match self.reader.as_mut().poll(&mut Context::from_waker(Waker::noop())) {
            Poll::Ready(r) => Some(r),
            Poll::Pending => None,
        }
    }

    fn push(&mut self, data: Bytes) -> Option<Resp> {
        self.queue.lock().unwrap().pieces.push_back(data);
        self.poll()
    }

    fn finish(mut self) -> Resp {
        self.queue.lock().unwrap().ended = true;
        self.poll().unwrap_or_else(|| error(StatusCode::BAD_REQUEST))
    }
}

async fn read_parts(body: Fed, boundary: String) -> Resp {
    let limits = multer::Constraints::new().size_limit(multer::SizeLimit::new().whole_stream(IMPORT_LIMIT as u64));
    let mut parts = multer::Multipart::with_constraints(body, boundary, limits);
    let mut fields = Vec::new();
    let mut texts = 0;
    let mut file = None;
    loop {
        let mut field = match parts.next_field().await {
            Ok(Some(f)) => f,
            Ok(None) => break,
            Err(multer::Error::StreamSizeExceeded { .. }) => return too_large(),
            Err(_) => return error(StatusCode::BAD_REQUEST),
        };
        let name = field.name().unwrap_or("").to_owned();
        if name.is_empty() || name.len() > 64 {
            return error(StatusCode::BAD_REQUEST);
        }
        match field.file_name().filter(|f| !f.is_empty()).map(str::to_owned) {
            Some(filename) => {
                let ctype = field.content_type().map_or("application/octet-stream".into(), |m| m.to_string());
                if file.is_some() || filename.len() > 256 || ctype.len() > 128 {
                    return error(StatusCode::BAD_REQUEST);
                }
                let (mut a, mut b, mut size) = (1u32, 0u32, 0usize);
                loop {
                    match field.chunk().await {
                        Ok(Some(c)) => {
                            size += c.len();
                            adler(&mut a, &mut b, &c);
                        }
                        Ok(None) => break,
                        Err(multer::Error::StreamSizeExceeded { .. }) => return too_large(),
                        Err(_) => return error(StatusCode::BAD_REQUEST),
                    }
                }
                file = Some((name, filename, ctype, size, (b << 16) | a));
            }
            None => {
                if texts == MAX_TEXTS {
                    return error(StatusCode::BAD_REQUEST);
                }
                let mut value = Vec::new();
                loop {
                    match field.chunk().await {
                        Ok(Some(c)) if value.len() + c.len() <= MAX_TEXT => value.extend_from_slice(&c),
                        Ok(Some(_)) => return error(StatusCode::BAD_REQUEST),
                        Ok(None) => break,
                        Err(multer::Error::StreamSizeExceeded { .. }) => return too_large(),
                        Err(_) => return error(StatusCode::BAD_REQUEST),
                    }
                }
                if texts > 0 {
                    fields.push(b',');
                }
                push_string(&mut fields, &name);
                fields.push(b':');
                push_string(&mut fields, &String::from_utf8_lossy(&value));
                texts += 1;
            }
        }
    }
    let Some((field, filename, ctype, size, sum)) = file else {
        return json_status(StatusCode::UNPROCESSABLE_ENTITY,
                           "{\"error\":\"invalid\",\"errors\":[{\"field\":\"file\",\"message\":\"is required\"}]}");
    };
    let mut buf = b"{\"fields\":{".to_vec();
    buf.extend_from_slice(&fields);
    buf.extend_from_slice(b"},\"file\":{\"field\":");
    push_string(&mut buf, &field);
    buf.extend_from_slice(b",\"filename\":");
    push_string(&mut buf, &filename);
    buf.extend_from_slice(b",\"contentType\":");
    push_string(&mut buf, &ctype);
    buf.extend_from_slice(format!(",\"size\":{size},\"adler32\":{sum}}}}}").as_bytes());
    json_status(StatusCode::CREATED, buf)
}

#[derive(Deserialize)]
struct Batch<'a> {
    #[serde(borrow, rename = "batchId")]
    batch_id: Option<&'a RawValue>,
    #[serde(borrow)]
    bookings: Option<&'a RawValue>,
}

// A booking's members, each kept as its JSON text and checked by hand, so
// that each wrong one is a field error rather than a failed parse.
#[derive(Deserialize)]
struct BookingIn<'a> {
    #[serde(borrow, rename = "clientId")]
    client: Option<&'a RawValue>,
    #[serde(borrow, rename = "staffId")]
    staff: Option<&'a RawValue>,
    #[serde(borrow)]
    service: Option<&'a RawValue>,
    #[serde(borrow)]
    start: Option<&'a RawValue>,
    #[serde(borrow)]
    end: Option<&'a RawValue>,
    #[serde(borrow)]
    room: Option<&'a RawValue>,
    #[serde(borrow)]
    note: Option<&'a RawValue>,
}

// How a booking's member read: absent, wrong, or fine.
#[derive(PartialEq, Clone, Copy)]
enum How {
    Absent,
    Wrong,
    Fine,
}

// An integer from lo to hi: a JSON number with no fraction.
fn int_member(v: Option<&RawValue>, lo: f64, hi: f64) -> How {
    let Some(v) = v else { return How::Absent };
    let t = v.get();
    if !t.starts_with(|c: char| c == '-' || c.is_ascii_digit()) {
        return How::Wrong;
    }
    match t.parse::<f64>() {
        Ok(n) if n >= lo && n <= hi && n == n.trunc() => How::Fine,
        _ => How::Wrong,
    }
}

fn string_member(v: &RawValue) -> Option<Cow<'_, str>> {
    if !v.get().starts_with('"') {
        return None;
    }
    serde_json::from_str::<Cow<str>>(v.get()).ok()
}

fn is_service(s: &str) -> bool {
    let b = s.as_bytes();
    let Some(d) = memchr(b'-', b) else { return false };
    (2..=4).contains(&d) && b.len() == d + 3 && b[..d].iter().all(u8::is_ascii_uppercase)
        && b[d + 1].is_ascii_digit() && b[d + 2].is_ascii_digit()
}

fn time_member(v: Option<&RawValue>) -> (How, i64) {
    let Some(v) = v else { return (How::Absent, 0) };
    match string_member(v).and_then(|s| parse_iso(s.as_bytes())) {
        Some(t) => (How::Fine, t),
        None => (How::Wrong, 0),
    }
}

fn booking_error(errors: &mut Vec<u8>, k: usize, field: &str, message: &str) {
    if !errors.is_empty() {
        errors.push(b',');
    }
    errors.extend_from_slice(format!("{{\"index\":{k},\"field\":\"{field}\",\"message\":\"{message}\"}}").as_bytes());
}

fn check_field(errors: &mut Vec<u8>, k: usize, how: How, field: &str, message: &str) {
    match how {
        How::Absent => booking_error(errors, k, field, "is required"),
        How::Wrong => booking_error(errors, k, field, message),
        How::Fine => {}
    }
}

// POST /bookings/batch: each booking's id, the batch's id and its number,
// and their minutes, or 422 with each field that doesn't validate.
fn batch(body: &[u8]) -> Resp {
    let bad = || error(StatusCode::BAD_REQUEST);
    if body.trim_ascii_start().first() != Some(&b'{') {
        return bad();
    }
    let Ok(b) = serde_json::from_slice::<Batch>(body) else { return bad() };
    let Some(id) = b.batch_id.and_then(string_member).filter(|s| !s.is_empty() && s.len() <= 64) else {
        return bad();
    };
    let Some(list) = b.bookings.filter(|v| v.get().starts_with('[')) else { return bad() };
    let Ok(list) = serde_json::from_str::<Vec<&RawValue>>(list.get()) else { return bad() };
    let mut errors = Vec::new();
    let mut minutes = 0;
    for (k, raw) in list.iter().enumerate() {
        let x = if raw.get().starts_with('{') { serde_json::from_str::<BookingIn>(raw.get()).ok() } else { None };
        let Some(x) = x else {
            booking_error(&mut errors, k, "booking", "must be an object");
            continue;
        };
        check_field(&mut errors, k, int_member(x.client, 1.0, 1_000_000.0), "clientId",
                    "must be an integer from 1 to 1000000");
        check_field(&mut errors, k, int_member(x.staff, 1.0, 10.0), "staffId", "must be an integer from 1 to 10");
        let service = match x.service {
            None => How::Absent,
            Some(v) => if string_member(v).is_some_and(|s| is_service(&s)) { How::Fine } else { How::Wrong },
        };
        check_field(&mut errors, k, service, "service", "must be a service code");
        let (start, from) = time_member(x.start);
        let (end, to) = time_member(x.end);
        check_field(&mut errors, k, start, "start", "must be an ISO 8601 time");
        check_field(&mut errors, k, end, "end", "must be an ISO 8601 time");
        if start == How::Fine && end == How::Fine && (to <= from || to - from > 8 * 3_600_000) {
            booking_error(&mut errors, k, "end", "must be after start, by at most 8 hours");
        }
        check_field(&mut errors, k, int_member(x.room, 1.0, 6.0), "room", "must be an integer from 1 to 6");
        let note = match x.note {
            None => How::Fine,
            Some(v) if v.get() == "null" => How::Fine,
            Some(v) => if string_member(v).is_some_and(|s| s.len() <= 500) { How::Fine } else { How::Wrong },
        };
        check_field(&mut errors, k, note, "note", "must be a string of at most 500 bytes");
        minutes += (to - from) / MINUTE;
    }
    if !errors.is_empty() {
        let mut buf = b"{\"error\":\"invalid\",\"errors\":[".to_vec();
        buf.extend_from_slice(&errors);
        buf.extend_from_slice(b"]}");
        return json_status(StatusCode::UNPROCESSABLE_ENTITY, buf);
    }
    let mut buf = b"{\"batchId\":".to_vec();
    push_string(&mut buf, &id);
    buf.extend_from_slice(format!(",\"count\":{},\"minutes\":{minutes},\"ids\":[", list.len()).as_bytes());
    for k in 0..list.len() {
        if k > 0 {
            buf.push(b',');
        }
        push_string(&mut buf, &format!("{id}-{}", k + 1));
    }
    buf.extend_from_slice(b"]}");
    json_status(StatusCode::CREATED, buf)
}

// POST /forms: the form's fields, decoded, in order.
fn form(body: &[u8]) -> Resp {
    let mut buf = b"{\"fields\":{".to_vec();
    let mut n = 0;
    for pair in body.split(|&c| c == b'&').filter(|p| !p.is_empty()) {
        let eq = memchr(b'=', pair).unwrap_or(pair.len());
        let (Some(k), Some(v)) = (decode_form(&pair[..eq]), decode_form(pair.get(eq + 1..).unwrap_or(b""))) else {
            return error(StatusCode::BAD_REQUEST);
        };
        if n > 0 {
            buf.push(b',');
        }
        push_string(&mut buf, &String::from_utf8_lossy(&k));
        buf.push(b':');
        push_string(&mut buf, &String::from_utf8_lossy(&v));
        n += 1;
    }
    buf.extend_from_slice(format!("}},\"count\":{n}}}").as_bytes());
    json_status(StatusCode::OK, buf)
}
