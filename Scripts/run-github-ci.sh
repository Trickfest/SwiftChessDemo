#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="ci.yml"

usage() {
  cat <<'EOF'
Usage: Scripts/run-github-ci.sh [branch-or-tag]

Manually dispatch the optional SwiftChessDemo GitHub Actions workflow.
The ref must already exist on GitHub and contain the workflow_dispatch trigger.
When omitted, the current local branch is used; a detached checkout falls back
to the repository's default branch.

This helper does not commit or push local changes.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if (( $# > 1 )); then
  usage >&2
  exit 2
fi

for command_name in git gh; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command is not installed: %s\n' "$command_name" >&2
    exit 1
  fi
done

cd "$ROOT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'Not inside the SwiftChessDemo Git worktree: %s\n' "$ROOT_DIR" >&2
  exit 1
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  printf 'SwiftChessDemo has no origin remote to validate.\n' >&2
  exit 1
fi
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  printf 'GitHub CLI is not authenticated for github.com. Run: gh auth login\n' >&2
  exit 1
fi

if ! repository="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" ||
   [[ -z "$repository" ]]; then
  printf 'Could not resolve the GitHub repository from %s.\n' "$ROOT_DIR" >&2
  exit 1
fi

ref="${1:-}"
current_branch="$(git branch --show-current)"
if [[ -z "$ref" ]]; then
  ref="$current_branch"
fi
if [[ -z "$ref" ]]; then
  if ! ref="$(
    gh repo view "$repository" --json defaultBranchRef \
      --jq '.defaultBranchRef.name' 2>/dev/null
  )" || [[ -z "$ref" ]]; then
    printf 'Could not determine a branch or tag to dispatch. Pass one explicitly.\n' >&2
    exit 1
  fi
fi

if ! git check-ref-format "refs/heads/$ref" >/dev/null 2>&1 &&
   ! git check-ref-format "refs/tags/$ref" >/dev/null 2>&1; then
  printf 'Invalid branch or tag name: %s\n' "$ref" >&2
  exit 2
fi

branch_ref="refs/heads/$ref"
tag_ref="refs/tags/$ref"
if ! remote_refs="$(git ls-remote --exit-code origin "$branch_ref" "$tag_ref" 2>/dev/null)" ||
   [[ -z "$remote_refs" ]]; then
  printf 'Remote branch or tag %s does not exist on origin.\n' "$ref" >&2
  printf 'Publish it separately, then rerun this helper. It will not push for you.\n' >&2
  exit 1
fi

remote_sha="$(
  printf '%s\n' "$remote_refs" |
    awk -v branch="$branch_ref" '$2 == branch { print $1; exit }'
)"
remote_kind="branch"
if [[ -z "$remote_sha" ]]; then
  remote_sha="$(printf '%s\n' "$remote_refs" | awk 'NR == 1 { print $1 }')"
  remote_kind="tag"
fi

if ! workflow_yaml="$(
  gh workflow view "$WORKFLOW" --repo "$repository" --ref "$ref" --yaml 2>/dev/null
)"; then
  printf 'Remote %s %s does not contain %s in %s.\n' \
    "$remote_kind" "$ref" "$WORKFLOW" "$repository" >&2
  printf 'Publish the workflow separately, then rerun this helper. It will not push for you.\n' >&2
  exit 1
fi
if ! grep -Eq '^[[:space:]]+workflow_dispatch:[[:space:]]*($|#)' <<<"$workflow_yaml"; then
  printf 'Remote workflow %s at %s is not configured for manual dispatch.\n' \
    "$WORKFLOW" "$ref" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Warning: local uncommitted changes are not included in this run.\n' >&2
fi
if [[ "$remote_kind" == "branch" && "$current_branch" == "$ref" ]]; then
  local_sha="$(git rev-parse HEAD)"
  if [[ "$local_sha" != "$remote_sha" ]]; then
    printf 'Warning: local HEAD %s differs from origin/%s at %s.\n' \
      "$local_sha" "$ref" "$remote_sha" >&2
    printf 'The workflow will run the remote commit; this helper will not push local commits.\n' >&2
  fi
fi

printf 'Dispatching %s for %s at remote %s %s (%s)...\n' \
  "$WORKFLOW" "$repository" "$remote_kind" "$ref" "$remote_sha"
if ! dispatch_output="$(
  gh workflow run "$WORKFLOW" --repo "$repository" --ref "$ref" 2>&1
)"; then
  printf 'GitHub rejected the workflow dispatch:\n%s\n' "$dispatch_output" >&2
  exit 1
fi

printf 'Dispatch accepted. GitHub may take a few seconds to create the run.\n'
if [[ -n "$dispatch_output" ]]; then
  printf '%s\n' "$dispatch_output"
fi
printf 'Workflow runs: https://github.com/%s/actions/workflows/%s\n' \
  "$repository" "$WORKFLOW"
printf 'Inspect recent manual runs with:\n'
printf '  gh run list --repo %s --workflow %s --event workflow_dispatch --limit 5\n' \
  "$repository" "$WORKFLOW"
printf 'Open a run with: gh run view --repo %s <run-id> --web\n' "$repository"
