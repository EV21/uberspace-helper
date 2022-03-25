#!/usr/bin/env bash
APP=grocy
ORG=grocy # Organisation or GitHub user
REPO=grocy
LOCAL_VERSION=$(jq --raw-output .Version /var/www/virtual/"$USER"/grocy/version.json)
TAG_NAME=$(curl -s https://api.github.com/repos/$ORG/$REPO/releases/latest | jq --raw-output .tag_name)
LATEST_VERSION=${TAG_NAME:1} # It is common to use the prefix v for the version tag.

## this is a helper function to compare two versions as a "lower than" operator
function version_lt
{
  test "$(echo "$@" |
    tr " " "n" |
    sort --version-sort --reverse |
    head --lines=1)" != "$1"
}

if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
  echo "Your $APP is running on $LOCAL_VERSION and it is already up to date."
else
  if version_lt "$LOCAL_VERSION" "$LATEST_VERSION"
  then
    echo "There is a new Version available of $ORG"
    echo "The latest Version is $LATEST_VERSION"
    echo "Your local Version is $LOCAL_VERSION"
    bash /var/www/virtual/"$USER"/grocy/update.sh
  fi
fi
