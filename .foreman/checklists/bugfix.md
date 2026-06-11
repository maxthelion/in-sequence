# Bugfix gate

A bug report or feedback item is done when:

- [ ] The fix is committed with a message explaining cause, not just change.
- [ ] The full test suite is green (machine-state CoreAudio tests may be
      excluded only if they fail with the documented kAUStartIO/990s
      signature — note the exclusion in the commit message).
- [ ] A regression test pins the fix when the bug was behavioral (skip only
      for pure-visual changes, which need capture evidence instead).
- [ ] UI changes have capture evidence (QA capture run or targeted crop)
      showing the fixed state.
- [ ] `resolution.md` exists next to the report: what changed, where, and
      anything deliberately not done.
- [ ] If the report revealed a class (not an instance), the class is either
      swept or recorded in a code-health doc as ranked backlog.
