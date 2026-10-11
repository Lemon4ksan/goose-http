// The benchmark server, serving with http::serve_epoll unless LOOP says
// otherwise: epoll on Linux, kqueue on macOS.
import http from "../";
import app;

fn main() { run("epoll"); }
