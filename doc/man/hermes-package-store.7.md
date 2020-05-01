hermes-package-store(7) - Hermes package store
===============================================

## SYNOPSIS

A hermes package store directory tree rooted at `HERMES_STORE` after initialization:

    $HERMES_STORE
    ├── etc
    │   └── hermes
    │       ├── cfg.jdn
    │       ├── signing-key-$ID.pub
    │       ├── signing-key-$ID.sec
    │       ├── signing-key.pub -> ./signing-key-$ID.pub
    │       ├── signing-key.sec -> ./signing-key-$ID.sec
    │       └── trusted-pub-keys
    ├── hpkg
    └── var
        └── hermes
            ├── hermes.db
            └── lock
                └── gc.lock

## DESCRIPTION

Hermes maintains a database of packages which we refer to as a package store, this manual page describes all aspects of the package store.
In general, a user will not need to manually edit the contents of the store, instead letting hermes maintain most of these files.

## FILES

* `/etc/hermes/cfg.jdn` - This is the store config. It's format will be discussed in [CONFIGURATION][].

* `/etc/hermes/signing-key-$ID.sec` - The store secret key in a format understood by hermes-signify(1).
  The store uses this key to prove it's identity to peer package stores during package export. In general, package stores
  only accept packages from package stores with a corresponding entry in the `/etc/hermes/trusted-pub-keys` directory.

* `/etc/hermes/signing-key-$ID.pub` - A store public key in a format understood by hermes-signify(1). This
  key can be added to peer package stores to enable trusted package transfers between them.

* `/etc/hermes/signing-key.sec` - A symlink link to the secret key package path without the key ID.

* `/etc/hermes/signing-key.pub` - A symlink link to the public key package path without the key ID.

* `/etc/hermes/trusted-pub-keys` - A directory containing public keys from other package store this package store trusts. Trust
  means the package store considers packages signed by the corresponding secret key valid for the given package hash.
  A user may manually copy keys into this store to setup trust. The trust system is used as a basis for the security of
  commands like hermes-cp(1), hermes-pkgstore-recv(1).

* `/hpkg` - The directory where all packages are installed into. Packages are generally accessed via symlinks into
  this directory. Directories within `/hpkg` have names of the form $HASH or $HASH-$NAME.

* `/var/hermes/hermes.db` An sqlite3 database containing a list of all installed packages, metadata and package roots.
  See [PACKAGE DATABASE][] for documentation on the database schema.

* `/var/hermes/lock/`  - A directory containing lockfiles used by hermes, see [LOCKS][] for information about
possible locks.


## CONFIGURATION

`cfg.jdn` is a `Janet Data Notation` file, containing package store specific configuration, it is a jdn table containing some or all of the following
configuration keys.

- `:mode` - The value should be one of `:multi-user` or `:single-user`. A single user store is owned by one user, and only this user may use packages stored in it.
  A multi user store is owned by root and allows multiple users to build packages. hermes-pkgstore-init(1) will initialize this value appropriately.

- :authorized-group - In multi user mode, only users that are part of this (string type) user group have permission to run hermes-pkgstore(1) commands against the package store.
  The default value is `wheel`, however it can be freely changed.

- :sandbox-build-users - In multi user mode, when a package build occurs, the build job is run as a build user taken from this string list. Additional isolation is applied to ensure
  package build security. The default value for this list is `["hermes_build_user0..9"]` It is the system administrators responsibility to ensure these build users are configured for
  the system.

Example multi-user configuration:

```
{
  :mode :multi-user
  :authorized-group "wheel"
  :sandbox-build-users [
    "hermes_build_user0"
    ...
    "hermes_build_user9"
  ]
}
```

Example single-user configuration:

```
{
  :mode :single-user
}
```

## PACKAGE DATABASE

`hermes.db` is an sqlite3 database with the following tables:

`Roots(LinkPath text primary key)` - A table containing known paths to package roots, each root was once a symlink to a package in the `/hpkg` directory. This table is traversed during package garbage collection
to delete unreferenced packages.

`Pkgs(Hash text primary key, Name text, TTLExpires integer)` - A table containing information about packages that had successful builds. `Hash` and `Name` can be 
combined to find the package path on disk. `TTLExpires` is a unix timestamp that marks the point in time the package is eligible for garbage collection.

`Meta(Key text primary key, Value text)` - A set of arbitrary key/value pairs. Currently only one key is used, 'StoreVersion', and this value is set to 1.

## LOCKS

Within the lock directory there are a few types of lock files used, they protect the integrity of the package store
when multiple users are building packages. Locking is done cooperatively by hermes-pkgstore(1) instances using system
specific method.

The follow is a summary of the various locks used by hermes.

- `gc.lock` This lock is aquired in an exclusive manner when hermes-pkgstore-gc(1) is running. This lock is also acquired in a shared
  manner while the package store is being updated, such as by hermes-pkgstore-build(1).

- `build-$HASH.lock` This form of lockfile corresponds to a package, and are held exclusively during package builds preventing multiple
  instances of hermes-pkgstore-build(1) from attempting to build the same package.

- `user-$NAME.lock` This form of lockfile corresponds to a build user when the package store is in multi user mode. The lockfile is held exclusively
  when a build user is being used during a package build. These locks help ensure isolation of the package builds, preventing one package build
  from influencing the package output of a concurrently building package.

The user and build lock files are removed when it is safe to do so, sometimes after a package build and always during a run of hermes-pkgstore-gc(1).

## SEE ALSO

hermes(1), hermes-pkgstore(1), hermes-signify(1)
