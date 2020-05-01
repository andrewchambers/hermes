# Installing Hermes

## Installing a precompiled Hermes

Download a release from the [releases page](https://github.com/andrewchambers/hermes/releases) and extract the contents into your PATH.

```
$ cd /home/me/bin
$ tar -xvzf ~/Downloads/hermes-$VERSION.tar.gz
```

## Installing from source.

Ensure you have a C compiler, latest janet from git, pkg-config, libbsd and libarchive for your distribution.

Clone the source code using Git.

```
$ git clone --recurse-submodules https://github.com/andrewchambers/hermes
$ cd hermes
```

Optionally configure a project local directory for janet jpm dependencies.

```
$ export JANET_PATH="$(pwd)/janet_modules"
$ mkdir $JANET_PATH

```

Install janet dependencies using jpm.

```
$ jpm load-lockfile lockfile.jdn
$ jpm build
```

Once hermes and it's support programs are built, extract them to your PATH:

```
$ cd /home/me/bin
$ tar -xvzf $HERMES_SRC/build/hermes.tar.gz
```

Once this is done you can optionally enable multi user mode, outlined below.

### Building from source once you already have hermes installed

As hermes can manage dependencies, it can be used to manage it's own dependencies.

Initialize a package store:

```
$ hermes init
```

Use the provided dev-shell script to configure and enter a development environment. If your hermes package store does not have a cache server configured, it may take a while
as the correct version of gcc may be compiled from source code.

```
$ cd hermes
$ sh ./support/dev-shell.sh
$ jpm load-lockfile lockfile.jdn
$ jpm build
```

This is useful as it ensures you have exactly the same build environment as are used for releases.

## Multi user install

Hermes also supports a shared system package store, though to use hermes in this mode requires slightly more configuration.

First install hermes as root:

```
$ cd /usr/bin/
$ sudo tar -xvzf $HERMES_SRC/build/hermes.tar.gz
$ sudo chown root:root hermes*
```

Next set mark the hermes-pkgstore binary as setuid and setgid, this allows the hermes backend to
dispatch build tasks to isolated build users and enables build sandboxing, and allows less privileged users install packages into /hpkg securely.

```
$ sudo chmod u+s,g+s hermes-pkgstore
```

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