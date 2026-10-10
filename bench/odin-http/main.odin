// /plaintext and /json on odin-http, which runs an io_uring event loop per
// thread on Linux. The JSON body is marshalled per request by
// core:encoding/json into the request's temp allocator. respond_json would
// stream it with chunked encoding; the other servers send a Content-Length.
//
//     WORKERS=n bench-odin-http [port]
package bench_odin_http

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"

import http "deps:odin-http"

Message :: struct {
	message: string,
}

handle :: proc(req: ^http.Request, res: ^http.Response) {
	http.headers_set_unsafe(&res.headers, "server", "odin")
	path := req.url.path
	known := path == "/plaintext" || path == "/json"
	// HEAD arrives as GET: redirect_head_to_get is on by default.
	if known && req.line.(http.Requestline).method != .Get {
		http.headers_set_unsafe(&res.headers, "allow", "GET, HEAD")
		http.respond(res, http.Status.Method_Not_Allowed)
		return
	}
	switch path {
	case "/plaintext":
		res.status = .OK
		http.headers_set_content_type(&res.headers, "text/plain")
		http.body_set(res, "Hello, World!")
		http.respond(res)
	case "/json":
		body, err := json.marshal(Message{message = "Hello, World!"}, allocator = context.temp_allocator)
		if err != nil {
			http.respond(res, http.Status.Internal_Server_Error)
			return
		}
		res.status = .OK
		http.headers_set_content_type(&res.headers, "application/json")
		http.body_set(res, body)
		http.respond(res)
	case:
		http.respond(res, http.Status.Not_Found)
	}
}

main :: proc() {
	opts := http.Default_Server_Opts
	opts.thread_count = os.get_processor_core_count()
	if v, ok := os.lookup_env("WORKERS", context.allocator); ok {
		n, nok := strconv.parse_int(v)
		if !nok || n < 1 {
			fmt.eprintln("WORKERS must be a positive number")
			os.exit(2)
		}
		opts.thread_count = n
	}
	port := 8080
	if len(os.args) > 1 {
		port, _ = strconv.parse_int(os.args[1])
	}
	fmt.printfln("odin-http: %d workers on port %d", opts.thread_count, port)

	s: http.Server
	err := http.listen(&s, net.Endpoint{address = net.IP4_Any, port = port}, opts)
	fmt.assertf(err == nil, "listen: %v", err)
	// core:net's accept sets TCP_NODELAY by default, but the io_uring accept
	// odin-http uses doesn't. Without it, Nagle holds back each pipelined
	// response until the one before is acknowledged. Accepted sockets copy
	// the option from the listener.
	opt_err := net.set_option(s.tcp_sock, .TCP_Nodelay, true)
	fmt.assertf(opt_err == nil, "TCP_NODELAY: %v", opt_err)
	err = http.serve(&s, http.handler(handle))
	fmt.assertf(err == nil, "server stopped with error: %v", err)
}
