// bench/vanilla-epoll's app on vanilla's io_uring backend, as HttpArena's
// vanilla-io_uring entry runs it (MDA2AV/HttpArena frameworks/vanilla-io_uring,
// at the commit in bench/build.sh): one worker thread per core, each with its
// own SO_REUSEPORT listener and io_uring ring, and handlers that write raw
// response bytes. Built with the entry's `v -prod -d vanilla_io_uring`, with V's
// default GC. A copy, so that bench/vanilla-epoll builds the binary its recorded
// results measured.
//
// /plaintext takes the entry's fast path for /pipeline, its plaintext test: a
// request starting `GET /plaintext ` is answered with fixed bytes before it is
// parsed. Everything else is parsed with vanilla's request parser.
//
// What the entry doesn't do that this benchmark needs: the Date field, which
// each worker caches as vanilla's examples/efficient_date does; 405 and 404;
// and WORKERS and the port as the first argument. vanilla reads its worker
// count from VANILLA_WORKERS before main runs, so main sets it from WORKERS
// and re-executes the program.
//
//     WORKERS=n bench-vanilla-io_uring [port]
module main

import vanilla.server
import vanilla.http1_1.request_parser
import vanilla.core
import json2
import os
import time

struct Message {
	message string
}

// A worker's state: the Date line, rebuilt when the second changes.
struct Worker {
mut:
	sec  i64
	date []u8 // "Date: <IMF-fixdate>\r\n"
}

fn new_worker() voidptr {
	return &Worker{
		date: []u8{cap: 40}
	}
}

@[direct_array_access]
fn (mut w Worker) refresh() {
	now := time.unix_now()
	if now == w.sec {
		return
	}
	w.sec = now
	w.date.clear()
	w.date << 'Date: '.bytes()
	time.utc().push_to_http_header(mut w.date)
	w.date << '\r\n'.bytes()
}

const status_ok = 'HTTP/1.1 200 OK\r\nServer: vanilla\r\n'.bytes()
const plaintext_tail = 'Content-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!'.bytes()
const not_allowed = 'HTTP/1.1 405 Method Not Allowed\r\nServer: vanilla\r\n'.bytes()
const not_allowed_tail = 'Allow: GET, HEAD\r\nContent-Length: 0\r\n\r\n'.bytes()
const not_found = 'HTTP/1.1 404 Not Found\r\nServer: vanilla\r\n'.bytes()
const empty_tail = 'Content-Length: 0\r\n\r\n'.bytes()
const bad_request = 'HTTP/1.1 400 Bad Request\r\nServer: vanilla\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'.bytes()

const plaintext_prefix = 'GET /plaintext '.bytes()

@[direct_array_access]
fn has_plaintext_prefix(b []u8) bool {
	if b.len < plaintext_prefix.len {
		return false
	}
	for i in 0 .. plaintext_prefix.len {
		if b[i] != plaintext_prefix[i] {
			return false
		}
	}
	return true
}

fn wb(mut out []u8, b []u8) {
	unsafe { out.push_many(b.data, b.len) }
}

fn handle(req_buffer []u8, mut out []u8, _ int, worker_state voidptr, mut _ core.EventLoop) core.Step {
	mut w := unsafe { &Worker(worker_state) }
	w.refresh()
	if has_plaintext_prefix(req_buffer) {
		wb(mut out, status_ok)
		wb(mut out, w.date)
		wb(mut out, plaintext_tail)
		return .done
	}
	mut req := request_parser.HttpRequest{
		buffer: req_buffer
	}
	if !request_parser.decode_into(mut req) {
		wb(mut out, bad_request)
		return .close
	}
	method := unsafe { tos(&req.buffer[req.method.start], req.method.len) }
	target := unsafe { tos(&req.buffer[req.path.start], req.path.len) }
	qpos := target.index_u8(`?`)
	route := if qpos < 0 { target } else { unsafe { tos(target.str, qpos) } }
	done := if has_close_option(req) { core.Step.close } else { core.Step.done }
	if route != '/plaintext' && route != '/json' {
		wb(mut out, not_found)
		wb(mut out, w.date)
		wb(mut out, empty_tail)
		return done
	}
	head := method == 'HEAD'
	if method != 'GET' && !head {
		wb(mut out, not_allowed)
		wb(mut out, w.date)
		wb(mut out, not_allowed_tail)
		return done
	}
	wb(mut out, status_ok)
	wb(mut out, w.date)
	if route == '/plaintext' {
		if head {
			wb(mut out, plaintext_tail[..plaintext_tail.len - 13])
		} else {
			wb(mut out, plaintext_tail)
		}
		return done
	}
	body := json2.encode(Message{ message: 'Hello, World!' })
	wb(mut out, 'Content-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n'.bytes())
	if !head {
		wb(mut out, body.bytes())
	}
	return done
}

// Whether the Connection field lists `close` (the entry's has_close_option).
fn has_close_option(req request_parser.HttpRequest) bool {
	c := req.get_header_value_slice('Connection') or { return false }
	end := c.start + c.len
	mut i := c.start
	for i + 5 <= end {
		if (req.buffer[i] | 0x20) == `c` && (req.buffer[i + 1] | 0x20) == `l`
			&& (req.buffer[i + 2] | 0x20) == `o` && (req.buffer[i + 3] | 0x20) == `s`
			&& (req.buffer[i + 4] | 0x20) == `e` {
			before := i == c.start || is_token_sep(req.buffer[i - 1])
			after := i + 5 == end || is_token_sep(req.buffer[i + 5])
			if before && after {
				return true
			}
		}
		i++
	}
	return false
}

fn is_token_sep(c u8) bool {
	return c == `,` || c == ` ` || c == `\t`
}

fn main() {
	workers := os.getenv('WORKERS')
	if workers != '' && os.getenv('VANILLA_WORKERS') != workers {
		os.setenv('VANILLA_WORKERS', workers, true)
		mut env := []string{}
		for k, v in os.environ() {
			env << '${k}=${v}'
		}
		os.execve(os.executable(), os.args[1..], env) or { panic(err) }
	}
	port := if os.args.len > 1 { os.args[1].int() } else { 8080 }
	println('vanilla-io_uring: ${core.max_thread_pool_size} workers on port ${port}')
	mut srv := server.new_server(server.ServerConfig{
		port:            port
		io_multiplexing: .io_uring
		handler:         handle
		make_state:      new_worker
	})!
	srv.run()
}
