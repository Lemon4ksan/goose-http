// The benchmark server, serving with http::serve unless LOOP says otherwise:
// io_uring on Linux, IOCP on Windows.
import http from "../";
import compress from "github.com/kaitk/goose-compress@v0.1.0";
import app;

fn main() { run("uring"); }
