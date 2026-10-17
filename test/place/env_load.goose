// .env files (settings.goose): what env_load puts into the environment, that
// the real environment wins, that a missing file is no error, and the error
// for each kind of mistake. Each test runs in a directory of its own, where it
// writes its files. The package is declared by place.goose alone; the sidecar
// beside it names the C.
import std;
import os;
import place from "../../";

fn show(name: const u8[:]) {
    var v: u8[>..] = [];
    if env(name, v) { print(name, "=[", v, "]"); } else { print(name, " unset"); }
}

fn main() {
    assert(write_file("dev.env", """
        # development settings
        GOOSE_PLACE = place/dev.place
        export DB_URL=sqlite:dev.db   # a comment after a space
        GREETING="hello # not a comment"
        RAW='a\nb'
        ESCAPED="a\tb\"c\""
        EMPTY=
        HASH=a#b
        """));
    let n, err = http::env_load("dev.env");
    print("set ", n, ", error \"", err, "\"");
    for k in ["GOOSE_PLACE", "DB_URL", "GREETING", "RAW", "ESCAPED", "EMPTY", "HASH", "NOT_THERE"] { show(k); }

    // Loaded again with other values: what's set already stays.
    assert(write_file("other.env", "DB_URL=postgres://prod\nNEW=1\n"));
    let n2, err2 = http::env_load("other.env");
    print("again: set ", n2, ", error \"", err2, "\"");
    show("DB_URL");
    show("NEW");

    let n3, err3 = http::env_load("no-such.env");
    print("missing: set ", n3, ", error \"", err3, "\"");

    for text in ["JUST_A_NAME", "TWO WORDS=1", "OPEN=\"never closed", "=1"] {
        assert(write_file("bad.env", text));
        let k, e = http::env_load("bad.env");
        print(e);
    }
}
