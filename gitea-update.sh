#!/usr/bin/env bash

APP_NAME=Gitea
GITEA_BINARY=$HOME/gitea/gitea
TMP_LOCATION=$HOME/tmp
PGP_KEY_FINGERPRINT=7C9E68152594688862D62AF62D9AE806EC1592E2

ORG=go-gitea # Organisation or GitHub user
REPO=gitea
GITHUB_API_URL=https://api.github.com/repos/$ORG/$REPO/releases/latest

function do_update_procedure
{
  $GITEA_BINARY manager flush-queues
  supervisorctl stop gitea
  wget --quiet --progress=bar:force --output-document "$TMP_LOCATION"/gitea "$DOWNLOAD_URL"
  verify_file
  mv --verbose "$TMP_LOCATION"/gitea "$GITEA_BINARY"
  chmod u+x --verbose "$GITEA_BINARY"
  supervisorctl start gitea
  supervisorctl status gitea
}

function set_local_version
{
  LOCAL_VERSION=$($GITEA_BINARY --version |
    awk '{print $3}')
}

function set_latest_version
{
  curl --silent $GITHUB_API_URL > "$TMP_LOCATION"/github_api_response.json
  TAG_NAME=$(jq --raw-output '.tag_name' "$TMP_LOCATION"/github_api_response.json)
  LATEST_VERSION=${TAG_NAME:1}
  DOWNLOAD_URL=$(jq --raw-output '.assets[].browser_download_url' "$TMP_LOCATION"/github_api_response.json |
    grep --max-count=1 "linux-amd64")
}

function download_signature_file
{
  SIGNATURE_FILE_URL=$(jq --raw-output '.assets[].browser_download_url' "$TMP_LOCATION"/github_api_response.json |
    grep "linux-amd64.asc")
  rm "$TMP_LOCATION"/github_api_response.json
  wget --quiet --progress=bar:force --output-document "$TMP_LOCATION"/gitea.asc "$SIGNATURE_FILE_URL"
}

function verify_file
{
  download_signature_file

  ## downloading public key if it does NOT already exist OR if it is expired
  if ! gpg --fingerprint $PGP_KEY_FINGERPRINT ||
    (gpg --fingerprint $PGP_KEY_FINGERPRINT | grep expired)
  then
    ## currently the key download via gpg does not work on Uberspace
    #gpg --keyserver keys.openpgp.org --recv $PGP_KEY_FINGERPRINT
    curl --silent https://keys.openpgp.org/vks/v1/by-fingerprint/$PGP_KEY_FINGERPRINT | gpg --import
  fi

  if ! gpg --export-ownertrust | grep --quiet $PGP_KEY_FINGERPRINT:6:
  then echo "$PGP_KEY_FINGERPRINT:6:" | gpg --import-ownertrust
  fi

  if gpg --verify "$TMP_LOCATION"/gitea.asc "$TMP_LOCATION"/gitea
  then rm "$TMP_LOCATION"/gitea.asc; return 0
  else echo "gpg verification results in a BAD signature"; exit 1
  fi
}

# version_lower_than A B
# returns whether A < B
function version_lower_than
{
  test "$(echo "$@" |                 # get all version arguments
    tr " " "\n" |                     # replace `space` with `new line`
    sed '/alpha/d; /beta/d; /rc/d' |  # remove pre-release versions (version-sort interprets suffixes as patch versions)
    sort --version-sort --reverse |   # latest version will be sorted to line 1
    head --lines=1)" != "$1"          # filter line 1 and compare it to A
}

function fix_stop_signal
{
  if (grep --quiet HUP "$HOME"/etc/services.d/gitea.ini)
  then
    sed --in-place '/HUP/d' "$HOME"/etc/services.d/gitea.ini
    supervisorctl reread
    supervisorctl update
  fi
}

function update_available
{
  set_local_version
  set_latest_version
  if version_lower_than "$LOCAL_VERSION" "$LATEST_VERSION"
  then return 0
  else return 1
  fi
}

function main
{
  fix_stop_signal

  if update_available
  then
    echo "There is a new version available."
    echo "Doing update from $LOCAL_VERSION to $LATEST_VERSION"
    do_update_procedure
  else
    echo "Your $APP_NAME is already up to date."
    echo "You are running $APP_NAME $LOCAL_VERSION"
  fi
}

main "$@"
exit $?