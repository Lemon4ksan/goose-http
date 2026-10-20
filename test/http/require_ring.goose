// Config.require_ring: serve refuses to emulate the ring, before it opens a
// listener. Where the platform's own ring starts, serve would run, so only
// the refusal is checked, and only where the ring would be emulated.
import std;
import http from "../../";

fn main() {
    var cfg = http::Config { port: 1, require_ring: true, emulate_ring: true, .. };
    var e = http::serve(cfg) { req, body, out => http::respond(out, 200, "text/plain", ""); };
    print("emulated and required: ", e.call, " ", e.code == http::EINVAL);

    cfg.emulate_ring = false;
    let probe = http::ring_probe();
    var refused = true;
    if probe < 0 {
        e = http::serve(cfg) { req, body, out => http::respond(out, 200, "text/plain", ""); };
        refused = e.call == "io_uring" && e.code == -probe;
    }
    print("required where the ring is emulated: ", refused);
}
