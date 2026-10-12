// The REST benchmark's tiers (task 021) on Tina's HTTP server
// (pmbanugo/tina, src/extensions/http), configured as bench/tina is: one
// shard per worker, each a thread with its own io_uring loop and its own
// SO_REUSEPORT listener. The routes are bench/rest/odin's, answering as
// bench/rest/hyper does.
//
// Tina answers a path no route matches with a 404 of its own, and a method
// none takes with a 405, so the one handler here is routed every path of one
// to eight segments, for GET, POST, PATCH, PUT, and DELETE, and the app routes
// from there. The handler is an event route:
//
// - A request body is streamed, in the pieces each receive gives, so
//   tier D reads the CSV and the multipart body as they arrive. A body's
//   limit is the app's, per route; Tina's own, the routes' body_size_max, is
//   set past the largest.
// - A response is written to the connection's egress buffer in a fixed-length
//   stream, a buffer at a time: respond_bytes takes only a body that fits the
//   buffer whole. The buffer is built at 62 KB
//   (-define:HTTP_EGRESS_BUFFER_SIZE=63488), where the default 4 KB would
//   take 270 sends for tier C's megabyte. Its documented maximum, 65535,
//   doesn't compile: the buffer is part of a connection, which must fit in
//   64 KB.
// - A request allocates from an arena of its own, taken from its shard's pool
//   at its start and given back when its response is written: Tina's scratch
//   arena lasts one handler call, and a response can take several.
// - A response without a JSON body says text/plain, since a stream's begin
//   takes a content type; hyper's send none.
//
// Tier D fails its checker: after a few bodies sent in chunks of a few
// bytes, with pauses between them, on one kept-alive connection, reading a
// Body_Chunk's data faults (SIGSEGV), and Tina quarantines the shard. A
// handler that only sums each piece's bytes faults the same way, so tier D
// is a gap here (task 021).
//
//     REST_DATA=DIR TIER=a|b|c|d WORKERS=n [JSON=template] rest-tina [port]
package rest_tina

import "base:runtime"
import "core:mem"
import "core:mem/virtual"
import "core:strings"

import tina "deps:tina/src"
import http "deps:tina/src/extensions/http/server"

import rest "../odin"

// Past tier D's largest limit, 16 MB, so that the app refuses a body over its
// route's limit.
BODY_MAX :: 32 << 20
// Connection slots per shard: enough for the benchmark's 256 connections on
// one shard.
SLOTS :: 1024

Phase :: enum u8 {
	Idle,
	Whole, // collecting a body for tiers A to C
	Writes, // giving a tier D body to its reader
	Drain, // reading the rest of a body after its answer
	Send,
}

State :: struct {
	arena:  ^virtual.Arena,
	phase:  Phase,
	head:   rest.Head,
	writes: rest.Writes,
	whole:  [dynamic]u8,
	resp:   rest.Resp,
	sent:   int,
}

@(thread_local)
pool: [dynamic]^virtual.Arena
@(thread_local)
pool_ready: bool

acquire :: proc() -> ^virtual.Arena {
	if !pool_ready {
		pool = make([dynamic]^virtual.Arena, 0, 64, runtime.heap_allocator())
		pool_ready = true
	}
	if len(pool) > 0 do return pop(&pool)
	a := new(virtual.Arena, runtime.heap_allocator())
	err := virtual.arena_init_growing(a, 16 * mem.Megabyte)
	assert(err == nil)
	return a
}

release :: proc(s: ^State) {
	if s.arena == nil do return
	virtual.arena_free_all(s.arena)
	append(&pool, s.arena)
	s.arena = nil
	s.phase = .Idle
}

FIELDS :: [?]string{"Authorization", "Cookie", "Origin", "X-User-Id", "Content-Type", "Content-Length"}

start :: proc(s: ^State, request: ^http.Request, response: ^http.Response) -> http.Route_Step {
	method: rest.Method
	#partial switch http.method(request) {
	case .GET:
		method = .Get
	case .HEAD:
		method = .Head
	case .POST:
		method = .Post
	case .PATCH:
		method = .Patch
	case:
		method = .Other
	}
	// Copied: on a connection's later requests, the frame's bytes don't last
	// until the body's events.
	s.head = rest.head_init(method, strings.clone(string(http.target(request))))
	fields := FIELDS
	for name in fields {
		if v := http.header(request, name); v != nil do rest.head_field(&s.head, name, strings.clone(string(v)))
	}
	length := string(http.header(request, "Content-Length"))
	has_body := method != .Get && method != .Head &&
		((len(length) > 0 && length != "0") || len(http.header(request, "Transfer-Encoding")) > 0)
	writes := method == .Post && rest.is_writes(s.head.path)
	if !has_body {
		if writes {
			w, refused, ok := rest.writes_start(&s.head)
			s.resp = rest.writes_finish(&w) if ok else refused
		} else {
			s.resp = rest.handle(&s.head, nil)
		}
		return begin_send(s, response)
	}
	if http.expects_continue(request) do http.continue_100(response)
	if writes {
		w, refused, ok := rest.writes_start(&s.head)
		if !ok {
			s.resp = refused
			if refused.close do return begin_send(s, response)
			s.phase = .Drain
			return http.read_body()
		}
		s.writes = w
		s.phase = .Writes
		return http.read_body()
	}
	s.whole = make([dynamic]u8, 0, 1024)
	s.phase = .Whole
	return http.read_body()
}

