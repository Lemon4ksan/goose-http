// The benchmark server, serving with http::serve unless LOOP says otherwise:
// io_uring on Linux, IOCP on Windows.
import http from "../";
import app;

fn main() { run("uring"); }
