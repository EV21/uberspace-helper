#!/usr/bin/env bash

APP_NAME=Gitea
GITEA_LOCATION=$HOME/gitea/gitea
TMP_LOCATION=$HOME/tmp
GPG_KEY_FINGERPRINT=7C9E68152594688862D62AF62D9AE806EC1592E2

ORG=go-gitea # Organisation or GitHub user
REPO=gitea
GITHUB_API_URL=https://api.github.com/repos/$ORG/$REPO/releases/latest

function do_update_procedure
{
  $GITEA_LOCATION manager flush-queues
  supervisorctl stop gitea
  wget --quiet --progress=bar:force --output-document "$TMP_LOCATION"/gitea "$DOWNLOAD_URL"
  verify_file
  supervisorctl stop gitea
  mv --verbose "$TMP_LOCATION"/gitea "$GITEA_LOCATION"
  chmod u+x --verbose "$GITEA_LOCATION"
  supervisorctl start gitea
  supervisorctl status gitea
}

function get_local_version
{
  LOCAL_VERSION=$($GITEA_LOCATION --version |
    awk '{print $3}')
}

function get_latest_version
{
  curl --silent $GITHUB_API_URL > "$TMP_LOCATION"/github_api_response.json
  TAG_NAME=$(jq --raw-output '.tag_name' "$TMP_LOCATION"/github_api_response.json)
  LATEST_VERSION=${TAG_NAME:1}
  DOWNLOAD_URL=$(jq --raw-output '.assets[].browser_download_url' "$TMP_LOCATION"/github_api_response.json |
    grep --max-count=1 "linux-amd64")
}

function get_signature_file
{
  SIGNATURE_FILE_URL=$(jq --raw-output '.assets[].browser_download_url' "$TMP_LOCATION"/github_api_response.json |
    grep "linux-amd64.asc")
  rm "$TMP_LOCATION"/github_api_response.json
  wget --quiet --progress=bar:force --output-document "$TMP_LOCATION"/gitea.asc "$SIGNATURE_FILE_URL"
}

function verify_file
{
  get_signature_file

  ## downloading public key if it does not already exist
  if ! gpg --fingerprint $GPG_KEY_FINGERPRINT
  then
    ## currently the key download via gpg does not work on Uberspace
    #gpg --keyserver keys.openpgp.org --recv $GPG_KEY_FINGERPRINT
    curl --silent https://keys.openpgp.org/vks/v1/by-fingerprint/$GPG_KEY_FINGERPRINT | gpg --import
  fi

  if ! gpg --export-ownertrust | grep --quiet $GPG_KEY_FINGERPRINT:6:
  then echo "$GPG_KEY_FINGERPRINT:6:" | gpg --import-ownertrust
  fi

  if gpg --verify "$TMP_LOCATION"/gitea.asc "$TMP_LOCATION"/gitea
  then rm "$TMP_LOCATION"/gitea.asc; return 0
  else echo "gpg verification results in a BAD signature"; exit 1
  fi
}

## version_lower_than A B returns whether A < B
function version_lower_than
{
  test "$(echo "$@" |
    tr " " "n" |
    sort --version-sort --reverse |
    head --lines=1)" != "$1"
}

function main
{
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

main "$@"
exit $?