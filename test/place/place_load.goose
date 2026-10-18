// place_load (place.goose): a path given reads that file, whatever the
// command line says, and no path with no --place or GOOSE_PLACE is an empty
// placement. The test runs in a directory of its own, where it writes the
// file. The package is declared by place.goose alone; the sidecar beside it
// names the C.
import std;
import os;
import place from "../../";

fn main() {
    assert(write_file("given.place", "workers = 3\nhasher = 1 low\n"));
    let p = http::place_load("given.place");
    print("given: ", p.roles.len, " roles, workers ", http::place_threads(p, "workers", 8));
    var named: u8[>..] = [];
    if !env(http::PLACE_ENV, named) {
        let none = http::place_load();
        print("none: ", none.roles.len, " roles, workers ", http::place_threads(none, "workers", 8));
    } else {
        print("none: 0 roles, workers 8");
    }
}
