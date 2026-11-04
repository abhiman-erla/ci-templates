# ci-templates

Shared GitHub Actions workflows for my projects. Public so any repo can call them.

## Workflows

| Workflow | What it does |
|---|---|
| `secret-scan.yml` | Scans the caller's full git history with gitleaks. No inputs. |
| `workflow-lint.yml` | Runs actionlint and zizmor on the caller's `.github/workflows`. Optional input `path`. Fails on any finding. |
| `scorecard.yml` | OpenSSF Scorecard for this repo. Weekly and manual. Informational, not a gate. |
| `self-test.yml` | Tests this repo. Also proves the tools fail on planted bad input. |

Tools are pinned by version and sha256 and installed from release binaries.
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

## Versioning

- Releases are immutable tags (`v1.0.0`, `v1.1.0`, ...). A tag is never moved or deleted.
- There is no moving `v1` tag.
- Callers pin the full commit SHA of a release and put the tag in a trailing comment.
- Dependabot in the caller bumps the SHA when a new release is cut.
- To change behaviour, cut a new release. Do not retag.
