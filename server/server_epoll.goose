// The benchmark server, serving with http::serve_epoll unless LOOP says
// otherwise: epoll on Linux, kqueue on macOS.
import http from "../";
import compress from "github.com/kaitk/goose-compress@2c7df270b88ed8a00e2d73b6f84d50908cf5a558";
import app;

fn main() { run("epoll"); }