chunk :: proc(s: ^State, response: ^http.Response, c: http.Body_Chunk) -> http.Route_Step {
	#partial switch s.phase {
	case .Writes:
		if len(c.data) > 0 {
			if r, early := rest.writes_push(&s.writes, c.data); early {
				s.resp = r
				if r.close || c.is_last do return begin_send(s, response)
				s.phase = .Drain
				return http.read_body()
			}
		}
		if c.is_last {
			s.resp = rest.writes_finish(&s.writes)
			return begin_send(s, response)
		}
	case .Whole:
		append(&s.whole, ..c.data)
		if c.is_last {
			s.resp = rest.handle(&s.head, s.whole[:])
			return begin_send(s, response)
		}
	case .Drain:
		if c.is_last do return begin_send(s, response)
	case:
		return http.close()
	}
	return http.read_body()
}

begin_send :: proc(s: ^State, response: ^http.Response) -> http.Route_Step {
	s.phase = .Send
	s.sent = 0
	_ = http.header_set(response, "Server", "tina")
	ctype := "application/json" if s.resp.json else "text/plain"
	if http.begin_fixed_stream(response, http.HTTP_Status(s.resp.status), ctype, u64(len(s.resp.body))) != .Begun {
		release(s)
		return http.close()
	}
	return send_more(s, response)
}

// Writes what the egress buffer takes of the body, and flushes it; the next
// part follows on Send_Ready.
send_more :: proc(s: ^State, response: ^http.Response) -> http.Route_Step {
	body := s.resp.body
	if s.sent < len(body) {
		s.sent += int(http.write_bytes(response, body[s.sent:]))
		if s.sent < len(body) do return http.flush()
	}
	close := s.resp.close
	// The body's last bytes are in the egress buffer.
	release(s)
	return http.close() if close else http.flush(true)
}

on_event :: proc(
	event: http.Route_Event,
	request: ^http.Request,
	response: ^http.Response,
	route_context: http.Route_Context,
	state: rawptr,
) -> http.Route_Step {
	s := cast(^State)state
	#partial switch _ in event {
	case http.Request_Start:
		s^ = {}
		s.arena = acquire()
	case http.Peer_Closed, http.Server_Drain:
		release(s)
		return http.close()
	}
	if s.arena == nil do return http.close()
	context.allocator = virtual.arena_allocator(s.arena)
	context.temp_allocator = context.allocator
	#partial switch e in event {
	case http.Request_Start:
		return start(s, request, response)
	case http.Body_Chunk:
		return chunk(s, response, e)
	case http.Send_Ready:
		return send_more(s, response)
	}
	return http.close()
}

main :: proc() {
	config := rest.init("rest-tina")
	workers := u8(clamp(config.workers, 1, 255))
	patterns := [?]string {
		"/:a",
		"/:a/:b",
		"/:a/:b/:c",
		"/:a/:b/:c/:d",
		"/:a/:b/:c/:d/:e",
		"/:a/:b/:c/:d/:e/:f",
		"/:a/:b/:c/:d/:e/:f/:g",
		"/:a/:b/:c/:d/:e/:f/:g/:h",
	}
	size := u16(size_of(State))
	routes := make([dynamic]http.Route)
	for p in patterns {
		append(&routes, http.get(p, on_event, size))
		append(&routes, http.post(p, on_event, size, BODY_MAX, .Streamed))
		append(&routes, http.patch(p, on_event, size, BODY_MAX, .Streamed))
		append(&routes, http.put(p, on_event, size, BODY_MAX, .Streamed))
		append(&routes, http.delete(p, on_event, size, BODY_MAX, .Streamed))
	}
	app := http.App {
		routes = routes[:],
	}
	// Reuse_Port needs more than one shard.
	// A streamed body's bytes that a receive leaves over, past the head or in
	// a chunk's size line, are kept in the pipeline tail, and the connection is
	// closed when they and the next receive don't fit it. Receives are up to
	// request_line_size_max + header_size_max, 10 KB, where the tail is 8 KB
	// by default, so the tail holds two receives here.
	limits := http.DEFAULT_LIMITS
	limits.pipeline_size_max = 2 * (limits.request_line_size_max + limits.header_size_max)
	server := http.Server {
		address      = tina.ipv4(0, 0, 0, 0, u16(config.port)),
		backlog      = 4096,
		ingress_mode = .Reuse_Port if workers > 1 else .Coordinator,
		app          = &app,
		limits       = limits,
	}
	spec := http.install(&server, workers, SLOTS)
	tina.tina_start(&spec)
}
