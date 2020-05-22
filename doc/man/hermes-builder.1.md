hermes-builder(1)
==================

## SYNOPSIS

Run a marshalled hermes thunk.

`hermes-builder [options]`

## DESCRIPTION

The `hermes-builder` command is an internal command used to launch a hermes build in a new process.
The `--thunk` argument is simply a marshalled janet/hermes function that will be immediately called
after unmarshalling.

## OPTIONS

* -t, --thunk:
  A marshaled janet/hermes function to call after unmarshalling.
 

## SEE ALSO

hermes(1), hermes-pkgstore(1)
