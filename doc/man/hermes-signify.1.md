hermes-signify(1)
==================

## SYNOPSIS

A copy of the openbsd key cryptographic signing tool https://man.openbsd.org/signify used internally by hermes
for package signing.

```
signify -C [-q] [-p pubkey] [-t keytype] -x sigfile [file ...]
signify -G [-n] [-c comment] -p pubkey -s seckey
signify -S [-enz] [-x sigfile] -s seckey -m message
signify -V [-eqz] [-p pubkey] [-t keytype] [-x sigfile] -m message
```

## DESCRIPTION

The hermes package store uses public key cryptography to verify packages
copied from other users. Each hermes-package-store(7) has a keypair used
for copying packages, and a set of trusted public keys that it will accept
packages signed with.

The key and signature files created by signify have the same format.
The first line of the file is a free form text comment that may be edited, so long as it does not exceed a single line.
Signature comments will be generated based on the name of the secret key used for signing. This comment can then be used as a hint for the name of the public key when verifying. The second line of the file is the actual key or signature base64 encoded.

## OPTIONS

* -C:
    Verify a signed checksum list, and then verify the checksum for each file. If no files are specified, all of them are checked. sigfile should be the signed output of sha256(1).

* -G:
    Generate a new key pair. Keynames should follow the convention of keyname.pub and keyname.sec for the public and secret keys, respectively.

* -S:
    Sign the specified message file and create a signature.

* -V:
    Verify the message and signature match.

* -c comment:
    Specify the comment to be added during key generation.

* -e:
    When signing, embed the message after the signature. When verifying, extract the message from the signature. (This requires that the signature was created using -e and creates a new message file as output.)

* -m message:
    When signing, the file containing the message to sign. When verifying, the file containing the message to verify. When verifying with -e, the file to create.
* -n:
    When generating a key pair, do not ask for a passphrase. Otherwise, signify will prompt the user for a passphrase to protect the secret key. When signing with -z, store a zero time stamp in the gzip(1) header.

* -p pubkey:
    Public key produced by -G, and used by -V to check a signature.

* -q:
    Quiet mode. Suppress informational output.

* -s seckey:
    Secret (private) key produced by -G, and used by -S to sign a message.

* -t keytype:
    When deducing the correct key to check a signature, make sure the actual key matches `/etc/signify/*-keytype.pub`.

* -x sigfile:
    The signature file to create or verify. The default is message.sig.

* -z:
    Sign and verify gzip(1) archives, where the signing data is embedded in the gzip(1) header.

## EXIT STATUS

The signify utility exits 0 on success, and >0 if an error occurs. It may fail because of one of the following reasons:

- Some necessary files do not exist.
- Entered passphrase is incorrect.
- The message file was corrupted and its signature does not match.
- The message file is too large.

## SEE ALSO

hermes(1), hermes-pkgstore(1), hermes-package-store(1)
