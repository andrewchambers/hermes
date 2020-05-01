hermes-gc(1) 
==============

## SYNOPSIS

`hermes` gc 

## DESCRIPTION

`hermes gc` runs the garbage collector against the package store. Garbage collection means to walk the 
set of active package roots, (symlinks created by commands like hermes-cp(1) and hermes-build(1)) and
removes packages that are no longer referenced.

If a package build is in progress, hermes-gc(1) will wait before proceeding, during garbage collection
no additional package builds will be able to take place.

## ENVIRONMENT

  * `HERMES_STORE`:
    The path of the package store to garbage collect against.

## SEE ALSO

hermes(1), hermes-pkgstore(1), hermes-pkgstore-gc(1), hermes-package-store(7)
