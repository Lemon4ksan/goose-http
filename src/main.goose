import os;
import greeting;

fn main() {
    let argv = args();
    let who = if argv.len > 1 { argv[1] } else { "World" };
    var line: u8[>..] = [];
    greeting(line, who);
    write_stdout(line);
}
