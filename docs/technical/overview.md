# Technical overview of hermes

Hermes is a package manager inspired by [Nix](https://nixos.org/) and [Guix](https://guix.gnu.org/)
with some new ideas added, and being built on top of the janet programming language.

## Key ideas

- Packages are defined by some metadata and a janet function that when called, builds the package
  and installs the result to a path we shall call :pkg-out.

- :pkg-out is computed as the repeatable cryptographic hash of the package data + the build function.

- Most changes to a package, its build function, or dependencies will change the computed path on disk. This is similar to
  git commit hashes for those familiar.

- Because each package has a unique path, it is simple to avoid rebuilding packages that have already been built as
  you simply need to check the package store for this unique path.

- A package compile time dependency graph is the set of packages reachable by walking the 
  build functions bytecode. Cyclic dependencies are not allowed. Because we can walk this
  bytecode statically, we know the full dependency graph before we execute any code to build
  packages.

- A packages runtime dependencies are automatically scanned after a build completes. We can do this
  because each package has a unique hash we can identify.

- The package store is a collection of lock-files, packages and an sqlite database.

- When a package is installed, a symlink to it is placed on disk at a user requested location.
  This link is saved in the store sqlite database for later use by the garbage collector.

- When we want to uninstall unreferenced packages, we run the garbage collector. This walks
  the known set of symlinks, and recursively marks runtime dependencies as reachable. Unreachable
  packages can then be removed.


## Flow of building a package


```
$ hermes build --module ./hpkgs/core.janet --expression core-env --out-link my-env
/home/ac/hermes/pkg/833543b51594f0e67364956202a2e52fce82ffbc-core-env
$ ./my-env/bin/ls -la
..... my-env -> /home/ac/hermes/pkg/833543b51594f0e67364956202a2e52fce82ffbc-core-env
```


- A user invokes ```hermes build``` on a hermes package file.

- The file and expression is evaluated in a limited environment and returns a package object graph, which is a graph
  of build functions and package definitions.

- The hermes command marshals this package graph and invokes the equivalent to ```hermes-pkgstore build --store $STOREPATH --pkg $MARSHALLED_PKG```.
  It should be noted that the hermes-pkgstore may be executed on a remote machine via ssh with little complication.

- The hermes-pkgstore command unmarshals the package graph, computes the final package hashes, and for each
  subpackage, aquires the desired locks, and then invokes the required builder functions within a sandbox/chroot in dependency order.

- The requested package gets it's gc-root/link installed into the pkg store database and created on disk.


## Source overview

src/*

- hermes-main.janet is the main entry point a user interacts with.

- hermes-pkgstore-main.janet is a potentially setuid binary that manipulates the package store.

- pkgstore.janet contains of the logic related to the package store including the package builder
  and garbage collector.

- builder.janet defines the build environment of packages.

... Other files...