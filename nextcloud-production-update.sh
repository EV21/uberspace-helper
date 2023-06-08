#!/usr/bin/env bash

APP_NAME=Nextcloud
APP_LOCATION=/var/www/virtual/$USER/html
TMP_LOCATION=~/tmp

VERBOSE_OUTPUT=true
NO_BACKUP=false
NO_INTERACTION=false

ORG=nextcloud # Organisation or GitHub user
REPO=server
GITHUB_API_URL=https://api.github.com/repos/$ORG/$REPO/releases

function ncc
{
  php "$APP_LOCATION"/occ "$@"
}

function is_verbose
{
  if [[ $VERBOSE_OUTPUT == "true" ]]
  then return 0
  else return 1
  fi
}

function verbose_echo
{
  if is_verbose
  then echo "$@"
  fi
}

function get_current_version
{
  ncc --version |
    awk '{print $NF}'
}

function get_major_version
{
  local complete_version=$1
  echo "$complete_version" | awk --field-separator "." '{print $1}'
}

function get_latest_version
{
  tag_name=$(curl --silent $GITHUB_API_URL > "$TMP_LOCATION"/github_api_response.json
    jq . "$TMP_LOCATION"/github_api_response.json |
    jq 'map(select(.tag_name | test("(v'"$MAJOR_VERSION"'.\\d+.\\d+$)")))' |
    jq --raw-output '.[0].tag_name')
  rm "$TMP_LOCATION"/github_api_response.json
  ## remove the first character 'v', for example 'v24.0.1' -> '24.0.1' using substring syntax
  local version="${tag_name:1}"
  echo "$version"
}

function do_update_procedure
{
  cd $TMP_LOCATION || exit 1
  folder_should_not_exist "$TMP_LOCATION/nextcloud"
  verbose_echo "Download latest-$MAJOR_VERSION.zip"
  local release_archive="latest-$MAJOR_VERSION.zip"
  local signature_file=${release_archive}.asc
  curl --progress-bar --remote-name https://download.nextcloud.com/server/releases/"$release_archive"
  curl --silent --remote-name https://download.nextcloud.com/server/releases/"$signature_file"
  curl --silent --remote-name https://nextcloud.com/nextcloud.asc
  gpg --import nextcloud.asc
  if ! gpg --verify "$TMP_LOCATION/$signature_file" "$TMP_LOCATION/$release_archive"
  then echo "gpg verification results in a BAD signature"; exit 1
  fi
  verbose_echo "unzip latest-$MAJOR_VERSION.zip"
  unzip -q latest-"$MAJOR_VERSION".zip
  verbose_echo "Copy config to new version"
  cp "$APP_LOCATION"/config/config.php $TMP_LOCATION/nextcloud/config/
  if [[ $NO_BACKUP == "true" ]]
  then
    verbose_echo "Delete $APP_LOCATION"
    rm -r "$APP_LOCATION"
  else
    verbose_echo "Create application backup by moving the directory"
    verbose_echo "Destination: ~/nextcloud_application_backup_$CURRENT_VERSION"
    folder_should_not_exist ~/nextcloud_application_backup_"$CURRENT_VERSION"
    mv "$APP_LOCATION" ~/nextcloud_application_backup_"$CURRENT_VERSION"
  fi
  verbose_echo "Moving new files to destination"
  mv $TMP_LOCATION/nextcloud "$APP_LOCATION"
  verbose_echo "Removing setup files"
  rm latest-"$MAJOR_VERSION".zip
  rm latest-"$MAJOR_VERSION".zip.asc
  rm nextcloud.asc
  ## official docs: (!) this MUST be executed from within your nextcloud installation directory
  cd "$APP_LOCATION" || exit 1
  ncc upgrade
  ncc db:add-missing-primary-keys --no-interaction
  ncc db:add-missing-columns --no-interaction
  ncc db:add-missing-indices --no-interaction
  ncc db:convert-filecache-bigint --no-interaction
  ncc app:update --all
  ## App updates may require additional steps to be done by the `upgrade` command
  ncc upgrade
  /usr/sbin/restorecon -R "$APP_LOCATION"
  if test -f ~/etc/services.d/notify_push.ini
  then supervisorctl restart notify_push
  fi
}

function folder_should_not_exist
{
  local folder_path=$1
  if test -d "$folder_path"
  then
    echo "The folder should not exist at this point in time. Delete or move: $folder_path"
    echo "abort update procedure"
    exit 1
  fi
}

function process_parameters
{
  while test $# -gt 0
	do
    local next_parameter=$1
    case $next_parameter in
      --no-backup )
        NO_BACKUP=true
        shift
      ;;
      --no-interaction )
        NO_INTERACTION=true
        shift
      ;;
      --no-verbose | --quiet )
        VERBOSE_OUTPUT=false
        shift
      ;;
      * )
        echo "$next_parameter can not be processed, exiting script"
        exit 1
      ;;
    esac
  done
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

function is_data_used_in_nextcloud_directory
{
  test -d "$APP_LOCATION"/data || return 1
  # shellcheck disable=SC2012
  directory_elements_counter=$(ls "$APP_LOCATION"/data | wc -l)
  ## Some older releases provide a data folder with a index.html file
  if [[ directory_elements_counter -gt 1 ]]
  then return 0
  else return 1
  fi
}

function yes_no_question
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

function no_interaction_mode
{
  if [[ $NO_INTERACTION == "true" ]]; then return 0; else return 1; fi
}

function set_critical_section { set -o pipefail -o errexit; }
function unset_critical_section { set +o pipefail +o errexit; }

function main
{
  set_critical_section

  process_parameters "$@"

  CURRENT_VERSION=$(get_current_version)
  MAJOR_VERSION=$(get_major_version "$CURRENT_VERSION")
  LATEST_VERSION=$(get_latest_version)

  if is_data_used_in_nextcloud_directory
  then
    echo "It looks like your data directory is located at the default location inside Nextcloud root"
    echo "This is not supported by this update script. Please use an external location."
    exit 1
  fi

  if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]
  then
    verbose_echo "Your $APP_NAME $MAJOR_VERSION already has the latest point release."
    verbose_echo "You are running $APP_NAME $CURRENT_VERSION"
    if is_verbose; then ncc update:check; fi
    verbose_echo "If you want to do a major update don't skip major releases."
    verbose_echo "Example: 18.0.5 -> 18.0.11 -> 19.0.5 -> 20.0.2"
    verbose_echo "Therefore it is recommended to use the built-in updater"
  else
    if version_lower_than "$CURRENT_VERSION" "$LATEST_VERSION"
    then
      echo "There is a new point release version available."
      echo "Doing update from $CURRENT_VERSION to $LATEST_VERSION"
      if no_interaction_mode || yes_no_question "Do you want to start the update procedure?"
      then do_update_procedure
      fi
    fi
  fi

  unset_critical_section
}

main "$@"
exit $?