#!/bin/bash
# Print each build's json_format_string scan loop: the lines around "cmp $0x5c,%al".
cd /mnt/c/Users/kait/projects/goose/goose-http/build/rest
for b in ${TAGS:-cx bp bw cm}; do
    echo "== $b"
    objdump -d --no-show-raw-insn rest-goose-$b |
        awk '/^[0-9a-f]+ <json_format_string/ { p = 1; n = 0; next }
             /^[0-9a-f]+ </ { p = 0 }
             p && /cmp +\$0x5c,%al/ && !n { n = 1; print prev; }
             p && n && n <= 12 { print; n++ }
             { prev = $0 }'
done
