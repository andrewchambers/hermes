# Uninstalling Hermes

## Single user installation:

```
rm /path/to/installation/bin/hermes*
rm -rf $HERMES_STORE
```

## Multi user installation:

Remove hermes files:

```
$ sudo su
# chmod -R +w /hpkg
# rm -rf /hpkg /var/hermes /etc/hermes
# rm /path/to/installation/bin/hermes*
```

Remove any hermes build users:

```
# for i in `seq 0 9`
do
  sudo userdel  hermes_build_user$i
done
```