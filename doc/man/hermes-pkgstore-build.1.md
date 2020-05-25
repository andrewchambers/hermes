hermes-pkgstore-build(1)
========================

## SYNOPSIS

Build a marshalled package in a package store.

`hermes-pkgstore build [option] ...`

## DESCRIPTION

`hermes-pkgstore build` is a low-level build command usd by the higher level hermes-build(1)
command.

`--package` is a marshalled package object, containing instructions on how to build a package
and all of its dependencies.

`--fetch-sock` is a path to a socket to which the build proxies download requests. For remote
builds this fetch socket is proxied back to the build host allowing access to the client's
network and required local source artifacts.

## OPTIONS

* -f, --fetch-socket-path VALUE:
  Path to fetch socket to use during build.

* -p, --package VALUE:
  Path to marshalled package.

* --debug:
  Allow stdin and interactivity during build, build always fails.

* -n, --no-out-link:
   Do not create an output link.

* -o, --output VALUE=./result:
  Path to where package output link will be created.

* -j, --parallelism VALUE=1:
  Pass a parallelism hint to package builders.

* -s, --store VALUE=:
  Package store to use for build.

## SEE ALSO

hermes-pkgstore(1), hermes-package-store(7)
