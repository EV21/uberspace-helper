#!/usr/bin/env bash

APP_NAME=Gitea
GITEA_BIN_LOCATION=$HOME/gitea/gitea
TMP_LOCATION=$HOME/tmp
GPG_KEY_FINGERPRINT=7C9E68152594688862D62AF62D9AE806EC1592E2
ORG=go-gitea # Organisation or GitHub user
REPO=gitea
GITHUB_API_URL=https://api.github.com/repos/$ORG/$REPO/releases/latest
# simply get the first password string from ~/.my.cnf
MYSQL_PASSWORD_STR=$(grep --max-count=1 password= ~/.my.cnf)
# using bash substring syntax to remove the 9 characters "password="
MYSQL_PASSWORD=${MYSQL_PASSWORD_STR:9}

function install_gitea
{
  get_latest_version
  echo "Installing $APP_NAME $LATEST_VERSION"
  echo "Please set your $APP_NAME login credentials."
  read -r -p "$APP_NAME admin user: " ADMIN_USER
  read -r -p "$APP_NAME admin password: " ADMIN_PASS
  wget --quiet --progress=bar:force --output-document "$TMP_LOCATION"/gitea "$DOWNLOAD_URL"
  verify_file
  mkdir --parents ~/gitea/custom/conf/
  mv --verbose "$TMP_LOCATION"/gitea "$GITEA_BIN_LOCATION"
  chmod u+x --verbose "$GITEA_BIN_LOCATION"
  #ln --symbolic --verbose "$GITEA_BIN_LOCATION" ~/bin/gitea
  ## gitea does not recognize its real path, maybe use a wrapper for this
  install_gitea_wrapper
  ln --symbolic --verbose ~/.ssh ~/gitea/.ssh
  create_app_ini
  mysql --verbose --execute="CREATE DATABASE ${USER}_gitea"
  echo "The database initialisation may take a while ..."
  $GITEA_BIN_LOCATION migrate
  create_gitea_daemon_config
  supervisorctl reread
  supervisorctl update
  supervisorctl status
  sleep 5
  supervisorctl status
  $GITEA_BIN_LOCATION admin user create \
    --username "${ADMIN_USER}" \
    --password "${ADMIN_PASS}" \
    --email "${USER}"@uber.space \
    --admin \
    --config "/home/${USER}/gitea/custom/conf/app.ini"
  uberspace web backend set / --http --port 9000
  uberspace web backend list
  install_update_script
  printf "You can now access your $APP_NAME by directing you Browser to: \n https://%s.uber.space \n" "$USER"
}

function install_gitea_wrapper
{
  cat << 'end_of_content' > ~/bin/gitea
#!/usr/bin/env bash

## No linking to the gitea binary as that would not recognize its real path,
## so it would set the wrong working directory settings. We just use a wrapper script instead.
export GITEA_WORK_DIR=$HOME/gitea

FIRST_PARAMETER="$1"
GITEA_BIN_LOCATION=$HOME/gitea/gitea

case $FIRST_PARAMETER in
  start | stop | restart | status )
  supervisorctl $FIRST_PARAMETER gitea
  exit $?
  ;;
  update | upgrade )
  gitea-update
  exit $?
  ;;
  log | logs )
  less ~/logs/supervisord.log
  exit $?
  ;;
  backup )
  ## this command creates a backup zip file with db, repos, config, log, data
  ## restoring the backup is more difficult
  ## read: https://docs.gitea.io/en-us/backup-and-restore/#restore-command-restore
  $GITEA_BIN_LOCATION dump --tempdir $HOME/tmp
  exit $?
  ;;
esac

$GITEA_BIN_LOCATION "$@"
exit $?
end_of_content
  chmod u+x --verbose ~/bin/gitea
}

function create_app_ini
{
  SECRET_KEY=$($GITEA_BIN_LOCATION generate secret SECRET_KEY)
  cat << end_of_content > ~/gitea/custom/conf/app.ini
APP_NAME = Gitea
RUN_USER = $USER
RUN_MODE = prod ; Either "dev", "prod" or "test", default is "dev".

[server]
HTTP_PORT            = 9000
DOMAIN               = $USER.uber.space
ROOT_URL             = https://%(DOMAIN)s
OFFLINE_MODE         = true ; privacy option.

[database]
DB_TYPE  = mysql
HOST     = 127.0.0.1:3306
NAME     = ${USER}_gitea
USER     = $USER
PASSWD   = $MYSQL_PASSWORD
SSL_MODE = disable

[security]
INSTALL_LOCK        = true
MIN_PASSWORD_LENGTH = 8
PASSWORD_COMPLEXITY = lower
SECRET_KEY          = $SECRET_KEY

[service]
DISABLE_REGISTRATION       = true ; security option, only admins can create new users.
SHOW_REGISTRATION_BUTTON   = false
REGISTER_EMAIL_CONFIRM     = true
DEFAULT_ORG_VISIBILITY     = private ; [public, limited, private]
DEFAULT_KEEP_EMAIL_PRIVATE = true
NO_REPLY_ADDRESS           = noreply.${USER}.uber.space

[mailer]
ENABLED     = true
MAILER_TYPE = sendmail
FROM        = ${USER}@uber.space

[repository]
DEFAULT_BRANCH = main
end_of_content
}

