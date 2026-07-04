# Visual Automation Blocked

Visual automation was not started because `SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION`
is not enabled.

This guard prevents unattended Foreman/Codex agents from triggering macOS TCC
permission prompts such as "bun would like to access data from other apps".

To run this scenario in an interactive, pre-authorized session:

```sh
SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1 PEEKABOO_OUTPUT_DIR=".meta/multipass/visual-review" <visual-scenario-command>
```

Unattended actors should treat this as `capture-permission-or-focus` /
`evidence-insufficient` and route a bounded interactive capture or process
repair instead of retrying.
