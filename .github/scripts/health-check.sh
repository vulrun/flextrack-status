#!/bin/bash
set -e # Exit immediately on any error

# Validate GITHUB_TOKEN exists
if [[ -z "${GITHUB_TOKEN}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set"
  exit 1
fi

echo "Configuring git user..."
git config --global user.name 'Mohit'
git config --global user.email 'vulrun@gmail.com'

echo "Setting authenticated remote URL..."
git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git

echo "Fetching all branches from remote..."
git fetch --prune origin

# Check if remote logging branch exists
if git show-ref --verify --quiet refs/remotes/origin/logging; then
  echo "Checking out logging branch"
  git checkout logging
else
  echo "Error: Remote branch 'origin/logging' does not exist"
  echo "Available remote branches:"
  git ls-remote --heads origin
  exit 1
fi

LAST_RUN_FILE="logs/.last_run"

if [ -f "$LAST_RUN_FILE" ]; then
  LAST_RUN=$(cat $LAST_RUN_FILE)
  NOW=$(date +%s)
  DIFF=$((NOW - LAST_RUN))

  if [ $DIFF -lt 300 ]; then
    echo "Skipping run ($DIFF seconds passed)"
    exit 0
  fi
fi

git log -n 10 --abbrev-commit --decorate --pretty=format:"%C(yellow)%h %C(reset)-%C(red)%d %C(reset)%s %C(green)(%ar) %C(blue)[%an]" "$@"
echo
wget -nv https://raw.githubusercontent.com/vulrun/flextrack-status/refs/heads/main/urls.cfg
echo "Working directory contents:"
ls -halF

KEYSARRAY=()
URLSARRAY=()

echo
echo
echo
urlsConfig="./urls.cfg"
echo "Reading $urlsConfig"

while read -r line; do
  echo "$line"
  IFS='=' read -ra TOKENS <<< "$line"
  KEYSARRAY+=(${TOKENS[0]})
  URLSARRAY+=(${TOKENS[1]})
done < "$urlsConfig"

echo ''
echo "***********************"
echo "Starting health checks with ${#KEYSARRAY[@]} configs:"

mkdir -p logs

for ((index = 0; index < ${#KEYSARRAY[@]}; index++)); do
  key="${KEYSARRAY[index]}"
  url="${URLSARRAY[index]}"
  echo "-- checking $key=$url"

  for i in 1 2 3 4; do
    response=$(curl --write-out '%{http_code}' --silent --output /dev/null $url)
    if [ "$response" -eq 200 ] || [ "$response" -eq 202 ] || [ "$response" -eq 301 ] || [ "$response" -eq 302 ] || [ "$response" -eq 307 ]; then
      result="success"
    else
      result="failed"
    fi
    if [ "$result" = "success" ]; then
      break
    fi
    sleep 5
  done

  dateTime=$(date +'%Y-%m-%d %H:%M')
  echo $dateTime, $result >> "logs/${key}_report.log"
  # By default we keep 2000 last log entries.  Feel free to modify this to meet your needs.
  echo "$(tail -2000 logs/${key}_report.log)" > "logs/${key}_report.log"
  echo "-- -- $dateTime, $result"
done
echo "***********************"
echo
echo
echo

date +%s > $LAST_RUN_FILE
git add -A --force logs/
git commit -am "[Automated] Health check logs updated at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
git log -n 10 --abbrev-commit --decorate --pretty=format:"%C(yellow)%h %C(reset)-%C(red)%d %C(reset)%s %C(green)(%ar) %C(blue)[%an]" "$@"
git push https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git logging
