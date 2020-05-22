hermes-cp(1) 
============

## SYNOPSIS

Copy packages and their dependencies between package stores.

`hermes cp [options...] FROM [TO]`

## DESCRIPTION

`hermes cp` copies a package pointed to by the package link `FROM` and create a new package link `TO`,
potentially to different package stores. The path to the receiving package store defaults to HERMES_STORE
or is taken from the `--to-store` argument if specified. If the TO link is omitted, the package is sent to the `--to-store` without creating a package link. If a `TO` link is created, it is saved by the receiving package
store as and prevents packages from being garbage collected until deleted.

The copy will take place via ssh(1) if either the FROM or TO argument is prefixed with `ssh://`.
Internally `hermes cp` operates by connecting an instance of hermes-pkgstore-send(1) to an instance of 
hermes-pkgstore-recv(1), so the hermes-pkgstore(1) command must be in the PATH for both the send
host and recv host.

If a package already on the destination host, the cp will skip sending the package, but still create the `TO` link.
Sending packages is done atomically, and therefore is crash safe and also safe to retry after network interruption.

To ensure package store integrity, the receiving package store must have
the public key of the sending package store added to it's set of trusted store keys (see hermes-package-store(7)).

The store path of the FROM and TO stores may differ, but if they do differ,
packages may not be runnable in place as absolute PATH references will not be correct.
This use case is generally used for intermediate package transfers.

## OPTIONS

* -t, --to-store VALUE:
  The store to copy into.

## EXAMPLES

### create a new package link
```
$ hermes cp ./my-package ./some-other-store
```

### local store to remote store
```
$ hermes cp ./my-package ssh://my-server.com/home/me/my-package
```

### remote store to local store
```
$ hermes cp ssh://my-server.com/home/me/my-package ./my-package
```

### remote store to remote store
```
$ hermes cp ssh://my-server1.com/package ssh://my-server2.com/package
```

## SEE ALSO

hermes(1), hermes-pkgstore-send(1), hermes-pkgstore-recv(1)
