## Nextcloud installer script
The lab guide is condensed into a script so Nextcloud can be installed  in less than 3 minutes by executing only one command and setting the admin user credentials.

Connect via SSH to your Uberspace an then run:

```
bash -c "$(wget -q -O - https://github.com/EV21/uberspace-helper/raw/main/uberspace-nextcloud-installer.sh)"
```

## Demo

![Nextcloud-Installer-Demo][nextcloud-installer-demo]

[nextcloud-installer-demo]: ./presentation/uberspace-nextcloud-installer.gif