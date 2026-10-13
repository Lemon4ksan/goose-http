// The benchmark server, serving with http::serve_epoll unless LOOP says
// otherwise: epoll on Linux, kqueue on macOS.
import http from "../";
import compress from "github.com/kaitk/goose-compress@4bed2d2e6c99d42bd36e79b4dde4f6fd786d5148";
import app;

fn main() { run("epoll"); }
