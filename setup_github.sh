#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f README.md ] || ! grep -q '# kkd_mini1' README.md; then
  echo "# kkd_mini1" >> README.md
fi

git init
git add README.md
if ! git diff --cached --quiet; then
  git commit -m "first commit"
fi

# Include the rest of the project if there are uncommitted files
git add -A
# Avoid committing secrets if present
git reset HEAD -- .env .env.* 2>/dev/null || true
if ! git diff --cached --quiet; then
  git commit -m "Add project files"
fi

git branch -M main

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin https://github.com/carcase2/kkd_mini1.git
else
  git remote add origin https://github.com/carcase2/kkd_mini1.git
fi

git push -u origin main
echo "Done: https://github.com/carcase2/kkd_mini1"
