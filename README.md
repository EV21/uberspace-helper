## Nextcloud installer script
The lab guide is condensed into a script so Nextcloud can be installed  in less than 3 minutes by executing only one command and setting the admin user credentials.

The following components will be set up and installed automatically:

* php settings
* sendmail email settings
* cronjob
* prettier URLs without index.php
* Memcaching with redis and APCu
* Client Push (notify_push)
* nextcloud-update script
* the default phone region will be set to `DE`, you may change it after the installation to a different setting


Connect via SSH to your Uberspace an then run:

```
bash -c "$(wget -q -O - https://github.com/EV21/uberspace-helper/raw/main/uberspace-nextcloud-installer.sh)"
```

## Demo

https://user-images.githubusercontent.com/8345730/153936271-8dc9a823-97b3-4651-8731-d9a80885ee6e.mp4

[nextcloud-installer-gif-demo]: ./presentation/uberspace-nextcloud-installer.gif
