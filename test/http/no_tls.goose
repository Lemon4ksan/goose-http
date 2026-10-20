// A program that imports http without http.tls builds without declaring
// goose-tls, and its serve_epoll and serve refuse a listener that asks for
// TLS before they open any.
import std;
import http from "../../";

fn main() {
    var cfg = http::Config { port: 1, .. };
    cfg.tls = true;
    var e = http::serve_epoll(cfg) { req, body, out => http::respond(out, 200, "text/plain", ""); };
    print("Config.tls: ", e.call, " ", e.code == http::EINVAL);
    e = http::serve(cfg) { req, body, out => http::respond(out, 200, "text/plain", ""); };
    print("serve, Config.tls: ", e.call, " ", e.code == http::EINVAL);
    cfg.tls = false;
    cfg.listeners.push(http::Listener { port: 2, tls: true });
    e = http::serve_epoll(cfg) { req, body, out => http::respond(out, 200, "text/plain", ""); };
    print("Listener.tls: ", e.call, " ", e.code == http::EINVAL);
    e = http::serve(cfg) { req, body, out => http::respond(out, 200, "text/plain", ""); };
    print("serve, Listener.tls: ", e.call, " ", e.code == http::EINVAL);
}
