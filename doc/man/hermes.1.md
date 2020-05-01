hermes(1) -- Software Environment Manager
=========================================

## SYNOPSIS

`hermes` init ...<br>
`hermes` build ...<br>
`hermes` gc ...<br>
`hermes` cp ...<br>
`hermes` show-build-deps ...<br>

## DESCRIPTION

`hermes` is a tool for converting software definitions, written in a packaging domain
specific language, into usable software. 

Some notable features of ```hermes``` include:

* A decentralized packaging model.
* Easy installation of software over URLS.
* Easy transfer of software environments between computers.
* Avoidance of version conflicts with already installed software.
* Installing software from source code.
* Transparent build artifact caching.
* Strong support for software auditability.
* Transparent build caching.
* Remote package builds.
* Remote deployments.
* Atomic upgrades and rollback.

The hermes command is split into sub-commands which can be executed to interact with the package
store and package definitions.
Using the `hermes` command and suitable package definitions, you will be able to install, and deploy
software both locally and remotely. Each subcommand listed in the synopsis  has it's own man page,
which are linked below.


## PRIMARY SUBCOMMANDS

* hermes-init(1) - Initialize a package store.
* hermes-build(1) - Install or build a package from a given package path or url.
* hermes-gc(1) - Remove packages that are no longer in use.
* hermes-cp(1) - Copy packages between local or remote package stores.

## AUXILLARY SUBCOMMANDS

* hermes-show-build-deps(1) - Show a visualization package of build time dependencies.

## ENVIRONMENT

  * `HERMES_STORE`:
    The path to the package store commands are run against. If unset a root owned, multi user package store
    is assumed.

## SEE ALSO

hermes-pkgstore(1), hermes-package-store(7)
