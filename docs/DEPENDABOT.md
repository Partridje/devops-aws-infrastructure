# Dependabot Configuration Guide

This document explains how Dependabot is configured to keep dependencies up to date automatically.

## Overview

Dependabot automatically creates pull requests to update dependencies when new versions are available. This helps:
- ✅ Keep dependencies secure (automatic security updates)
- ✅ Stay current with latest features
- ✅ Reduce technical debt
- ✅ Prevent breaking changes (controlled updates)

**Cost**: FREE (built into GitHub)

---

## What Gets Updated

### 1. Terraform Providers

**Scope**: AWS provider and other Terraform providers

**Frequency**: Weekly (Monday 03:00 Stockholm time)

**Strategy**:
- ✅ Patch updates: Auto-created PRs (e.g., 5.0.0 → 5.0.1)
- ✅ Minor updates: Auto-created PRs (e.g., 5.0.0 → 5.1.0)
- ⚠️ Major updates: **Ignored** (requires manual review)

**Why ignore major updates?**
Major version changes may contain breaking changes that require code modifications.

**Environments**: Separate PRs for dev and prod
- `terraform/environments/dev/` - Development environment
- `terraform/environments/prod/` - Production environment

**Example PR**:
```
terraform(dev): Bump hashicorp/aws from 5.0.0 to 5.0.1 in /terraform/environments/dev
```

### 2. Python Dependencies

**Scope**: Flask and all Python packages in `app/requirements.txt`

**Frequency**: Weekly (Monday 03:00 Stockholm time)

**Strategy**:
- ✅ All updates allowed (security, feature, bugfix)
- ✅ Minor and patch updates **grouped together** (fewer PRs)
- ✅ Major updates: Individual PRs for careful review

**Packages monitored**:
- Flask, Werkzeug
- psycopg2 (PostgreSQL driver)
- boto3 (AWS SDK)
- prometheus-client
- gunicorn
- All transitive dependencies

**Example PR**:
```
python: Bump Flask from 3.0.0 to 3.0.1 in /app
```

**Grouped PR example**:
```
python: Bump python-minor-patch group in /app

Updates:
- Flask from 3.0.0 to 3.0.2
- boto3 from 1.28.0 to 1.28.5
- psycopg2-binary from 2.9.7 to 2.9.9
```

### 3. Docker Base Images

**Scope**: Python base image in `app/Dockerfile`

**Frequency**: Weekly (Monday 03:00 Stockholm time)

**Currently tracked**:
- `python:3.11-slim` → `python:3.11.x-slim`

**Strategy**:
- ✅ Patch updates for security fixes
- Docker tags are monitored for new releases

**Example PR**:
```
docker: Update Python Docker tag to v3.11.8
```

### 4. GitHub Actions

**Scope**: All workflow actions in `.github/workflows/`

**Frequency**: Weekly (Monday 03:00 Stockholm time)

**Strategy**:
- ✅ All updates allowed
- ✅ All actions **grouped together** (single PR per week)

**Actions monitored**:
- `actions/checkout@v4`
- `actions/setup-python@v5`
- `hashicorp/setup-terraform@v3`
- `docker/build-push-action@v5`
- `aquasecurity/trivy-action@master`
- And others

**Example grouped PR**:
```
ci: Bump github-actions group with 3 updates

Updates:
- actions/checkout from v4.0.0 to v4.1.0
- hashicorp/setup-terraform from v3.0.0 to v3.1.0
- docker/build-push-action from v5.0.0 to v5.1.0
```

---

## How It Works

### Automatic Workflow

```
Monday 03:00
    ↓
Dependabot checks for updates
    ↓
New versions found?
    ↓ Yes
Create Pull Request
    ↓
CI automatically runs tests
    ↓
Tests pass? → Review and merge
Tests fail? → Investigate and fix
```

### PR Review Process

1. **Dependabot creates PR** with changelog and release notes
2. **CI automatically runs**:
   - Terraform validation
   - Python tests
   - Docker build
   - Security scans
3. **You review**:
   - Check changelog for breaking changes
   - Verify CI passed
   - Review any security advisories
4. **Merge** if everything looks good

---

## Configuration Details

### Update Schedule

All updates run at **Monday 03:00 Stockholm time** (Europe/Stockholm timezone).

**Why Monday morning?**
- Gives you the week to review and merge
- Avoids weekend surprises
- Consistent schedule

### Pull Request Limits

| Ecosystem | Max Open PRs |
|-----------|--------------|
| Terraform (dev) | 5 |
| Terraform (prod) | 5 |
| Python | 10 |
| Docker | 3 |
| GitHub Actions | 5 (grouped) |

**Why limits?**
Prevents PR overload. If limit reached, Dependabot waits until you merge/close existing PRs.

