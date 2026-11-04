# ci-templates

Shared GitHub Actions workflows for my projects. Public so any repo can call them.

## Workflows

| Workflow | What it does |
|---|---|
| `secret-scan.yml` | Scans the caller's full git history with gitleaks. No inputs. |
| `workflow-lint.yml` | Runs actionlint and zizmor on the caller's `.github/workflows`. Optional input `path`. Fails on any finding. |
| `node-ci.yml` | Install, lint, test and audit a Node project. See [node-ci](#node-ci). |
| `docker-build.yml` | Build, boot-test, scan with Trivy and (on push to main) push an image to ghcr.io. See [docker-build](#docker-build). |
| `scorecard.yml` | OpenSSF Scorecard for this repo. Weekly and manual. Informational, not a gate. |
| `self-test.yml` | Tests this repo. Also proves the tools fail on planted bad input. |

Tools are pinned by version and sha256 and installed from release binaries.
Trivy is pinned by image digest and run as a container.
Planted bad workflows are in `fixtures/` (never run). The fake token for the
gitleaks test is generated at run time and never committed.

## Calling from another repo

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
permissions:
  contents: read
jobs:
  secrets-scan:
    uses: abhiman-erla/ci-templates/.github/workflows/secret-scan.yml@<sha> # v1.0.0
  workflow-lint:
    uses: abhiman-erla/ci-templates/.github/workflows/workflow-lint.yml@<sha> # v1.0.0
  ci-ok:
    if: always()
    needs: [secrets-scan, workflow-lint] # plus every code job, not deploy
    runs-on: ubuntu-latest
    steps:
      - uses: re-actors/alls-green@<sha> # v1.3.0
        with:
          jobs: ${{ toJSON(needs) }}
```

`ci-ok` is the only required check. A separate deploy job needs `ci-ok`.

## node-ci

Steps: checkout (full history), setup-node, install, lint, export `test-env`,
setup, test, then `npm audit`.

| Input | Default | Meaning |
|---|---|---|
| `working-directory` | `.` | Project directory, relative to the repo root |
| `node-version` | `22` | Passed to `actions/setup-node` |
| `install-command` | `npm ci` | Empty skips install **and** npm caching. Caching expects `package-lock.json` in the working directory |
| `lint-command` | `npm run lint --if-present` | Empty skips lint |
| `setup-command` | empty | Runs before the tests (start a service, seed data). Empty skips |
| `test-env` | empty | Extra environment for setup and test, one `KEY=value` per line |
| `test-command` | `npm test` | Empty skips the tests with a warning |
| `audit` | `true` | `false` skips audit |

No outputs.

- The four `*-command` inputs are trusted caller code. They run as
  `bash -e -o pipefail -c "$VAR"` and are never interpolated into a script.
- `test-env` is data. Each line must match `KEY=value` (no control
  characters). Lines that set `GITHUB_*`, `RUNNER_*`, `ACTIONS_*`, `LD_*`,
  `DYLD_*`, `PATH`, `BASH_ENV`, `BASHOPTS`, `SHELLOPTS`, `IFS`, `PS4`,
  `PROMPT_COMMAND`, `CDPATH`, `NODE_OPTIONS` or `NODE_PATH` fail the job. It
  applies to setup and test only, not to install or lint.
- Audit runs `npm audit --omit=dev --audit-level=high`, only when a
  `package.json` or lockfile changed between the base and head of the event.
  Any doubt (no base, a zero SHA, a failed `git diff`, `workflow_dispatch`)
  counts as changed.

## docker-build

Steps: checkout (full history), validate inputs, `docker build`, boot test,
Trivy scan, push.

| Input | Default | Meaning |
|---|---|---|
| `context` | `.` | Build context, relative to the repo root |
| `dockerfile` | empty | Relative to the repo root. Empty means `<context>/Dockerfile` |
| `image-name` | empty | Lower-case `ghcr.io/...` name. Empty means `ghcr.io/<owner>/<repo>` |
| `smoke-port` | `3000` | Port the app listens on inside the container |
| `smoke-path` | `/` | Path polled for a 2xx, for up to 30 seconds |
| `smoke-env` | empty | Environment for the boot-test container, one `KEY=value` per line |

| Output | Meaning |
|---|---|
| `image` | `name@digest` of the pushed image |
| `digest` | `sha256:...` digest the registry reported for the push |

**`image` and `digest` are empty unless the run pushed.** Only a `push` event on
`refs/heads/main` pushes; pull requests and other branches build, test and scan
only. Deploy from `image` or `digest`, never from a tag.

**The caller must grant `packages: write`.** A caller's token limits a called
workflow, so the job that calls `docker-build.yml` needs it, even though the
workflow also requests it itself. Without it the run fails at startup:

```yaml
jobs:
  image:
    uses: abhiman-erla/ci-templates/.github/workflows/docker-build.yml@<sha> # v1.1.0
    permissions:
      contents: read
      packages: write
    with:
      context: .
      smoke-path: /healthz
```

How it behaves:

- The image is built once, with `APP_VERSION=<commit sha>` as a build arg. The
  same local image is boot-tested, saved to a tar for Trivy, and pushed. There
  is no rebuild between scan and push, so the scanned image is the pushed one.
  `digest` is read from `docker push` output and checked with
  `docker manifest inspect`.
- Boot test: the image runs with `smoke-env`, the port published on
  `127.0.0.1`, and `smoke-path` is polled once a second for 30 seconds. It fails
  at once if the container exits.
- Trivy 0.69.3 runs as `aquasec/trivy@sha256:...` on the saved tar. No Docker
  socket is mounted. It fails on fixed HIGH or CRITICAL findings
  (`--ignore-unfixed --severity HIGH,CRITICAL`). It runs only when the
  Dockerfile, `.dockerignore` or a dependency manifest or lockfile changed
  (same doubt rule as the audit: unknown means run it). Trivy downloads its
  vulnerability database on each run.
- Login uses the caller's `GITHUB_TOKEN`; it is passed through the
  environment and removed again with `docker logout`.

## Versioning

- Releases are immutable tags (`v1.0.0`, `v1.1.0`, ...). A tag is never moved or deleted.
- There is no moving `v1` tag.
- Callers pin the full commit SHA of a release and put the tag in a trailing comment.
- Dependabot in the caller bumps the SHA when a new release is cut.
- To change behaviour, cut a new release. Do not retag.
