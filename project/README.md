# Project-Local Ticker

This folder contains the project-owned orchestration skeleton for `in-sequence`.

Meta should not decide what the coordinator, build loop, review loops, PM loop,
or process fixer mean. Meta should call `project/scripts/tick.sh`; this project
script owns the local roster and dispatch order.

The first version is intentionally small:

- write a coordinator cadence note when the coordinator has not run recently;
- write a process-fixer note when blocked requests exist;
- dispatch one runnable inbox request per tick by default;
- delegate actor execution to the existing multi-pass coordinator actor runner;
- leave blocked/malformed requests for a judgment actor instead of collapsing
  them into idle.

The roster lives at `project/scripts/loops.tsv`.