### Commit Messages

Dependabot uses conventional commit format:

```
<type>(<scope>): <description>

Examples:
- terraform(dev): Bump hashicorp/aws from 5.0.0 to 5.1.0
- python: Bump Flask from 3.0.0 to 3.0.1
- docker: Update Python Docker tag to v3.11.8
- ci: Bump github-actions group with 2 updates
```

### Labels

PRs are automatically labeled for easy filtering:

| Label | Used For |
|-------|----------|
| `dependencies` | All dependency updates |
| `terraform` | Terraform provider updates |
| `python` | Python package updates |
| `docker` | Docker image updates |
| `github-actions` | GitHub Actions updates |
| `dev` | Dev environment |
| `prod` | Production environment |

**Filter PRs by label**:
```
is:pr label:dependencies label:terraform
is:pr label:dependencies label:python
```

---

## Common Scenarios

### Scenario 1: Security Vulnerability

**What happens:**
1. GitHub Security Advisory published
2. Dependabot immediately creates PR (doesn't wait for Monday)
3. PR is labeled with `security`
4. Email notification sent

**What to do:**
1. Review the advisory details in PR
2. Check if fix is available
3. Merge ASAP if tests pass
4. Deploy to production

### Scenario 2: Major Version Update

**What happens:**
Major version updates are **ignored by default** for Terraform and Docker.

**What to do:**
1. Manually check for major updates periodically
2. Read changelog for breaking changes
3. Test in dev environment first
4. Update manually when ready:
   ```bash
   # Example: Update Terraform AWS provider
   cd terraform/environments/dev
   # Edit main.tf to update version constraint
   terraform init -upgrade
   terraform plan
   terraform apply
   ```

### Scenario 3: Failed Tests

**What happens:**
1. Dependabot creates PR
2. CI runs automatically
3. Tests fail (e.g., breaking change)

**What to do:**
1. Review test failures in CI
2. Check if code changes needed
3. Options:
   - **Fix code** to work with new version
   - **Close PR** and pin version (temporary)
   - **Report issue** to package maintainer

### Scenario 4: Too Many PRs

**What happens:**
Many packages updated in same week → multiple PRs

**What to do:**
1. **Merge grouped PRs first** (minor/patch updates)
2. **Review major updates carefully**
3. **Close outdated PRs** if newer version available
4. **Adjust limits** in `.github/dependabot.yml` if needed

---

## Best Practices

### Review Guidelines

✅ **DO:**
- Review Dependabot PRs weekly
- Check changelog/release notes
- Verify CI passes before merging
- Merge security updates ASAP
- Test in dev before merging prod updates
- Keep PRs open < 1 week (avoid conflicts)

❌ **DON'T:**
- Auto-merge without reviewing
- Ignore failing tests
- Let PRs accumulate (creates conflicts)
- Merge prod updates without testing

### Security Updates

Security updates are high priority:

```bash
# View security updates
gh pr list --label "dependencies,security"

# Merge security update (after CI passes)
gh pr merge <PR-NUMBER> --squash --delete-branch
```

**Security advisory severity**:
- **Critical**: Merge immediately
- **High**: Merge within 24 hours
- **Medium**: Merge within 1 week
- **Low**: Merge with regular updates

### Merge Strategy

**Recommended strategy**: Squash and merge

```bash
# Via GitHub CLI
gh pr merge <PR-NUMBER> --squash --delete-branch

# Or use GitHub UI: "Squash and merge" button
```

**Why squash?**
- Clean commit history
- Single commit per dependency update
- Easy to revert if needed

---

## Managing Dependabot

### Pause Updates

Temporarily pause updates (e.g., during major release):

**Option 1: Via GitHub UI**
1. Go to repository **Settings** → **Security** → **Dependabot**
2. Click **Pause** for specific ecosystem

**Option 2: Edit config**
```yaml
# .github/dependabot.yml
- package-ecosystem: "terraform"
  directory: "/terraform/environments/prod"
  schedule:
    interval: "weekly"
  open-pull-requests-limit: 0  # Pause by setting to 0
```

### Ignore Specific Dependencies

Ignore problematic package:

```yaml
# .github/dependabot.yml
- package-ecosystem: "pip"
  directory: "/app"
  # ...
  ignore:
    - dependency-name: "problematic-package"
      # Ignore all versions
    - dependency-name: "another-package"
      versions: ["1.x"]  # Ignore 1.x versions only
```

### Change Update Frequency

Reduce/increase update frequency:

```yaml
schedule:
  interval: "monthly"  # Options: daily, weekly, monthly
```

### Increase PR Limits

Allow more concurrent PRs:

```yaml
open-pull-requests-limit: 20  # Default: 5-10
```

---

## Monitoring

### View Dependabot Activity

**GitHub UI**:
1. Go to **Insights** → **Dependency graph** → **Dependabot**
2. See all updates, security alerts, and PRs

**GitHub CLI**:
```bash
# List all Dependabot PRs
gh pr list --author "app/dependabot"

# View Dependabot alerts
gh api /repos/OWNER/REPO/dependabot/alerts
```

### Email Notifications

Configure notifications for Dependabot:
1. Go to **Settings** → **Notifications**
2. Enable:
   - **Dependabot alerts**
   - **Pull request reviews**

### Metrics

Track Dependabot effectiveness:
- **Time to merge**: How quickly PRs are merged
- **Security response**: Time to merge security updates
- **PR accumulation**: Number of open PRs
- **Update success rate**: % of PRs merged vs closed

---

## Troubleshooting

### Dependabot Not Creating PRs

**Problem**: No PRs created on Monday

**Possible causes:**
1. **Already at PR limit**: Check open PRs
   ```bash
   gh pr list --author "app/dependabot" --state open
   ```
   Close old PRs to allow new ones

2. **No updates available**: All dependencies are current

3. **Configuration error**: Check `.github/dependabot.yml` syntax
   ```bash
   # Validate YAML syntax
   yamllint .github/dependabot.yml
   ```

4. **GitHub status**: Check https://www.githubstatus.com/

### PR Conflicts

**Problem**: Dependabot PR has merge conflicts

**Solution**:
```bash
# Rebase via comment on PR
# Add this comment to PR:
@dependabot rebase

# Or close and let Dependabot recreate
@dependabot recreate
```

### Failed CI

**Problem**: Tests fail after dependency update

**Diagnosis**:
1. Check CI logs for specific error
2. Review package changelog for breaking changes
3. Check if multiple dependencies updated together

**Solutions**:
1. **Fix code** to work with new version
2. **Revert specific package** (close PR, pin version)
3. **Report bug** to package maintainer

---

## Advanced Configuration

### Auto-Merge (Optional)

Enable auto-merge for patch updates:

⚠️ **WARNING**: Only enable if you have comprehensive test coverage

```yaml
# .github/workflows/dependabot-auto-merge.yml
name: Dependabot Auto-Merge
on: pull_request

permissions:
  pull-requests: write
  contents: write

jobs:
  auto-merge:
    runs-on: ubuntu-latest
    if: ${{ github.actor == 'dependabot[bot]' }}
    steps:
      - name: Dependabot metadata
        id: metadata
        uses: dependabot/fetch-metadata@v1
        with:
          github-token: "${{ secrets.GITHUB_TOKEN }}"

      - name: Enable auto-merge for patch updates
        if: ${{ steps.metadata.outputs.update-type == 'version-update:semver-patch' }}
        run: gh pr merge --auto --squash "$PR_URL"
        env:
          PR_URL: ${{github.event.pull_request.html_url}}
          GITHUB_TOKEN: ${{secrets.GITHUB_TOKEN}}
```

### Custom Update Schedule

Different schedule per ecosystem:

```yaml
# Terraform: Weekly
- package-ecosystem: "terraform"
  schedule:
    interval: "weekly"

# Python: Daily (for critical app)
- package-ecosystem: "pip"
  schedule:
    interval: "daily"

# Docker: Monthly (slow-moving)
- package-ecosystem: "docker"
  schedule:
    interval: "monthly"
```

---

## Cost Considerations

**Dependabot**: FREE (included with GitHub)

**CI costs** (if using GitHub Actions):
- Dependabot triggers CI for each PR
- ~5-10 minutes per PR
- Included in free tier (2,000 minutes/month)

**Time investment**:
- ~10-30 minutes/week for reviews
- Worth it for security and maintenance

---

## Summary

**Dependabot is configured and active**:

✅ **What's monitored:**
- Terraform providers (AWS, etc.)
- Python packages (Flask, boto3, psycopg2, etc.)
- Docker base images (python:3.11-slim)
- GitHub Actions (checkout, setup-terraform, etc.)

✅ **Update schedule:**
- Every Monday at 03:00 Stockholm time
- Security updates: Immediate

✅ **Strategy:**
- Patch/minor: Automatic PRs
- Major: Ignored (manual review required)
- Grouped updates: Fewer PRs

✅ **Next steps:**
1. Wait for first PRs (next Monday)
2. Review and merge as they come
3. Adjust configuration if needed

**No action required** - Dependabot works automatically! 🤖

---

**Related Documentation**:
- [GitHub Dependabot Docs](https://docs.github.com/en/code-security/dependabot)
- [Dependabot Configuration Options](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
- [Main README](../README.md)
