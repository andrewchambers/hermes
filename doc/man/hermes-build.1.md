hermes-build(1) 
==============

## SYNOPSIS

`hermes` build `[options...]` `[MODULE]`

## DESCRIPTION

`hermes build` evaluates a package module and then attempts to build the package returned by the expression `--expression` option.
The path to the resulting package is printed to stdout and a link to the package in the package store is installed at `--output`.
The output link created is remembered by hermes, and neither the package or runtime dependencies will  
be deleted by hermes-gc(1) until it is removed. If the package or it's dependencies already exists in the package store,
then the package is not rebuilt.

The `--build-host` option allows building+fetching packages on a remote host. The remote host must have its public key
added to the set of trusted keys in the hermes-package-store(7) /etc directory. Copying of build artifacts between hosts is performed
via ssh so the current user must have an ssh key configured to access the build host. The build host must have a package
store at `HERMES_STORE` and must have hermes installed and on the users PATH. It is important to know that network access
and limited file access is proxied back to localhost, meaning although the remote servers cpu/memory/disk is used to
perform the build, some `fetch` requests may occur on the local machine.

When using the global package store, builds are performed in a sandbox by a build user on the current user's behalf. When
hermes is using a single user package store, builds are performed as that user with little or no sandboxing.

It is safe to run `hermes build` many times concurrently, even building the same package. Either `hermes build` will divide
work evenly between build processes, or will wait until it is able to continue.

## OPTIONS

```
     --build-host VALUE        Build on a remote host and copy the package back.
     --debug                   Allow stdin and interactivity during build, build always fails.
 -e, --expression VALUE        Expression to build, defaults to the hpkg file name.
 -n, --no-out-link             Do not create an output link.
 -o, --output VALUE=./result   Path to where package output link will be created.
 -j, --parallelism VALUE=1     Pass a parallelism hint to package build functions.
```

## ENVIRONMENT

  * `HERMES_STORE`:
    The path of the package store to build packages for. When --build-host is set
    the path is also used for the remote package store.

## EXAMPLES

### Install and run an hpkg from a git repository
```
$ git clone https://github.com/andrewchambers/hpkgs
...
$ hermes build ./hpkgs/core.hpkg -e gcc -o ./gcc
...
$ ./gcc/bin/gcc --version
gcc (GCC) 9.2.0
```

### Install a package from an https url
```
$ hermes build https://raw.githubusercontent.com/andrewchambers/hpkgs/$COMMIT/community/busybox.hpkg
...
$ ./result/bin/echo hello
hello
```

## SEE ALSO

hermes(1),hermes-cp(1)
