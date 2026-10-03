#!/usr/bin/env bash
# AW1: AppWorld, first 20 test_normal tasks, simplified_react_code_agent, raw (:18080) then layer (:8080). Logs to AW1.log.
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
K=$(tr -d '\r\n' < C:/Users/pwall/Projects/bonsai-2-27b-serve/artifacts/api_key.txt)
export BONSAI_API_KEY="$K" OPENAI_API_KEY="$K"
VP="$TEMP/appworld-venv/Scripts/python.exe"
cd "$TEMP/appworld-src"
for arm in bonsai-raw bonsai-layer; do
  echo "== $arm start $(date +%H:%M)"
  $VP -m appworld.cli run simplified_react_code_agent/bonsai_local/$arm/test_normal_first20 2>&1 | grep -v "^|\|^+\|^│\|^┌\|^└" | tail -5
  $VP -m appworld.cli evaluate simplified_react_code_agent/bonsai_local/$arm/test_normal_first20 test_normal_first20 2>&1 | grep -v "^|\|^+\|^│\|^┌\|^└" | tail -12
  echo "== $arm done $(date +%H:%M)"
done
