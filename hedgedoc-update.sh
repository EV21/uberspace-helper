#!/usr/bin/env bash
APP_NAME=HedgeDoc
ORG=hedgedoc # Organisation or GitHub user
REPO=hedgedoc
LOCAL_VERSION=$(jq --raw-output .version ~/hedgedoc/package.json)
LATEST_VERSION=$(curl --silent https://api.github.com/repos/$ORG/$REPO/releases/latest |
  jq --raw-output .tag_name)

function do_upgrade() {
  supervisorctl stop hedgedoc
  echo "waiting 1 minute until all processes are stopped"
  sleep 1m
  mv --verbose ~/hedgedoc ~/hedgedoc_"$LOCAL_VERSION"
  VERSION=$LATEST_VERSION
  cd || exit
  wget https://github.com/hedgedoc/hedgedoc/releases/download/"$VERSION"/hedgedoc-"$VERSION".tar.gz
  tar --extract --gzip --file=hedgedoc-"$VERSION".tar.gz
  rm --verbose hedgedoc-"$VERSION".tar.gz
  cp --verbose hedgedoc_"$LOCAL_VERSION"/config.json hedgedoc/config.json
  cd ~/hedgedoc || exit
  bin/setup
  echo "You may need to wait a minute until HedgeDoc is up and running."
  supervisorctl start hedgedoc
  echo "If everything works fine you can delete ~/hedgedoc_$LOCAL_VERSION"
  echo "Please consider that there might be uploaded files in ~/hedgedoc_$LOCAL_VERSION/public/uploads which were not migrated to the new version if you are using the default setting."
  rm --recursive ~/hedgedoc_"$LOCAL_VERSION"
}

function yes-no_question
{
  local question=$1
  while true
  do
    read -r -p "$question (Y/n) " ANSWER
    if [ "$ANSWER" = "" ]
    then ANSWER='Y'
    fi
    case $ANSWER in
      [Yy]* | [Jj]* )
        return 0 ;;
      [Nn]* )
        return 1 ;;
      * ) echo "Please answer yes or no." ;;
    esac
  done
}

## this is a helper function to compare two versions as a "lower than" operator
function version_lt
{
  test "$(echo "$@" |
    tr " " "n" |
    sort --version-sort --reverse |
    head --lines=1)" != "$1"
}

function main
{
  if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]
  then echo "Your HedgeDoc is already up to date."
  elif version_lt "$LOCAL_VERSION" "$LATEST_VERSION"
  then
    echo "There is a new Version available of $APP_NAME"
    echo "The latest Version is $LATEST_VERSION"
    echo "Your local Version is $LOCAL_VERSION"
    echo "Upgrades to next major releases are not tested."
    echo "Please read the release notes."
    echo "Also check if the upgrade instructions have changed."
    echo "Your instance might break."
    if yes-no_question "Do you wish to proceed with the upgrade?"
    then do_upgrade
    fi
  fi
}

main "$@"
exit $?