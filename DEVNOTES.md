# Developer Notes

Internal notes for building, testing, and releasing this workflow.

## Project layout

```
.
├── workflow/
│   ├── info.plist          # Alfred workflow definition
│                           #   (keyword, action, Text View, config)
│   ├── readme.md           # Workflow "About" text — injected into info.plist by build.sh
│   └── scripts/
│       ├── passthrough.sh  # Run Script action — instant pass-through, emits Q + N
│       ├── view.sh         # Text View Script Source — config, render, launch_job, run_view
│       └── common.sh       # Code shared by both scripts (json_escape)
├── build.sh                # Packages workflow/ → dist/*.alfredworkflow
└── .github/
    └── workflows/
        └── release.yml     # Builds + publishes the .alfredworkflow on tag push
```

## Build and install

From the repo root:

```bash
./build.sh
```

Produces `dist/alfred-claude-cli-v<version>.alfredworkflow` (a ZIP). The version comes
from `<key>version</key>` in `workflow/info.plist`. The build injects the Markdown
in `workflow/readme.md` into the plist's `readme` key (the workflow "About" text),
so edit that file rather than the plist string. Install it with:

```bash
open dist/alfred-claude-cli-v*.alfredworkflow
```

## Make a release

Releases are built and published by `.github/workflows/release.yml` on any
`v*.*.*` tag (`macos-latest` runner → `build.sh` → uploads
`dist/*.alfredworkflow` to a GitHub Release with auto-generated notes).

1. Bump `<key>version</key>` in `workflow/info.plist` (e.g. `0.1.0` → `0.2.0`).
2. Commit the bump.
3. Tag and push — the tag version should match the plist:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

4. The workflow runs and attaches `alfred-claude-cli-v0.2.0.alfredworkflow` to the
   release. You can also trigger it manually via **Actions → Release →
   Run workflow** (`workflow_dispatch`).

> Keep the tag and the plist `version` in sync — the built filename takes its
> version from the plist, not from the tag.

## How it runs

What happens, in order, when you type `ca <prompt>` and press Enter:

1. The **keyword input** fires the **Run Script** action (`passthrough.sh`).
2. `passthrough.sh` returns immediately — it just sets two Alfred variables:
   `Q` (the prompt) and `N` (a per-Enter nonce). It never waits on Claude, so the
   launcher doesn't block.
3. Alfred opens the **Text View**, whose Script Source (`view.sh`) runs and reads
   `Q` and `N`.
4. On the first render, `view.sh` starts Claude **detached** in the background
   (`claude -p <prompt> --model <model>`), writing its output to a cache file
   keyed by `N`.
5. While the job runs, `view.sh` shows a spinner and asks Alfred to re-poll via
   the JSON `"rerun"` key — so step 4's `view.sh` re-runs every interval.
6. Once the cache file exists, `view.sh` renders the answer (prompt on top) as
   Markdown and drops `"rerun"`, so polling stops.

The nonce `N` keys the cache per Enter, so each run is fresh and independent.
