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