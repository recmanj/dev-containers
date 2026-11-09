# Development

## Building locally

`build.sh` builds images and their parents with Podman:

```sh
./build.sh t3                    # base → base-agent → claude → t3
./build.sh codex gemini          # shared parents are built once
./build.sh                       # everything
./build.sh --no-cache codex
./build.sh --dry-run t3          # print the podman commands
./build.sh --tag local t3        # tag as :local instead of :latest
```

Builds target `linux/amd64` like CI and stay in local storage; nothing is
pushed. By default they overwrite your local `:latest` tags, so the wrappers
and the Quadlet pick them up the next time a container is created
(`systemctl --user restart t3` for t3).

## Version updates

[Renovate](https://docs.renovatebot.com/) keeps every version pinned and
current (`renovate.json`). `FROM` images, GitHub Actions and pre-commit hooks
are found automatically. Tools downloaded in a Dockerfile need a comment
saying where they're released:

```dockerfile
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=2.103.3
```

Releases have to be 3 days old before Renovate picks them up. Minor, patch and
digest updates go into one `tooling` PR that merges once CI passes; majors get
their own PR. Pending updates are listed on the Dependency Dashboard issue.

## CI

- **Build** runs on pushes and PRs to `main`, nightly, and on demand. PR
  builds push images tagged `pr-<number>`, and child images build on their
  parent's PR tag, so a change to `base` is tested through the whole chain.
  Changes to docs and lint config don't trigger it.
- **Lint** runs [pre-commit](https://pre-commit.com/) with hadolint,
  shellcheck, actionlint and zizmor. Run `pre-commit install` to get the same
  checks locally.
- **Scan** runs Grype against the published images every night and reports
  findings under *Security → Code scanning*.
