// /plaintext and /json on Tina's HTTP server (pmbanugo/tina, src/extensions/http),
// in the shape of its own examples/http_server_for_bench.odin: one shard per
// worker, each a thread with its own io_uring loop on Linux and kqueue on
// macOS. With more than one shard, each accepts on a listener of its own,
// Tina's documented Reuse_Port ingress, which served 2.5 times the requests
// of its primary one, Coordinator, in task 019's first runs; INGRESS=
// coordinator picks Coordinator. The JSON body is written per request into a
// stack buffer, which Tina copies into the connection's.
//
//     WORKERS=n [INGRESS=coordinator] bench-tina [port]
package bench_tina

import "core:os"
import "core:strconv"

import tina "deps:tina/src"
import http "deps:tina/src/extensions/http/server"

server_header :: proc(response: ^http.Response) {
	_ = http.header_set(response, "Server", "tina")
}

plaintext :: proc(request: ^http.Request, response: ^http.Response) -> http.Route_Step {
	server_header(response)
	return http.respond_bytes(response, http.HTTP_STATUS_OK, "text/plain", transmute([]u8)string("Hello, World!"))
}

// Appends s to out at at as a JSON string, escaping what JSON requires.
json_string :: proc(out: []u8, at: int, s: string) -> int {
	hex := "0123456789abcdef"
	n := at
	out[n] = '"'
	n += 1
	for c in transmute([]u8)s {
		switch c {
		case '"', '\\':
			out[n] = '\\'
			out[n + 1] = c
			n += 2
		case 0 ..< 0x20:
			copy(out[n:], "\\u00")
			out[n + 4] = hex[c >> 4]
			out[n + 5] = hex[c & 15]
			n += 6
		case:
			out[n] = c
			n += 1
		}
	}
	out[n] = '"'
	return n + 1
}

json :: proc(request: ^http.Request, response: ^http.Response) -> http.Route_Step {
	server_header(response)
	buf: [64]u8
	n := copy(buf[:], "{\"message\":")
	n = json_string(buf[:], n, "Hello, World!")
	buf[n] = '}'
	return http.respond_bytes(response, http.HTTP_STATUS_OK, "application/json", buf[:n + 1])
}

main :: proc() {
	port: u16 = 8080
	if len(os.args) > 1 {
		if p, ok := strconv.parse_uint(os.args[1]); ok && p > 0 && p < 65536 do port = u16(p)
	}
	workers: u8 = 1
	if w, ok := os.lookup_env("WORKERS", context.temp_allocator); ok {
		if n, nok := strconv.parse_uint(w); nok && n > 0 && n < 256 do workers = u8(n)
	}
	// Reuse_Port needs more than one shard.
	ingress := http.Ingress_Mode.Reuse_Port if workers > 1 else .Coordinator
	if v, ok := os.lookup_env("INGRESS", context.temp_allocator); ok && v == "coordinator" {
		ingress = .Coordinator
	}

	app := http.App {
		routes = []http.Route{http.get("/plaintext", plaintext), http.get("/json", json)},
	}
	server := http.Server {
		address      = tina.ipv4(0, 0, 0, 0, port),
		backlog      = 4096,
		ingress_mode = ingress,
		app          = &app,
	}
	// Connection slots per shard: enough for the benchmark's 4,096 connections
	// on one shard.
	spec := http.install(&server, workers, 4096)
	tina.tina_start(&spec)
}
