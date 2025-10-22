#!/usr/bin/env bash
set -euo pipefail

repo_root="$(pwd)"

echo "Scanning for common generated build artifacts..."

# Patterns to detect (find -path patterns)
paths=("*/Debug/*.exe" "*/Debug/*.dcu" "*/Debug/*.res" "**/Debug/*.exe" "**/Debug/*.dcu" "**/Debug/*.res")

# Use git ls-files to list tracked files, then filter by patterns using fnmatch-like matching via grep
tracked_files=$(git ls-files)

candidates=()
while IFS= read -r f; do
  for p in "${paths[@]}"; do
    # Convert glob pattern to grep-friendly regex (simple replace)
    # We'll just check if the path contains the segments since patterns are simple
    if [[ "${f//\\/\/}" == ${p} || "${f//\\/\/}" == ${p#**/} || "${f//\\/\/}" == ${p#*/} ]]; then
      candidates+=("$f")
    fi
    # Fallback: simple contains check for /Debug/
    if [[ "$f" == *"/Debug/"* ]]; then
      # check extension
      case "$f" in
        *.exe|*.dcu|*.res) candidates+=("$f") ;;
      esac
    fi
  done
done <<< "$tracked_files"

# Deduplicate
mapfile -t uniq_candidates < <(printf "%s\n" "${candidates[@]}" | awk '!seen[$0]++')

if [ ${#uniq_candidates[@]} -eq 0 ]; then
  echo "No tracked generated files found. Nothing to do."
  exit 0
fi

echo "Found tracked generated files:" 
printf "  %s\n" "${uniq_candidates[@]}"

branch="cleanup/generated-files-$(date +%s)"
git checkout -b "$branch"

# Update .gitignore
gi='.gitignore'
declare -a additions=("# Auto-ignore generated build outputs" "**/Debug/*.exe" "**/*/Debug/*.exe" "**/Debug/*.dcu" "**/*/Debug/*.dcu" "**/Debug/*.res" "**/*/Debug/*.res")
changed=false
if [ -f "$gi" ]; then
  gi_content=$(cat "$gi")
else
  gi_content=''
fi
for a in "${additions[@]}"; do
  if ! grep -Fxq "$a" "$gi" 2>/dev/null; then
    echo "$a" >> "$gi"
    changed=true
  fi
done
if [ "$changed" = true ]; then
  git add "$gi"
fi

# Remove tracked files from index
for f in "${uniq_candidates[@]}"; do
  git rm --cached -r -- "$f" || true
done

git add -u
if git diff --staged --quiet; then
  echo "No changes to commit after cleanup.";
else
  git commit -m "Propose removal of generated binaries and update .gitignore"
  git push origin "$branch"

  # Try to create PR using gh if available
  if command -v gh >/dev/null 2>&1; then
    gh pr create --title "chore: remove generated binaries" --body "This PR removes tracked generated build artifacts and updates .gitignore." --base main --head "$branch" || true
  else
    echo "gh CLI not available — a branch was pushed: $branch";
  fi
fi

echo "Done. Review the branch/PR and merge when ready."
