#!/usr/bin/env bash

APP_NAME="Uptime Kuma"
ORG=louislam # Organisation or GitHub user
REPO=uptime-kuma
GITHUB_API_URL=https://api.github.com/repos/$ORG/$REPO/releases/latest

function get_local_version
{
  LOCAL_VERSION=$(git describe --tags)
}

function get_latest_version
{
  LATEST_VERSION=$(curl --silent $GITHUB_API_URL |
    jq --raw-output .tag_name)
}

function do_update_procedure
{
  git fetch --all
  git checkout "$LATEST_VERSION" --force
  npm ci --production
  npm run download-dist
  supervisorctl restart uptime-kuma
  sleep 3
  supervisorctl status
}

## version_lower_than A B
# returns whether A < B
function version_lower_than
{
  test "$(echo "$@" |
    tr " " "\n" |
    sort --version-sort --reverse |
    head --lines=1)" != "$1"
}

function main
{
  cd ~/uptime-kuma || exit 1
  get_local_version
  get_latest_version

  if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]
  then
    echo "Your $APP_NAME is already up to date."
    echo "You are running $APP_NAME $LOCAL_VERSION"
  else
    if version_lower_than "$LOCAL_VERSION" "$LATEST_VERSION"
    then
      echo "There is a new version available."
      echo "Doing update from $LOCAL_VERSION to $LATEST_VERSION"
      do_update_procedure
    fi
  fi
}

main "${@}"
exit $?
