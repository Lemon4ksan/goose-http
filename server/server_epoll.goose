// The benchmark server, serving with http::serve_epoll unless LOOP says
// otherwise: epoll on Linux, kqueue on macOS.
import http from "../";
import compress from "github.com/kaitk/goose-compress@v0.1.0";
import app;

fn main() { run("epoll"); }
