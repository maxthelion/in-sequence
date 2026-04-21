# Follow-ups from UI token extraction (v0.0.18-ui-tokens)

- **Adversarial-reviewer rule:** add a review pass that flags new `.font(.system(size:…))`, `cornerRadius: <literal>`, and `.opacity(<literal>)` uses in `Sources/UI/` where a matching token already exists.
- **ButtonStyle extraction:** several button and chip recipes are now visually clearer after the token pass, and some are close to rule-of-three promotion into named `ButtonStyle` values.
- **Theme propagation:** if light mode or accessibility theme variants become a real feature, `StudioTheme`, `StudioTypography`, `StudioMetrics`, and `StudioOpacity` should move behind an environment-driven theme object rather than static enums.
- **Oddball token audit:** a few intentionally distinct literals still exist for specialized UI affordances (`0.015`, `0.02`, `0.82`, `0.92`, tiny radii like `4/5/6`). Revisit them after another UI cleanup pass instead of forcing premature tokens now.