function create_gitea_daemon_config
{
  cat << end_of_content > ~/etc/services.d/gitea.ini
[program:gitea]
directory=%(ENV_HOME)s/gitea
command=gitea web
startsecs=30
autorestart=true
end_of_content
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
    echo "$GPG_KEY_FINGERPRINT:6:" | gpg --import-ownertrust
  fi

  if gpg --verify "$TMP_LOCATION"/gitea.asc "$TMP_LOCATION"/gitea
  then rm "$TMP_LOCATION"/gitea.asc; return 0
  else echo "gpg verification results in a BAD signature"; exit 1
  fi
}

function install_update_script
{
  cat << 'end_of_content' > ~/bin/gitea-update
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
  wget --quiet --progress=bar:force --output-document $TMP_LOCATION/gitea "$DOWNLOAD_URL"
  verify_file
  supervisorctl stop gitea
  mv --verbose $TMP_LOCATION/gitea "$GITEA_LOCATION"
  chmod u+x --verbose "$GITEA_LOCATION"
  echo "Start gitea migration"
  $GITEA_LOCATION migrate
  supervisorctl start gitea
  sleep 5
  supervisorctl status gitea
}

function get_local_version
{
  LOCAL_VERSION=$($GITEA_LOCATION --version |
    awk '{print $3}')
}

function get_latest_version
{
  curl --silent $GITHUB_API_URL > $TMP_LOCATION/github_api_response.json
  TAG_NAME=$(jq --raw-output '.tag_name' $TMP_LOCATION/github_api_response.json)
  LATEST_VERSION=${TAG_NAME:1}
  DOWNLOAD_URL=$(jq --raw-output '.assets[].browser_download_url' $TMP_LOCATION/github_api_response.json |
    grep --max-count=1 "linux-amd64")
}

function get_signature_file
{
  SIGNATURE_FILE_URL=$(jq --raw-output '.assets[].browser_download_url' $TMP_LOCATION/github_api_response.json |
    grep "linux-amd64.asc")
  rm $TMP_LOCATION/github_api_response.json
  wget --quiet --progress=bar:force --output-document $TMP_LOCATION/gitea.asc "$SIGNATURE_FILE_URL"
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
    echo "$GPG_KEY_FINGERPRINT:6:" | gpg --import-ownertrust
  fi

  if gpg --verify $TMP_LOCATION/gitea.asc $TMP_LOCATION/gitea
  then rm $TMP_LOCATION/gitea.asc; return 0
  else echo "gpg verification results in a BAD signature"; exit 1
  fi
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
  get_local_version
  get_latest_version

  if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]
  then
    echo "Your $APP_NAME is already up to date."
    echo "You are running $APP_NAME $LOCAL_VERSION"
  else
    if version_lt "$LOCAL_VERSION" "$LATEST_VERSION"
    then
      echo "There is a new version available."
      echo "Doing update from $LOCAL_VERSION to $LATEST_VERSION"
      do_update_procedure
    fi
  fi
}

main "${@}"
exit $?
end_of_content
  chmod u+x --verbose ~/bin/gitea-update
}

function yes-no_question
{
  local question=$1
  while true
  do
  read -r -p "$question (y/n) " ANSWER
  case $ANSWER in
    [Yy]* | [Jj]* )
      return 0
      ;;
    [Nn]* )
      return 1
      ;;
    * ) echo "Please answer yes or no. ";;
  esac
  done
}

function set_critical_section { set -o pipefail -o errexit; }
function unset_critical_section { set +o pipefail +o errexit; }

function main
{
  set_critical_section

  echo "This script installs the latest release of $APP_NAME"
  echo "and assumes a newly created Uberspace with default settings."
  echo "Do not run this script if you already use your Uberspace for other apps!"

  if yes-no_question "Do you want to execute this installer for $APP_NAME?"
  then install_gitea
  fi

  unset_critical_section
}

main "$@"
exit $?
