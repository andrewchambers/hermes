hermes-pkgstore-init(1)
=======================

## SYNOPSIS

Initialize a package store.

`hermes-pkgstore init [OPTIONS]...`

## DESCRIPTION

The init subcommand creates initializes a package store at the path passed by `--store`.
When `--store` is empty, it is assumed to be a multi user global installation, and will
only proceed if the current user is the root user.

When `--store` is non empty a single user package store is created which is owned by the 
current user.

Reinitializing the store as the same user used initially is an idempotent operation.

## OPTIONS

* -s, --store:
  The path to the package store to initialize.

## SEE ALSO

hermes-pkgstore(1), hermes-package-store(7)
