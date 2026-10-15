// The Error a call returns: its code and the call it names.
import std;
import http from "../../";

fn main() {
    let s = http::stop_on_signals();
    assert(s.code == 0 && s.call == "sigaction");
    http::exit_on_error(s);
    let b, e = http::mail_open(4, 8);
    assert(e.code == 0 && e.call == "mail_open");
    http::exit_on_error(e);
    http::mail_close(b);
    let _, bad = http::mail_open(3, 8);
    assert(bad.code == http::EINVAL && bad.call == "mail_open");
    print(s.call, ": ", s.code);
    print(bad.call, " of 3 slots of 8: EINVAL");
}
