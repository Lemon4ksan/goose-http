// The benchmark server, serving with http::serve unless LOOP says otherwise:
// io_uring on Linux, IOCP on Windows.
import http from "../";
import compress from "github.com/kaitk/goose-compress@3969fd1d173955fe0bfb438fa8b02d40d0fa123f";
import app;

fn main() { run("uring"); }
