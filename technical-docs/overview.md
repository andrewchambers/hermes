# Technical overview of hermes

Hermes is a package manager inspired by [Nix](https://nixos.org/) and [Guix](https://guix.gnu.org/)
with some new ideas added, and being built on top of the janet programming language.

## Key ideas

- Packages are defined by a janet function that when called, builds the package
  and installs the result to :pkg-out.

- :pkg-out is computed as the repeatable cryptographic hash of the package + the build function.

- Any change to a package or its build function, changes its computed path on disk. This is similar to
  git commit hashes for those familiar.

- As each package has a unique path, it is simple to avoid rebuilding packages that have already been built.

- A packages compile time dependency graph is simply the set of packages reachable by walking the 
  builder bytecode.

- A packages runtime dependencies are automatically scanned after a build completes. We can do this
  because each package has a unique hash we can identify.

- The package store is a collection of lockfiles, pkg paths and an sqlite database.

- When a package is installed, a symlink to it is placed on disk at a user requested location.
  This link is saved in the store sqlite database.

- When we want to uninstalled unreferenced packages, we run the garbage collector. This walks
  the known set of symlinks, and recursively marks runtime dependencies as reachable. Unreachable
  packages can be removed.


## Flow of building a package


```
$ hermes build --module ./hpkgs/core.janet --expression core-env --out-link my-env
/home/ac/hermes/pkg/833543b51594f0e67364956202a2e52fce82ffbc-core-env
$ ./my-env/bin/ls -la
..... my-env -> /home/ac/hermes/pkg/833543b51594f0e67364956202a2e52fce82ffbc-core-env
```


- A user invokes ```hermes build``` on a hermes package file.

- The file is evaluated in a limited environment and returns a package object graph, which is a graph
  of build functions and package definitions.

- The hermes command marshals this package graph and invokes the equivalent to ```hermes-pkgstore --store $STOREPATH --pkg $MARSHALLED_PKG```

- The hermes-pkgstore command unmarshals the package graph, computes the final package hashes, and for each
  subpackage, aquires the desired locks, and then invokes the required builder functions within a sandbox/chroot in dependency order.

- The requested package gets it's gc-root/link installed into the root database and saved to disk.


## Code overview


- hermes-main.janet is the main entry point a user interacts with.

- hermes-pkgstore-main.janet is a potentially setuid binary that manipulates the package store.

- pkgstore.janet contains of the logic related to the package store including the package builder
  and garbage collector.

- builder.janet defines the build environment of packages.

... Other files too.