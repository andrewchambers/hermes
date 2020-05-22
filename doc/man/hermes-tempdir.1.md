hermes-tempdir(1)
==================

## SYNOPSIS

Create a tempdir and remove it on exit.

`hermes tempdir`

## DESCRIPTION

The `hermes-tempdir` command is an internal command used by other hermes commands to ensure temporary
directories are removed when higher level commands are aborted. This is especially useful
when the abort happens due to a network interruption during remote builds.

## SEE ALSO

hermes(1)
