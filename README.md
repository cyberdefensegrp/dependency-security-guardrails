# cdg-dependency-security-guardrails

Automated Dependency Security Guardrails defaults for npm and Python projects. Prevents the class of attacks seen in the [Axios npm compromise](https://snyk.io/blog/axios-npm-package-compromised-supply-chain-attack-delivers-cross-platform/) (March 2026, UNC1069/DPRK) and [LiteLLM PyPI compromise](https://docs.litellm.ai/blog/security-update-march-2026) (March 2026, TeamPCP).

## What this does

| Layer | What it catches |
|---|---|
| `ignore-scripts=true` | Blocks postinstall hooks (Axios attack vector) |
| Exact version pins | Prevents auto-pulling compromised new versions |
| Hash-verified installs (uv) | Detects tampered wheels/tarballs at install time |
| Provenance checks | Flags packages missing SLSA/OIDC build attestations |
| Lockfile diff warnings | Surfaces dependency changes for human review |
| pip-audit / npm audit | Catches known CVEs in your dependency tree |

## Quick start

```bash
# Clone the repo
git clone https://github.com/your-org/cdg-supply-chain-security.git

# Bootstrap a project
cd /path/to/your-project
bash /path/to/cdg-supply-chain-security/scripts/secure-project-init.sh npm     # or python, or both
```

The bootstrap script sets up `.npmrc`, virtualenv, Dependabot config, `.gitignore` entries, and a git pre-commit hook that warns on lockfile changes.

## CI workflows: two options

### Option A: Reusable workflow (recommended)

Define the checks once in this repo. Every project repo calls the central workflow with a tiny config file. When you update the checks here, all repos get the update automatically.

**Step 1:** This repo already contains the reusable workflow at `.github/workflows/supply-chain-check.yml`.

**Step 2:** In each project repo, create `.github/workflows/supply-chain.yml`:

```yaml
name: Dependency Security Guardrails

on:
  pull_request:
    paths:
      - "package.json"
      - "package-lock.json"
      - "yarn.lock"
      - "pnpm-lock.yaml"
      - "requirements.txt"
      - "requirements*.txt"
      - "pyproject.toml"
      - "uv.lock"
      - "Pipfile.lock"

jobs:
  supply-chain:
    uses: your-org/cdg-supply-chain-security/.github/workflows/supply-chain-check.yml@main
```

**Optional inputs** you can override:

```yaml
jobs:
  supply-chain:
    uses: your-org/cdg-supply-chain-security/.github/workflows/supply-chain-check.yml@main
    with:
      node-version: "20"
      python-version: "3.12"
      audit-level: "high"             # low, moderate, high, critical
      fail-on-floating: true          # block PRs with ^ or ~ ranges
      fail-on-missing-hashes: true    # block PRs if requirements.txt lacks hashes
```

**Requirements:**
- This repo must be in the same GitHub org (or the workflow must be in a public repo)
- The reusable workflow repo needs Actions enabled

**Pros:** Single source of truth. Update once, every repo benefits.
**Cons:** Requires org-level access. Caller repos depend on this repo being available.

### Option B: Drop-in workflow (self-contained)

Copy the workflow file directly into each project repo. No external dependency.

**Step 1:** Copy `examples/drop-in-workflow.yml` to your project:

```bash
cp examples/drop-in-workflow.yml /path/to/your-project/.github/workflows/supply-chain-check.yml
```

**Step 2:** Commit and push.

**Pros:** Fully self-contained. Works in any repo, any org, no cross-repo dependency.
**Cons:** Updates are manual per repo. If you change the checks, you update each repo individually.

### Which should I pick?

| Scenario | Recommendation |
|---|---|
| Single org, 3+ repos, one person maintaining | Reusable (Option A) |
| Cross-org, open source, or client-facing repos | Drop-in (Option B) |
| Quick one-off project | Drop-in (Option B) |
| Want to enforce stricter policies over time | Reusable (Option A) |

## What each check does

### npm checks
- **Lockfile exists:** Fails if `package.json` exists but no lockfile is committed
- **Floating versions:** Warns (or fails) if any dependency uses `^`, `~`, `*`, or range specifiers
- **ignore-scripts:** Warns if `.npmrc` does not have `ignore-scripts=true`
- **Provenance:** Runs `npm audit signatures` and reports packages missing registry signatures
- **npm audit:** Runs `npm audit` at the configured severity threshold

### Python checks
- **Lockfile exists:** Fails if `pyproject.toml` exists but no `uv.lock` or `requirements.txt` is committed
- **Hash verification:** Warns (or fails) if `requirements.txt` does not contain `--hash` entries
- **Unpinned deps:** Warns if any dependency in `requirements.txt` is not pinned with `==`
- **pip-audit:** Runs pip-audit against known vulnerability databases

### Lockfile diff
- Summarizes line-level changes to any lockfile in the PR
- Posts to the GitHub Actions job summary for reviewer visibility

## Additional recommendations

**Socket.dev** (free tier): Install as a GitHub App. It flags behavioral anomalies (new maintainers, install scripts, network calls, obfuscated code) before CVEs are even assigned. This is the layer that catches novel attacks.

https://socket.dev

**Dependabot:** The bootstrap script creates `.github/dependabot.yml` automatically. This opens PRs for version updates on a weekly cadence, which run through the supply chain checks.

## Repo structure

```
cdg-supply-chain-security/
  .github/
    workflows/
      supply-chain-check.yml    # Reusable workflow (Option A)
  examples/
    reusable-caller.yml         # Copy this into project repos (Option A)
    drop-in-workflow.yml        # Copy this into project repos (Option B)
  scripts/
    secure-project-init.sh      # Bootstrap script for new projects
  README.md
  LICENSE
```

## Background

Both the Axios and LiteLLM attacks followed the same pattern: maintainer account takeover, direct publish to the registry bypassing CI/CD, and exploitation of the ecosystem's implicit trust in registered packages.

The Axios attack (March 30, 2026) injected a malicious dependency with a postinstall hook that deployed a cross-platform RAT. With ~100M weekly npm downloads, the blast radius was massive even in a two-hour window. Google attributed it to UNC1069 (DPRK-linked).

The LiteLLM attack (March 24, 2026) was more sophisticated: attackers first compromised the Trivy security scanner, used stolen credentials to publish poisoned LiteLLM versions to PyPI, and deployed a multi-stage credential stealer targeting cloud credentials, SSH keys, and Kubernetes secrets. Attributed to TeamPCP, with possible LAPSUS$ collaboration.

Both attacks would have been blocked by the controls in this repo: `ignore-scripts` blocks the npm postinstall vector, exact pins prevent auto-pulling compromised versions, and hash verification catches tampered packages at install time.

## License

MIT

> Built and maintained by [Cyber Defense Group](https://www.cdg.io)
