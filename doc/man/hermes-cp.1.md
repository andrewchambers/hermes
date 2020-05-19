hermes-cp(1) 
==============

## SYNOPSIS

`hermes` cp `[options...]` `FROM` `TO`

## DESCRIPTION

`hermes cp` copies a package and it's dependencies between package stores.

The hermes cp command copies packages by connecting an instance of hermes-pkgstore-send(1) to an instance of 
hermes-pkgstore-recv(1). This copy can take place over ssh if the FROM or TO argument is prefixed with `ssh://`.

If a package already on the destination host, the cp will skip sending the package. Sending packages is atomic
and is safe to resume on network interruption.

To ensure package security, the receiving package store must have the public key of the sending package store added
to it's set of trusted store keys.

## OPTIONS

```
--allow-untrusted 
  
  Allow the destination to ignore failed trust challenges if run by the store owner.

-t, --to-store VALUE 
  
  The store to copy into.
```

## EXAMPLES

### localhost to remote host
```
$ hermes cp ./my-package ssh://my-server.com/home/me/my-package
```

### remote host to local host
```
$ hermes cp ssh://my-server.com/home/me/my-package ./my-package
```

### between hosts
```
$ hermes cp ssh://my-server1.com/package ssh://my-server2.com/package
```

## SEE ALSO

hermes(1), hermes-pkgstore-send(1), hermes-pkgstore-recv(1)
