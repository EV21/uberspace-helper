#!/usr/bin/env bash

function install_nextcloud
{
  echo "Please set your Nextcloud login credentials."
  read -r -p "Nextcloud admin user: " NEXTCLOUD_ADMIN_USER
  read -r -p "Nextcloud admin password: " NEXTCLOUD_ADMIN_PASS
  setup_domains
  echo "Set one of the configured domains that your Nextcloud will be accessed with as \"trusted\":"
  read -r trusted_domain
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
  curl --progress-bar https://download.nextcloud.com/server/releases/latest.tar.bz2 |
    tar -xjf - --strip-components=1
  mysql --verbose --execute="CREATE DATABASE ${USER}_nextcloud"
  echo "Installing Nextcloud"
  php ~/html/occ maintenance:install \
    --admin-user "${NEXTCLOUD_ADMIN_USER}" \
    --admin-pass "${NEXTCLOUD_ADMIN_PASS}" \
    --database 'mysql' --database-name "${USER}_nextcloud" \
    --database-user "${USER}" \
    --database-pass "${MYSQL_PASSWORD}" \
    --data-dir "${HOME}/nextcloud_data"


  php ~/html/occ config:system:set trusted_domains 0 --value="$trusted_domain"
  php ~/html/occ config:system:set overwrite.cli.url --value="https://$trusted_domain"

  echo "Setting symbolic links for more easy log file access"
  ln --symbolic --verbose ~/nextcloud_data/nextcloud.log ~/logs/nextcloud.log
  ln --symbolic --verbose ~/nextcloud_data/updater.log ~/logs/nextcloud-updater.log

  php ~/html/occ config:system:set mail_domain --value="uber.space"
  php ~/html/occ config:system:set mail_from_address --value="$USER"
  php ~/html/occ config:system:set mail_smtpmode --value="sendmail"
  php ~/html/occ config:system:set mail_sendmailmode --value="pipe"

  php ~/html/occ config:system:set htaccess.RewriteBase --value='/'
  php ~/html/occ maintenance:update:htaccess

  echo "*/5  *  *  *  * php -f $HOME/html/cron.php > $HOME/logs/nextcloud-cron.log 2>&1" |
    crontab -
  php ~/html/occ background:cron

  php ~/html/occ config:system:set memcache.local --value='\OC\Memcache\APCu'
  php ~/html/occ config:system:set default_phone_region --value='DE'

  setup_redis
  install_notify_push
  install_nextcloud_updater

  /usr/sbin/restorecon -R ~/html

  echo "You can now access your Nextcloud by directing you Browser to https://$trusted_domain"
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
}

function setup_php
{
  uberspace tools version use php 8.0
  echo "Applying relevant PHP settings for Nextcloud"
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
  php ~/html/occ config:system:set redis host --value="${HOME}/.redis/sock"
  php ~/html/occ config:system:set redis port --value=0
  php ~/html/occ config:system:set redis timeout --value=1.5
  php ~/html/occ config:system:set filelocking.enabled --value='true'
  php ~/html/occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
  php ~/html/occ config:system:set memcache.distributed --value='\OC\Memcache\Redis'
}

function install_notify_push
{
  php ~/html/occ app:install notify_push
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
  php ~/html/occ config:system:set trusted_proxies 0 --value="$trusted_proxy"
  php ~/html/occ notify_push:setup https://"$trusted_domain"/push
}

function install_nextcloud_updater
{
  touch ~/bin/nextcloud-update
  cat << end_of_content > ~/bin/nextcloud-update
#!/usr/bin/env bash
## Updater automatically works in maintenance:mode.
## Use the Uberspace backup system for files and database if you need to roll back.
## The Nextcloud updater creates backups only to safe base and app code data and config files
## so it takes ressources you might need for your productive data.
## Deactivate NC-updater Backups with --no-backup (works from 19.0.4, 18.0.10 and 17.0.10)
php ~/html/updater/updater.phar -vv --no-backup --no-interaction

## database optimisations
php ~/html/occ db:add-missing-primary-keys --no-interaction
php ~/html/occ db:add-missing-columns --no-interaction
php ~/html/occ db:add-missing-indices --no-interaction
php ~/html/occ db:convert-filecache-bigint --no-interaction

php ~/html/occ app:update --all
/usr/sbin/restorecon -R ~/html

## If you have set up the notify_push service uncomment the following line by removing the #
supervisorctl restart notify_push
end_of_content
  chmod +x ~/bin/nextcloud-update
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

  echo "This script tries to install the latest release of Nextcloud"
  echo "but it is tested for Nextcloud 23 on Uberspace 7.12.0"
  echo "and assumes a newly created Uberspace with default settings."
  echo "Do not run this script if you already use your Uberspace for other apps!"

  if yes-no_question "Do you want to execute this installer for Nextcloud?"
  then install_nextcloud
  fi

  unset_critical_section
}

main "$@"
exit $?
