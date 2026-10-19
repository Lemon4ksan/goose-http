// The benchmark server, serving with http::serve unless LOOP says otherwise:
// io_uring on Linux, IOCP on Windows. It serves no TLS.
import http from "../";
import compress from "github.com/kaitk/goose-compress@v0.1.1";
import hash from "github.com/kaitk/goose-hash@v0.0.2";
import app;

fn main() { run("uring", no_tls, epoll_workers); }
