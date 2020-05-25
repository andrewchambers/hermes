hermes-pkgstore-recv(1)
========================

## SYNOPSIS

Receive a package closure sent over stdin/stdout with the send/recv protocol.

`hermes-pkgstore recv [option] ...`

## DESCRIPTION

`hermes-pkgstore recv`receives a package and its dependencies (also referred to as a package closure)
from an instance of `hermes-pkgstore recv`. To use this command you must arrange the stdout and stdin
of the send end to be connected to the stdin and stdout of the recv end.

The receiving package store must have the sending package store's public key added to the public key list
as a package store can only receive signed packaged.

It is safe to abort and retry a package send at any time

## OPTIONS

* -o, --output VALUE:
  Path to where package output link will be created.

* -s, --store VALUE=:
  Package store to receive the closure.

## SEE ALSO

hermes-pkgstore(1), hermes-pkgstore-send(1)
