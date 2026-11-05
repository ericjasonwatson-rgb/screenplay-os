# Campaign and Siri: isolated integration validation

Status: a reviewed conflict-resolution patch and reproducible detached test tree.
This does **not** merge PR3 into PR6, alter either branch's history, or add Siri to
the Campaign app build. Native runtime results belong to the exact Campaign head,
Siri head, composed tree, configuration and CI run reported by the runner.

## Integration contract

- Campaign remains a contextual sheet, not a sixth workspace. Its sheet, menu,
  project binding, persistence, source navigation and command guards are retained.
- Siri PR3 is pinned to `a45d29182535e5a90bdab9cb23096d3e4376fb26`. Its five
  choices remain Outline, Script, Shot, Boards and Edit. Only a mode name enters
  the pending preference; no screenplay, campaign, source text, path, media,
  approval record or provider credential enters the intent payload.
- The app resolves its one lifecycle conflict by keeping the Campaign sheet and
  adding both original Siri consumers: initial appearance and the request
  notification. Neither hook creates, opens, saves, changes or exports a project.
- A valid request is consumed once. When no blocking presentation is active, it
  invokes the existing `setWorkflowMode` navigation command. The intent itself
  still opens the app; native OS shortcut discovery/launch needs manual testing.
- A request received while Campaign is open is **discarded**, not queued. Closing,
  reopening or Go to Source cannot replay an older Siri request and override a
  newer explicit choice. Close the panel and issue the shortcut again.
- The same conservative guard covers title page, dialogue assistant, continuity
  bible, board generation, generation consent/cost ledger, package preview/editor,
  converted-copy receipt and the missing-source alert. Native modal windows and
  attached sheets cover file save/open/import and additional native dialogs.
  No modal is dismissed or accepted by Siri. This is deliberately app-wide: a
  sheet attached to another app window also blocks workspace navigation.
- The intent acknowledgment says the workspace was requested and explains the
  open-panel retry. It does not falsely report completed navigation when blocked.
- Original PR3 tests are retained byte-for-byte. The modal guard and acknowledgment
  changes exist only in the integration patch, not PR3's branch.

## Run

Use a full-history checkout so the merge base and reviewed Campaign ancestor are
available. Fetch PR3's actual head before each CI run; passing that ref to the
script makes a moved upstream head fail closed instead of silently testing an
outdated version. The runner itself does not fetch or access the network.

```sh
git fetch --no-tags origin pull/3/head
python3 -m unittest discover -s Tests/Integration -v
python3 Scripts/validate-campaign-siri-integration.py \
  --campaign-ref HEAD --siri-ref FETCH_HEAD --configuration debug
```

Repeat with `--configuration release`. The runner uses the complete, unfiltered
`Scripts/test.sh --no-parallel`, including Python, Node, all Swift tests, the
self-test and both inspector fixtures. No real provider or credentials are used.
A failed aggregate stays failed; source preparation is not a native test pass.

To inspect source composition on Linux without claiming native execution:

```sh
python3 Scripts/validate-campaign-siri-integration.py --prepare-only \
  --worktree /tmp/campaign-siri-review --keep-worktree
```

The destination must not exist and must be outside the source checkout. Without
`--keep-worktree`, the runner removes its detached worktree after completion or
failure. For a retained tree, remove it later using `git worktree remove --force`
with that exact disposable destination. Do not publish the temporary tree as a
feature branch or release build.

## How the composition is bounded

The runner requires a descendant of Campaign's reviewed `d09cd41587b3bf2637e3a33f8febb55eecbde77e`, the exact Siri pin, the original five-file Siri
change inventory, and exactly the known conflict in `ScreenplayOSApp.swift`.
It uses `git merge-tree` plumbing to write a candidate tree, then materializes it
in a **new detached worktree**. No `git merge`, merge commit, reset of the source
checkout, branch update, push or deploy occurs. The Campaign app source replaces
the conflict markers before the reviewed patch applies. Any changed context,
additional conflict or missing fixture fails rather than choosing a side silently.

If PR3 moves, review its new diff and update the pin and patch deliberately. If
Siri is already in Campaign history, retire this temporary integration runner.
Do not keep replaying a pre-merge patch after integration becomes ordinary code.

The output manifest records both source commit IDs, merge base, combined Git tree,
patch/test SHA-256, build configuration and native test result. It is printed to
CI and written to `.build/campaign-siri-integration.json` in the temporary tree.
The three original Siri tests plus six integration test functions (19 parameter
cases) run inside the full Swift suite. The latter cover all five modes; exact
screenplay/campaign file bytes; undo/redo/dirty state; Campaign selection/modal
preservation; Close/reopen and newer Go to Source precedence; ten other model
presentations; deterministic native-modal rejection; malformed and latest requests.

## Evidence and remaining gates

Local source checks on 2026-11-05: eight Python composition checks passed, including
pin expiry, wrong/missing refs, destination protection, exact original Siri test
preservation, detached history, unchanged source app/ref state, bounded composed
file inventory and modal-guard ordering. The pinned combined source tree prepares
and passes `git diff --cached --check` on Linux. No Swift toolchain or AppKit is
available there, so native compilation and runtime tests were **not run locally**.
Use the exact CI manifests for native outcomes; this note is not a green-CI claim.

Native unit tests inject the presence of a native modal window to remain
repeatable. They do not prove actual macOS sheet notification timing, Siri speech,
shortcut discovery, cold launch or keyboard focus. Before release, test:

1. Each workspace through Shortcuts with a saved project, then cold launch.
2. A request during Campaign text entry, import preview and native file picker.
   Confirm no navigation, focus loss, draft change, dismissal or provider send.
3. Close/Escape/reopen and Go to Source after a blocked request. Confirm no replay,
   then repeat the shortcut after closing and confirm one navigation.
4. Title/consent/preview panels and native Save/Open dialogs, including Cancel.
5. Multiple app windows with a sheet attached to a non-key window.

Native manual acceptance is separate from passing model/source tests. No live
provider call is needed for any of these checks.
