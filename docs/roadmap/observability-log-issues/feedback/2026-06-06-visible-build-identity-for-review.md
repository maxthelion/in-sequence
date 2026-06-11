# Feedback: Visible Build Identity For Product Review

Date: 2026-06-06
Area: Observability / build attribution / product review
Source: product-owner review

## Feedback

When reviewing the app, it is not clear which build is running. This makes
runtime regressions hard to attribute and makes product feedback less useful.

The build identity should be visible in the app, ideally in the window title
bar or an always-available debug/status surface. It should show enough to tell
what is being reviewed:

- commit SHA;
- branch;
- dirty/clean state;
- build timestamp or build attribution id;
- possibly whether the app came from `main` or a feature worktree.

## Current State

`scripts/open-latest-build.sh` writes build attribution manifests under
`.meta/multipass/runtime/build-attribution/`, and launch logs can sometimes
include commit/branch metadata. However:

- the visible UI does not show the build identity;
- some recent launch rows still reported `gitCommit=unknown` and
  `gitBranch=unknown`;
- the bundle build number still appears as `1`, so crash/log reports do not
  reliably map back to the attribution manifest unless the stamped metadata is
  also present.

## Desired Direction

Make build identity visible and reliable enough for product-owner review.

Minimum viable shape:

- stamp the app with commit, branch, dirty state, and build timestamp when
  building via the review/open script;
- show that identity in the main window title or a compact debug badge;
- include the same identity in launch logs and crash/log evidence;
- preserve honest language: report "observed in commit X", not "introduced by
  commit X" unless there is actual historical evidence.

