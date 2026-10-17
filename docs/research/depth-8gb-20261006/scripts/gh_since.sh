#!/usr/bin/env bash
# Print every issue / PR comment in the repo since the last call (time kept in gh_since.txt), so nothing posted between two
# gh_watch.sh runs is missed (gh_watch takes a new baseline at each start). Own comments (gh_mine.txt) are skipped.
cd /c/bonsai/8gb; R=professorpalmer/bonsai-ada-surgery
SINCE=$(cat gh_since.txt 2>/dev/null || date -u -d '-6 hours' +%Y-%m-%dT%H:%M:%SZ)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gh api "repos/$R/issues/comments?since=$SINCE&per_page=100" --jq '.[] | "\(.id)\t\(.created_at)\t\(.html_url)\t\(.body | gsub("\n"; " ") | .[0:300])"' 2>/dev/null \
  | grep -v -F -f <(sed 's/^/^/' gh_mine.txt | sed 's/^\^//' ) | awk -F'\t' -v s="$SINCE" '$2 > s'
echo "$NOW" > gh_since.txt
