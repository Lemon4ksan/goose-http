// The REST benchmark's tiers (task 021) on odin-http, configured as
// bench/odin-http is: an io_uring event loop per thread, accepting on one
// shared listener, with TCP_NODELAY set on it. The routes are
// bench/rest/odin's, answering as bench/rest/hyper does.
//
// odin-http hands a handler a request's body whole, read into its scanner
// and, for a chunked one, decoded into the connection's temp allocator, so
// tier D's bodies are read whole here: the CSV and the multipart body are
// given to their readers in one piece. A handler that answers without
// reading the body has it discarded up to 256 KB, and the connection closed
// past that, so every body is read before the answer.
//
//     REST_DATA=DIR TIER=a|b|c|d WORKERS=n [JSON=template] rest-odin-http [port]
package rest_odin_http

import "core:fmt"
import "core:net"

import http "deps:odin-http"

import rest "../odin"

method_of :: proc(req: ^http.Request) -> rest.Method {
	if req.is_head do return .Head
	#partial switch req.line.(http.Requestline).method {
	case .Get:
		return .Get
	case .Post:
		return .Post
	case .Patch:
		return .Patch
	}
	return .Other
}

head_of :: proc(req: ^http.Request) -> rest.Head {
	h := rest.head_init(method_of(req), req.url.raw)
	for name, value in req.headers._kv do rest.head_field(&h, name, value)
	return h
}

send :: proc(res: ^http.Response, r: rest.Resp) {
	res.status = http.Status(r.status)
	http.headers_set_unsafe(&res.headers, "server", "odin")
	if r.json do http.headers_set_content_type(&res.headers, "application/json")
	if r.close do http.headers_set_close(&res.headers)
	if len(r.body) > 0 do http.body_set(res, r.body)
	http.respond(res)
}

// A request waiting for its body.
Pending :: struct {
	head: rest.Head,
	res:  ^http.Response,
}

handle :: proc(req: ^http.Request, res: ^http.Response) {
	p := new(Pending, context.temp_allocator)
	p.head = head_of(req)
	p.res = res
	// http.body on a request without a body marks the body as failed, which
	// closes the connection, so only a POST or PATCH body is read.
	if p.head.method != .Post && p.head.method != .Patch {
		send(res, rest.handle(&p.head, nil))
		return
	}
	if rest.is_writes(p.head.path) {
		_, limit, refused, ok := rest.route_of(&p.head)
		if !ok && refused.close {
			send(res, refused)
			return
		}
		// Past the limit, the body is refused with 413 before it's read
		// further, as hyper's Limited does.
		http.body(req, limit if ok else rest.IMPORT_LIMIT, p, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
			p := cast(^Pending)user
			if err != nil {
				status := http.body_error_status(err)
				send(p.res, rest.too_large() if status == .Payload_Too_Large else rest.writes_error(400))
				return
			}
			w, refused, ok := rest.writes_start(&p.head)
			if !ok {
				send(p.res, refused)
				return
			}
			r, early := rest.writes_push(&w, transmute([]u8)body)
			send(p.res, r if early else rest.writes_finish(&w))
		})
		return
	}
	http.body(req, rest.FORM_LIMIT, p, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		p := cast(^Pending)user
		if err != nil {
			send(p.res, rest.Resp{status = int(http.body_error_status(err)), close = true})
			return
		}
		send(p.res, rest.handle(&p.head, transmute([]u8)body))
	})
}

main :: proc() {
	config := rest.init("rest-odin-http")
	opts := http.Default_Server_Opts
	opts.thread_count = config.workers
	s: http.Server
	err := http.listen(&s, net.Endpoint{address = net.IP4_Any, port = config.port}, opts)
	fmt.assertf(err == nil, "listen: %v", err)
	// core:net's accept sets TCP_NODELAY by default, but the io_uring accept
	// odin-http uses doesn't. Accepted sockets copy the option from the
	// listener.
	opt_err := net.set_option(s.tcp_sock, .TCP_Nodelay, true)
	fmt.assertf(opt_err == nil, "TCP_NODELAY: %v", opt_err)
	err = http.serve(&s, http.handler(handle))
	fmt.assertf(err == nil, "server stopped with error: %v", err)
}
