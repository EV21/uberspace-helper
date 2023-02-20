# Uberspace Helper Scripts

- [♾️ Nextcloud Installer](#nextcloud-installer-script)
- [☕ Gitea Installer](#gitea-installer-script)

## Nextcloud installer script

The lab guide is condensed into a script so Nextcloud can be installed  in less than 3 minutes by executing only one command and setting the admin user credentials.

The following components will be set up and installed automatically:

- php settings
- sendmail email settings
- cronjob
- prettier URLs without index.php
- Memcaching with redis and APCu
- Client Push (notify_push)
- `nextcloud-update` script
- the default phone region will be set to `DE`, you may change it after the installation to a different setting
- `ncc` wrapper command for `occ` with bash completion

Connect via SSH to your Uberspace an then run:

```sh
bash -c "$(wget -q -O - https://github.com/EV21/uberspace-helper/raw/main/nextcloud-installer.sh)"
```

alternatively something shorter:

```sh
bash -c "$(wget -q -O - https://sh.ev21.de/uberspace/nextcloud-installer.sh)"
```

## Demo

<!-- markdownlint-disable-next-line MD034 -->
https://user-images.githubusercontent.com/8345730/154812905-970c649d-4360-4846-961c-1d8363d662f2.mp4

<!-- unused
[nextcloud-installer-gif-demo]: ./presentation/uberspace-nextcloud-installer.gif
-->

---

## Gitea installer script

The following steps will be done automatically:

- check gpg signature
- install `gitea` convenience wrapper script  
  `gitea update`, `gitea log`, `gitea start | stop | restart | status`, `gitea backup`
- install `gitea-update` script

Connect via SSH to your Uberspace an then run:

```sh
bash -c "$(wget -q -O - https://github.com/EV21/uberspace-helper/raw/main/gitea-installer.sh)"
```

```console
[isabell@stardust ~]$ bash -c "$(wget -q -O - https://sh.ev21.de/uberspace/gitea-installer.sh)"
This script installs the latest release of Gitea
and assumes a newly created Uberspace with default settings.
The following files and directories will be created:
/home/ubertest
├── bin
│   ├── [-rwxrw-r--] gitea (wrapper script)
│   └── [-rwxrw-r--] gitea-update
├── etc
│   ├── services.d
│   │   └── gitea.ini
│   └── ...
├── gitea
│   ├── custom
│   │   └── conf
│   │       └── app.ini (configuration file)
│   ├── data
│   └── [-rwxrw-r--] gitea (binary file)
└── ...
Do not run this script if you already use your Uberspace for other apps!
Do you want to execute this installer for Gitea? (y/n) y
Installing Gitea 1.18.4
Please set your Gitea login credentials.
Gitea admin user: AdminUserName
Your password input will not be visible.
Gitea admin password:
Gitea admin password confirmation:
... some magic moments later
You can now access your Gitea by directing you browser to:
 https://isabell.uber.space
[isabell@stardust ~]$
```
