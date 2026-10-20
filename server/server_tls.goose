// The benchmark server with the epoll loop's TLS listener (https.goose), served
// with http::serve_epoll unless LOOP says otherwise: epoll on Linux, kqueue on
// macOS. This root declares goose-tls, and builds with OpenSSL;
// server_epoll.goose is the same server without TLS, which doesn't map it.
import http from "../";
import compress from "github.com/kaitk/goose-compress@v0.1.1";
import tls from "github.com/kaitk/goose-tls@v0.0.1";
import hash from "github.com/kaitk/goose-hash@v0.0.4";
import app;
import https;

fn main() { run("epoll", tls_listener, tls_workers); }
