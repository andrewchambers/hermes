# Compared to Nix and Guix

## Philisophical differences

- Hermes has a focus on simplicy and minimalism.
  As an example, hermes provides a fraction of the commands or options
  you need to learn compared to either Nix or Guix.

- Hermes has a focus on allowing you to run everything yourself
  without any need for central infrastructure. 
  Nix for example, comes preconfigured to fetch software from the hydra build
  cache centrally run by the project. Hermes does not place any emphasis
  on a single blessed package tree. Anyone can make their own package tree
  and hermes does not come configured with one.

## Practical differences

- They are based on a different programming languages, Nix uses a custom
  lazy functional language, Guix uses scheme, and hermes uses
  Janet.

- Arguably a simpler to learn package model. Nix packages are lazy thunks and
  you must program in a lazy functional language.
  Guix packages make use of a Scheme DSL, 'strata' of code, G-expressions, and 
  a store monad. Hermes packages are just janet functions and when
  a build gets scheduled, it gets called. All three accomplish more or
  less the same result.

- Both Nix and Guix rely on a build daemon to mediate package
  builds, Hermes uses a setuid binary.

- Hermes has better support for installing software directly from things
  like git repositories hosted online.

- The first package repository for Hermes is based on musl libc, both Nix and Guix
  package sets are heavily based around glibc.
