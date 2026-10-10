import os;
import echo;

fn usage() {
    write_stderr("usage: server echo-blocking|echo-epoll [port]\n");
    exit(2);
}

fn main() {
    let argv = args();
    guard argv.len >= 2 else { usage(); }
    var port: i32 = 8080;
    if argv.len > 2 {
        let p, ok = parse_int(argv[2]);
        guard ok && p > 0 && p < 65536 else { usage(); }
        port = p as i32;
    }
    let mode = argv[1];
    if mode == "echo-blocking" { echo_blocking(port); }
    else if mode == "echo-epoll" { echo_epoll(port); }
    else { usage(); }
}
