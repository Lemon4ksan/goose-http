# Benchmarks

- Every number comes with how it was measured: machine, kernel, command, worker and
  connection counts, and run count. A result without them doesn't go in a doc.
- The competing servers run in their fastest documented configuration, built in release
  mode, with the same worker count as the Goose server. Losses are recorded as plainly as
  wins.
- A change made only for speed that shows no gain beyond the runs' spread is dropped, and
  its task records what it was, what it cost, and why it went, so it isn't proposed again
  (2026-10-14).
