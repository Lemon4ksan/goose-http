// The Date header, the common fields, and is_field_value.
import std;
import http from "../../";

fn main() {
    let cases = [
        0, 951782400, 951868800, 1709251199, 1791633600, 4102444799, 4107542399,
        4107542400, 253402300799,
    ];
    let want = [
        "Thu, 01 Jan 1970 00:00:00 GMT",
        "Tue, 29 Feb 2000 00:00:00 GMT",
        "Wed, 01 Mar 2000 00:00:00 GMT",
        "Thu, 29 Feb 2024 23:59:59 GMT",
        "Sat, 10 Oct 2026 12:00:00 GMT",
        "Thu, 31 Dec 2099 23:59:59 GMT",
        "Sun, 28 Feb 2100 23:59:59 GMT",
        "Mon, 01 Mar 2100 00:00:00 GMT",
        "Fri, 31 Dec 9999 23:59:59 GMT",
    ];
    for t, i in cases {
        var d: u8[..32] = [];
        http::format_date(d, t);
        if d != want[i] {
            print("date of ", t, ": got '", d, "', want '", want[i], "'");
            assert(false);
        }
        print(t, ": ", d);
    }
    var common: u8[>..] = [];
    http::common_fields(common, "goose", 1791633600);
    assert(common == "Server: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\n");
    var bare: u8[>..] = [];
    http::common_fields(bare, "", 1791633600);
    assert(bare == "Date: Sat, 10 Oct 2026 12:00:00 GMT\r\n");
    assert(http::is_field_value("") && http::is_field_value("goose/1.0 (x\tz)"));
    assert(!http::is_field_value("a\r\nX: y") && !http::is_field_value(" a") && !http::is_field_value("a\t"));
    print("common fields, with and without Server; is_field_value");
}
