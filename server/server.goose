// The benchmark server, serving with http::serve unless LOOP says otherwise:
// io_uring on Linux, IOCP on Windows.
import http from "../";
import compress from "github.com/kaitk/goose-compress@2c7df270b88ed8a00e2d73b6f84d50908cf5a558";
import app;

fn main() { run("uring"); }
