# Hermes quick start for advanced users

## Installing Hermes

Installing from source:

- Ensure you have latest janet, pkg-config, curl, libarchive and libbsd installed.

```
$ git clone https://github.com/andrewchambers/hermes
...
$ cd hermes
$ jpm load-lockfile lockfile.jdn
...
$ jpm build
...
```

Once hermes and it's support programs are built, extract them to your PATH:

```
$ cd /home/me/bin
$ tar -xvzf $HERMES_SRC/build/hermes.tar.gz
```

## Installing precompiled Hermes

Coming soon...

## Initializing Hermes

Once hermes is installed and on your path:


```
$ export HERMES_STORE=/tmp/hermes-store
$ hermes init 
```

Lets see what you have just created:

```
/tmp/hermes-store/
├── etc
│   └── hermes
│       ├── cfg.jdn
│       ├── signing-key-7f9eea683ad4075532980857f3523dec.pub
│       ├── signing-key-7f9eea683ad4075532980857f3523dec.sec
│       ├── signing-key.pub -> ./signing-key-7f9eea683ad4075532980857f3523dec.pub
│       ├── signing-key.sec -> ./signing-key-7f9eea683ad4075532980857f3523dec.sec
│       └── trusted-pub-keys
├── hpkg
└── var
    └── hermes
        ├── hermes.db
        └── lock
            └── gc.lock

7 directories, 7 files
```

What are these files?

### /hpkg

This is the directory all your packages will be installed under.

### /etc/hermes/cfg.jdn

This is the store config. This store is setup in single user mode at the moment, so the 
config is relatively empty.

### /etc/hermes/signing-key...

This is a signing key related to package exports and downloads.

### /var/hermes/hermes.db

This is an sqlite database containing metadata about installed packages.

### /var/hermes/lock/*

Lock files used by hermes during package builds and other operations.


## Installing your first package

Now that hermes is installed and initialized, we can start to build packages:

First lets install the binary seed package:
```
$ git clone https://github.com/andrewchambers/hpkgs
$ hermes build --module ./hpkgs/core.janet --expression seed-env --output ./seed-env

building /tmp/hermes-store/hpkg/9fe12ef4bec689db93b9e8bdbd3b6d752dc619a8-seed.tar.gz...
fetching sha256:3d850f281e907d3b78599612ee1a17e63084b98947799a22a3e2a938db98e30a...
...
/tmp/hermes-store/hpkg/39c4105a12581e50027a505f3321b0670d937c32-seed
```

This created ./seed-env as a symlink into our package store, which is a package containing our 
package set bootstrap environment.

We can verify this:

```
$ readlink ./seed-env
/tmp/hermes-store/hpkg/39c4105a12581e50027a505f3321b0670d937c32-seed

$ ./seed-env/bin/ls ./seed-env/bin
'['         dir          link       od          split        vdir                           x86_64-linux-musl-readelf
 ar         dircolors    ln         paste       stat         wc                             x86_64-linux-musl-size
 awk        dirname      locate     patch       stdbuf       who                            x86_64-linux-musl-strings
....
```

## Uninstalling packages

In the previous section we installed a package, to remove packages, we must run the package garbage collector.

```
$ rm ./seed-env
$ hermes gc
deleting /tmp/hermes-store/hpkg/9fe12ef4bec689db93b9e8bdbd3b6d752dc619a8-seed.tar.gz
deleting /tmp/hermes-store/hpkg/39c4105a12581e50027a505f3321b0670d937c32-seed
```

Packages that are not reachable by any links created by hermes will automatically be deleted.

## Building a package from source

The previous package was quite boring, it just downloaded it from the internet... Hermes is supposed to be about building
packages from source!

```
$ hermes build -m ./hpkgs/core.janet -e core-env
...
...build output whizzing past...
...
/tmp/hermes-store/hpkg/c7e0d1a92cbd5492a5468c74a2b65bd16b3af14e-core-env
```

Now ./result contains a more impressive package!

```
$ tree ./result
./result
├── activate
└── bin
    ├── [ -> /tmp/hermes-store/hpkg/117a348b70fd002e5e885ed2ddf30724d2e84809-coreutils/bin/[
    ├── awk -> /tmp/hermes-store/hpkg/431dc40f0b66e6250fad2a5f962d246e7cda673c-awk/bin/gawk
    ├── basenc -> /tmp/hermes-store/hpkg/117a348b70fd002e5e885ed2ddf30724d2e84809-coreutils/bin/basenc
    ├── bunzip2 -> /tmp/hermes-store/hpkg/3ff2c672888768ec2a9b2d98b31da3357d6c4c43-bzip2/bin/bunzip2
...
```

We can clean up the intermediate artifacts we no longer care about...

```
$ hermes gc
deleting /tmp/hermes-store/hpkg/9ed275376722deeb1ecf68d94675b85a579fff12-xz-5.2.4.tar.gz
deleting /tmp/hermes-store/hpkg/ffae58192dcb3e087f1e07fad24c04ddc6b8965f-grep-3.3.tar.xz
deleting /tmp/hermes-store/hpkg/5432124392eb57fb610f0ad2c40286ce4ffb28e2-lzip-1.21.tar.gz
deleting /tmp/hermes-store/hpkg/c992b1918098b76771c3b572c705537482a4a786-dash-0.5.10.tar.gz
...
```

## Transferring packages between computers

We can use ```hermes cp``` to transfer arbitrary packages between computers, provided hermes is installed, 
and has a package store at the same path.

```
$ hermes cp ./my-package ssh://my-other-server/home/me/my-package
```

## Writing your own packages

TODO ...

## Multi user install of hermes

TODO ...


## Regenerating the seed environment

It's pretty lame to have to trust the seed environment, luckily, rebuilding it yourself
is simple.

```
$ hermes build -m ./hpkgs/core.janet -e seed-out
```