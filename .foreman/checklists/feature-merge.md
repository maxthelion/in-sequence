# Feature merge gate

A feature branch merges to main when:

- [ ] Full suite green on the branch with main merged in (machine-state
      CoreAudio exclusions allowed only with the documented signature).
- [ ] The work still matches its raw intent entry in
      `docs/roadmap/intent.md` — reread the seed, not just the spec.
- [ ] Spec acceptance criteria each have evidence: a test, a capture, or a
      direct check. Unmet criteria are listed in the merge commit message
      as explicit exclusions, not silently dropped.
- [ ] UI surfaces have QA capture evidence (capture rows exist and were
      reviewed against `docs/ux-canon.md`).
- [ ] No new duplicate code paths: anything copied from an existing
      implementation either delegates to it or the duplication is recorded
      as a finding.
- [ ] `xcodegen generate` run in the main checkout after merge;
      `Sources/Resources/Info.plist` verified against HEAD.
- [ ] Post-merge: full suite green on main.
