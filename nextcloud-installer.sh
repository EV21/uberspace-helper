#!/usr/bin/env bash

APP_NAME=Nextcloud

function install_nextcloud
{
  echo "Please set your Nextcloud login credentials."
  read -r -p "Nextcloud admin user: " NEXTCLOUD_ADMIN_USER
  read -r -p "Nextcloud admin password: " NEXTCLOUD_ADMIN_PASS
  trusted_domain="$USER.uber.space"
  #setup_domains
  setup_php
  # simply get the first password string from ~/.my.cnf
  MYSQL_PASSWORD_STR=$(grep --max-count=1 password= ~/.my.cnf)
  # using bash substring syntax to remove the 9 characters "password="
  MYSQL_PASSWORD=${MYSQL_PASSWORD_STR:9}

  if [ -e ~/html/nocontent.html ]
  then rm ~/html/nocontent.html
  fi
  # shellcheck disable=2088
  if [ "$(ls --almost-all ~/html/)" ]; then echo '~/html is not empty, abort!'; exit 1; fi
  cd ~/html
  echo "Downloading Nextcloud to ~/html/"
  release_name=$(get_version_name)
  release_archive="$release_name".tar.bz2
  signature_file="$release_archive".asc
  curl --progress-bar --remote-name https://download.nextcloud.com/server/releases/"$release_archive"
  curl --silent --remote-name https://download.nextcloud.com/server/releases/"$signature_file"
  curl --silent --remote-name https://nextcloud.com/nextcloud.asc
  gpg --import nextcloud.asc
  PGP_KEY_FINGERPRINT='28806A878AE423A28372792ED75899B9A724937A'
  #gpg --keyserver pgp.mit.edu --recv-keys $PGP_KEY_FINGERPRINT
  echo "$PGP_KEY_FINGERPRINT:6:" | gpg --import-ownertrust
  if ! gpg --verify "$signature_file" "$release_archive"
  then echo "gpg verification results in a BAD signature"; exit 1
  fi
  echo "Extracting archive"
  tar -xjf "$release_archive" --strip-components=1
  rm "$release_archive" "$signature_file" nextcloud.asc
  mysql --verbose --execute="CREATE DATABASE ${USER}_nextcloud"
  echo "Installing Nextcloud"
  install_ncc
  ncc maintenance:install \
    --admin-user="${NEXTCLOUD_ADMIN_USER}" \
    --admin-pass="${NEXTCLOUD_ADMIN_PASS}" \
    --database='mysql' \
    --database-name="${USER}_nextcloud" \
    --database-user="${USER}" \
    --database-pass="${MYSQL_PASSWORD}" \
    --data-dir="${HOME}/nextcloud_data"

  ncc config:system:set trusted_domains 0 --value="$trusted_domain"
  ncc config:system:set overwrite.cli.url --value="https://$trusted_domain"

  echo "Setting symbolic links for more easy log file access"
  ln --symbolic --verbose ~/nextcloud_data/nextcloud.log ~/logs/nextcloud.log
  ln --symbolic --verbose ~/nextcloud_data/updater.log ~/logs/nextcloud-updater.log

  ncc config:system:set mail_domain --value="uber.space"
  ncc config:system:set mail_from_address --value="$USER"
  ncc config:system:set mail_smtpmode --value="sendmail"
  ncc config:system:set mail_sendmailmode --value="pipe"

  ncc config:system:set htaccess.RewriteBase --value='/'
  ncc maintenance:update:htaccess

  echo "*/5  *  *  *  * sleep $(( 1 + RANDOM % 60 )); php -f $HOME/html/cron.php > $HOME/logs/nextcloud-cron.log 2>&1" |
    crontab -
  ncc background:cron

  ncc config:system:set memcache.local --value='\OC\Memcache\APCu'
  ncc config:system:set default_phone_region --value='DE'

  setup_redis
  install_notify_push
  install_nextcloud_updater

  /usr/sbin/restorecon -R ~/html

  printf "If you want to use another domain read:\n https://lab.uberspace.de/guide_nextcloud/#set-the-trusted-domain\n"
  printf "You can now access your Nextcloud by directing you Browser to: \n https://%s \n" "$trusted_domain"
}

