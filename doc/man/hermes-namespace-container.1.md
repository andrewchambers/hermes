hermes-namespace-container(1) 
=============================

## SYNOPSIS

Run a command in a linux namespace jail.

`hermes-namespace-container [OPTIONS] -- COMMAND...`

## DESCRIPTION

Run a command in a namespace jail. When used in conjunction with hermes-builder(1) forms
the basis of the hermes build sandboxing mechanism.

The purpose of sandboxing builds is to help ensure a package is only
derived from its input build function and as little external state 
as possible.

Any signals received by the sandbox result in termination of all
processes within the sandbox.

## OPTIONS

* -n:
  Create a new network namespace, thus removing network access from the container.

## SEE ALSO

hermes(1)
