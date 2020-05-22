hermes-init(1) 
==============

## SYNOPSIS

Initialize a package store.

`hermes init `

## DESCRIPTION

`hermes init` initializes a package store with a base path at the environment
variable `HERMES_STORE`.

If `HERMES_STORE` is not set or empty, the package store is a multi user package store, and the initialization
must be performed by the root user.

If `HERMES_STORE` is set, the package store at this path is initialized and is owned by the current user.

For details about the contents of the package store after initialization, see hermes-package-store(7).

## ENVIRONMENT

  * HERMES_STORE:
    The path of the package store to initialize.

## SEE ALSO

hermes(1), hermes-pkgstore(1), hermes-package-store(7)
