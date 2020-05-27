hermes-pkgstore-send(1)
========================

## SYNOPSIS

Send a package closure over stdin/stdout with the send/recv protocol.

`hermes-pkgstore send [option] ...`

## DESCRIPTION

`hermes-pkgstore send` sends a package and its dependencies (also referred to as a package closure)
to an instance of `hermes-pkgstore recv`. To use this command you must arrange the stdout and stdin
of the send end to be connected to the stdin and stdout of the recv end.

Only packages the recv end does not already have are sent. The receiving package store must have the
sending package store's public key added to the public key list.

## OPTIONS

* -p, --package VALUE:
  Path to package.

## SEE ALSO

hermes-pkgstore(1), hermes-pkgstore-recv(1)
