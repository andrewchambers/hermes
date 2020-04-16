# Hermes quick start

This quickstart is meant for confident users to quickly
get started using Hermes to install software.

Being familiar with the Janet programming language helps with writing packages,
but it is not necessary to use packages. 

People familiar with Nixos, or Guix may find some of the ideas familiar.

All that being said, if you are a confident computer user, this guide may be useful if
you are interested in diving into using Hermes.

## Installing Hermes

Installing from source:

- Ensure you have latest janet, pkg-config, curl, libarchive and libbsd installed.

```
$ git clone https://github.com/andrewchambers/hermes
$ cd hermes
$ jpm load-lockfile lockfile.jdn
$ jpm build
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

```

What are these files?

### /hpkg

This is the directory all your packages will be installed under.

### /etc/hermes/cfg.jdn

This is the store config. This store is setup in single user mode at the moment, so the 
config is relatively empty.

### /etc/hermes/signing-key...

Signing keys are related to how hermes package stores trust eachother to provide
secure packages across the network, we will cover them in a later section.

### /var/hermes/hermes.db

This is an sqlite database containing metadata about installed packages.

### /var/hermes/lock/*

Lock files used by hermes during package builds and other operations.


## Installing your first package

Now that hermes is installed and initialized, we can start building/installing packages.

First lets install the binary seed package (the root dependency of all packages.):
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

### A note about funny package paths

Hermes packages are installed into a path based on it's cryptographic hash. In practice this
simply means we can install many variations of the same package and not have to worry about them conflicting and breakign each other.

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

Now ./result contains a more impressive package! This package contains references to other packages, 
hermes automatically tracks these dependencies for you.

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

## Regenerating the seed environment

It's pretty sad to have to trust the seed environment, luckily, rebuilding it yourself is simple.

```
$ hermes build -m ./hpkgs/core.janet -e seed -o seed
$ hermes build -m ./hpkgs/core.janet -e seed-out -o seed-out
```

You can verify your binary seed has the same hash as the binary seed you originally downloaded.

```
$ sha256sum ./seed/seed.tar.gz ./seed-out/seed.tar.gz
```

When both hashes match, it means you have the ability to regenerate *all* of your hermes software from source. You have *total* control of your software stack :).

## Writing your own packages

TODO ...

## Multi user install

Until now, you have been user a private package store that only your
user can access. Hermes also supports a shared global package store.

To use hermes in this mode requires slightly more configuration.

First install hermes as root:

```
$ cd /usr/bin/
$ sudo tar -xvzf $HERMES_SRC/build/hermes.tar.gz
$ sudo chmod u+s,g+s hermes-pkgstore
```
Note, for a true multi-user install, we must install the pkgstore binary as setuid (The chmod command).
This lets less privileged users install packages into /hpkg securely.


Now we can initialize the global package store:

```
$ unset HERMES_STORE
$ sudo hermes init
```

Now that hermes is initialized, globally, we can check our store config:

```
$ sudo cat /etc/hermes/cfg.jdn
{
  :mode :multi-user
  :authorized-group "wheel"
  :sandbox-build-users [
    "hermes_build_user0"
    ...
  ]
}
```


Ensure your user is in the authorized group, as hermes will refuse to allow users not 
in this group to build packages.

When a package is built, hermes will perform the package build on your behalf inside a [chroot](https://en.wikipedia.org/wiki/Chroot) and
[sandbox](https://en.wikipedia.org/wiki/Sandbox_(computer_security)). 

You will also need to create user accounts for the sandbox build users,
how to do so varies system by system, but for many users this will be sufficient:

```
$ for i in `seq 0 9`
do
  sudo useradd --system --no-create-home --home /homeless hermes_build_user$i
done
```

## Configuring a cache server

TODO...

## Transparent remote builds

When building a package on a laptop, or other underpowered device, it is
useful to perform remote builds on a more powerful server. This can
easily be done with hermes, simply add the --build-host flag to your
build command.

```
$ hermes build -m ./hpkgs/core.janet -e seed-out --build-host ssh://your-server.com
```

The build will proceed exactly the same as a local build, but be performed on the
remote host, with the resulting package copied back locally.

It is important to note that builds referring to 'local-file packages still work without
change. The remote build transparently handles sending these files to the build host 
when they are needed.

## Transferring packages between computers

We can use ```hermes cp``` to transfer arbitrary packages (and their dependencies) between computers, provided hermes is installed, 
and has a package store at the same path.

```
$ hermes cp ./my-package ssh://my-other-server/home/me/my-package
```

## Uninstalling hermes

[see here](../uninstalling-hermes.md).