function uninstall_nextcloud
{
  unset_critical_section
  if ! yes-no_question "Do you want to keep the Nextcloud user files?"
  then rm -r ~/nextcloud_data
  fi
  if test -f ~/etc/services.d/notify_push.ini
  then
    supervisorctl stop notify_push
    rm ~/etc/services.d/notify_push.ini
    supervisorctl reread
    supervisorctl update
  fi
  if test -f ~/etc/services.d/redis.ini
  then
    supervisorctl stop redis
    rm ~/etc/services.d/redis.ini
    rm -r ~/.redis
    supervisorctl reread
    supervisorctl update
  fi
  rm -r ~/html/* ~/html/.htaccess ~/html/.user.ini
  mysql --verbose --execute="DROP DATABASE ${USER}_nextcloud"
  rm ~/bin/ncc ~/bin/nextcloud-update
  unlink ~/bin/notify_push
  unlink ~/logs/nextcloud.log
  unlink ~/logs/nextcloud-updater.log
  set_critical_section
}

function process_parameters
{
  while test $# -gt 0
	do
    local next_parameter=$1
    case $next_parameter in
      use )
        shift
        VERSION="$1"
        shift
      ;;
      uninstall )
        echo "This command tries to revert the $APP_NAME installation, it will delete all of its scripts, service config, ~/nextcloud_data directory with all contents and drops the database."
        if yes-no_question "Do you really want to do this?"
        then uninstall_nextcloud
        fi
        exit 0
      ;;
      * )
        echo "$1 can not be processed, exiting script"
        exit 1
      ;;
    esac
  done
}

function get_version_name
{
  if [[ -n $VERSION ]]
  then echo "nextcloud-$VERSION"
  else echo "latest"
  fi
}

function setup_domains
{
  echo "You currently have configured the following domains:"
  uberspace web domain list
  if yes-no_question "Do you want to add another domain to the web configuration of your uberspace?"
  then add_domain
  fi
}

function add_domain
{
  read -rp "Domain: " DOMAIN
  uberspace web domain add "$DOMAIN"
  trusted_domain=$DOMAIN
}

function setup_php
{
  echo "Applying relevant PHP settings for Nextcloud"
  uberspace tools version use php 8.1
  touch ~/etc/php.d/opcache.ini
  cat << end_of_content > ~/etc/php.d/opcache.ini
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
end_of_content

  touch ~/etc/php.d/apcu.ini
  cat << end_of_content > ~/etc/php.d/apcu.ini
apc.enable_cli=1
end_of_content

  touch ~/etc/php.d/memory_limit.ini
  cat << end_of_content > ~/etc/php.d/memory_limit.ini
memory_limit=512M
end_of_content

  touch ~/etc/php.d/output_buffering.ini
  cat << end_of_content > ~/etc/php.d/output_buffering.ini
output_buffering=off
end_of_content
  uberspace tools restart php
}

function setup_redis
{
  mkdir ~/.redis
  touch ~/.redis/conf
  cat << end_of_content > ~/.redis/conf
unixsocket /home/$USER/.redis/sock
daemonize no
port 0
save ""
end_of_content

  touch ~/etc/services.d/redis.ini
  cat << end_of_content > ~/etc/services.d/redis.ini
[program:redis]
command=redis-server %(ENV_HOME)s/.redis/conf
directory=%(ENV_HOME)s/.redis
autostart=yes
autorestart=yes
end_of_content
  supervisorctl reread
  supervisorctl update
  supervisorctl status
  ncc config:system:set redis host --value="${HOME}/.redis/sock"
  ncc config:system:set redis port --value=0
  ncc config:system:set redis timeout --value=1.5
  ncc config:system:set filelocking.enabled --value='true'
  ncc config:system:set memcache.locking --value='\OC\Memcache\Redis'
  ncc config:system:set memcache.distributed --value='\OC\Memcache\Redis'
}

function install_notify_push
{
  ncc app:install notify_push
  chmod u+x --verbose ~/html/apps/notify_push/bin/x86_64/notify_push
  ln --symbolic --verbose "$HOME"/html/apps/notify_push/bin/x86_64/notify_push ~/bin/notify_push
  touch ~/etc/services.d/notify_push.ini
  cat << end_of_content > ~/etc/services.d/notify_push.ini
[program:notify_push]
command=notify_push %(ENV_HOME)s/html/config/config.php
autostart=yes
autorestart=yes
end_of_content
  supervisorctl reread
  supervisorctl update
  supervisorctl status
  uberspace web backend set /push --http --port 7867
  uberspace web backend list
  local trusted_proxy
  trusted_proxy=$(ip route | 
    tail --lines 1 |    ## filter last line
    awk '{print $9}')   ## filter the last (9.) string from that line, it is the proxy ip
  ncc config:system:set trusted_proxies 0 --value="$trusted_proxy"
  ncc notify_push:setup https://"$trusted_domain"/push
}

function install_ncc
{
  touch ~/bin/ncc
  cat << 'end_of_content' > ~/bin/ncc
#!/usr/bin/env bash
php ~/html/occ "$@"
end_of_content
  chmod u+x ~/bin/ncc
}

function install_nextcloud_updater
{
  touch ~/bin/nextcloud-update
  cat << 'end_of_content' > ~/bin/nextcloud-update
#!/usr/bin/env bash

APP_LOCATION=~/html

function ncc
{
  php $APP_LOCATION/occ "$@"
}

## Updater automatically works in maintenance:mode.
## Use the Uberspace backup system for files and database if you need to roll back.
## The Nextcloud updater creates backups only to safe base and app code data and config files
## so it takes ressources you might need for your productive data.
## Deactivate NC-updater Backups with --no-backup
php $APP_LOCATION/updater/updater.phar --no-backup --no-interaction

## database optimisations
ncc db:add-missing-primary-keys --no-interaction
ncc db:add-missing-columns --no-interaction
ncc db:add-missing-indices --no-interaction
ncc db:convert-filecache-bigint --no-interaction

ncc app:update --all
/usr/sbin/restorecon -R $APP_LOCATION

if test -f ~/etc/services.d/notify_push.ini
then supervisorctl restart notify_push
fi
end_of_content
  chmod u+x ~/bin/nextcloud-update
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
  process_parameters "$@"

  if [[ -n $VERSION ]]
  then
    echo "This script installs $APP_NAME $VERSION"
    echo "We recommend to use the latest release."
    ## This feature is mainly used to install older versions and then test the update script.
  else
    echo "This script installs the latest release of $APP_NAME"
    echo "and assumes a newly created Uberspace with default settings."
  fi
  echo "Do not run this script if you already use your Uberspace for other apps!"

  if yes-no_question "Do you want to execute this installer for $APP_NAME?"
  then install_nextcloud
  fi

  unset_critical_section
}

main "$@"
exit $?
