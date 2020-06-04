# Hermes quick start

This quickstart is meant for confident users to quickly
get started using Hermes to install software.

Being familiar with the Janet programming language helps with writing packages,
but it is not necessary to use packages. 

People familiar with Nixos, or Guix may find some of the ideas familiar.

All that being said, if you are a confident computer user, this guide may be useful if
you are interested in diving into using Hermes.

## Installing Hermes

See the [installation guide](../installing.md).

## Initializing Hermes

Once hermes is installed and on your path you can initialize a package store:

```
$ export HERMES_STORE=/tmp/hermes-store
$ hermes init 
```

Let's see what you have just created:

```
/tmp/hermes-store/
├── etc
│   └── hermes
│       ├── cfg.jdn
│       ├── signing-key-7f9eea683ad4075532980857f3523dec.pub
│       ├── signing-key-7f9eea683ad4075532980857f3523dec.sec
│       ├── signing-key.pub -> ./signing-key-7f9eea683ad4075532980857f3523dec.pub
│       ├── signing-key.sec -> ./signing-key-7f9eea683ad4075532980857f3523dec.sec
│       └── trusted-pub-keys
├── hpkg
└── var
    └── hermes
        ├── hermes.db
        └── lock
            └── gc.lock

```

Hermes has created a configuration file - cfg.jdn, some security keys used for verifying packages, an sqlite database of installed packages, some lock files for coordinating
parallel package builds, and a folder - /hpkg for installing packages into. 

For a detailed reference of these files see the [package store manual entry](../man/hermes-package-store.7.md),

## Installing your first package

Now that hermes is installed and initialized, we can start building/installing packages.

First let's install the binary seed package (the root dependency of all packages.):
```
$ git clone https://github.com/andrewchambers/hpkgs
$ hermes build --expression seed --output ./seed-env ./hpkgs/seed.hpkg

building /tmp/hermes-store/hpkg/9fe12ef4bec689db93b9e8bdbd3b6d752dc619a8-seed.tar.gz...
fetching sha256:3d850f281e907d3b78599612ee1a17e63084b98947799a22a3e2a938db98e30a...
...
/tmp/hermes-store/hpkg/39c4105a12581e50027a505f3321b0670d937c32-seed
```

This created ./seed-env as a symlink into our package store, which is a package containing our 
package set bootstrap environment.

We can verify this:

```
$ readlink ./seed-env
/tmp/hermes-store/hpkg/39c4105a12581e50027a505f3321b0670d937c32-seed

$ ./seed-env/bin/ls ./seed-env/bin
'['         dir          link       od          split        vdir                           x86_64-linux-musl-readelf
 ar         dircolors    ln         paste       stat         wc                             x86_64-linux-musl-size
 awk        dirname      locate     patch       stdbuf       who                            x86_64-linux-musl-strings
....
```

### A note about funny package paths

Hermes packages are installed into a path based on its cryptographic hash. In practice this
simply means we can install many variations of the same package and not have to worry about them conflicting and breaking each other.

## Uninstalling packages

In the previous section we installed a package, to remove packages, we must run the package garbage collector.

```
$ rm ./seed-env
$ hermes gc
deleting /tmp/hermes-store/hpkg/9fe12ef4bec689db93b9e8bdbd3b6d752dc619a8-seed.tar.gz
deleting /tmp/hermes-store/hpkg/39c4105a12581e50027a505f3321b0670d937c32-seed
```

Packages that are not reachable by any links created by hermes will automatically be deleted.

## Building a package from source

The previous package was quite boring, it just downloaded it from the internet... Hermes is supposed to be about building
packages from source!

```
$ hermes build -j $(nproc) ./hpkgs/core.hpkg -e core-env
...
...build output whizzing past...
...
/tmp/hermes-store/hpkg/c7e0d1a92cbd5492a5468c74a2b65bd16b3af14e-core-env
```

Now ./result contains a more impressive package! This package contains references to other packages, 
hermes automatically tracks these dependencies for you.

```
$ tree ./result
./result
├── activate
└── bin
    ├── [ -> /tmp/hermes-store/hpkg/117a348b70fd002e5e885ed2ddf30724d2e84809-coreutils/bin/[
    ├── awk -> /tmp/hermes-store/hpkg/431dc40f0b66e6250fad2a5f962d246e7cda673c-awk/bin/gawk
    ├── basenc -> /tmp/hermes-store/hpkg/117a348b70fd002e5e885ed2ddf30724d2e84809-coreutils/bin/basenc
    ├── bunzip2 -> /tmp/hermes-store/hpkg/3ff2c672888768ec2a9b2d98b31da3357d6c4c43-bzip2/bin/bunzip2
...
```

We can clean up the intermediate artifacts we no longer care about...

```
$ hermes gc
deleting /tmp/hermes-store/hpkg/9ed275376722deeb1ecf68d94675b85a579fff12-xz-5.2.4.tar.gz
deleting /tmp/hermes-store/hpkg/ffae58192dcb3e087f1e07fad24c04ddc6b8965f-grep-3.3.tar.xz
deleting /tmp/hermes-store/hpkg/5432124392eb57fb610f0ad2c40286ce4ffb28e2-lzip-1.21.tar.gz
deleting /tmp/hermes-store/hpkg/c992b1918098b76771c3b572c705537482a4a786-dash-0.5.10.tar.gz
...
```

## Using your packages

For many packages, to use them, simply add their bin directory to your PATH. 
```
$ export PATH="($pwd)/core-env/bin:$PATH"
$ dash
```

## Regenerating the seed environment

It's pretty sad to have to trust the seed environment, luckily, rebuilding it yourself is simple.

```
$ hermes build -o seed ./hpkgs/seed.hpkg
$ hermes build -o seed-out ./hpkgs/seed-out.hpkg 
```

You can verify your binary seed has the same hash as the binary seed you originally downloaded. Note this generally only works
for multi user installs of hermes, as the package paths are consistent for all users.

```
$ sha256sum ./seed/seed.tar.gz ./seed-out/seed.tar.gz
```

When both hashes match, it means you have the ability to regenerate *all* of your hermes software from source. You have *total* control of your software stack.

## Writing your own packages

Hermes packages are closely related to the [janet programming language](https://janet-lang.org).

A package is simply a janet object with a builder function. Here is perhaps the simplest package:

```
$ hermes build -e '(pkg :name "empty-package" :builder (fn [] nil))'
/hpkg/63386eadb35d5aa88567bd851a32112bbc2228c6-empty-package
$ ls ./result/
$ cat ./result/.hpkg.jdn
{:hash "63386eadb35d5aa88567bd851a32112bbc2228c6" :scanned-refs @[] :name "empty-package"}
```

This creates a a package object using the hermes builtin `pkg` function.


Note, let's create a package with a file in it:
```
$ echo "hello" > hello.txt
$ hermes build -e '(local-file "./hello.txt")'
/hpkg/7f13ae53be79a917a67a11a2bc069c0fbd042212-hello.txt
$ cat ./result/hello.txt
hello
```

The example used the builtin `local-file` hermes function to create a package object, containing
our desired content.

Now, let's create a package with a file we have downloaded from the internet:

```
$ hermes build -e '
(fetch
    :url "https://raw.githubusercontent.com/andrewchambers/hermes/master/doc/quick-start/hello.c"
    :hash "sha256:606789023f0e1da5a251fb56a82b3017900aa1125a6d51bddbe063a189691ae7")'
/hpkg/933b4fe2786fb38cd1876de0aa0431e88afabcad-hello.c
```

This example used the builtin `fetch` hermes function to fetch content. Hermes requires external content to specifiy file hashes to ensure
builds are reproducible.

Now let's create more interesting packages:

```
$ hermes build -e '
(pkg
  :name "hello-package"
  :builder
  (fn []
    (def output-file
      (string (dyn :pkg-out) "/hello.txt"))
    (spit output-file "hello world!")))
'
/hpkg/caab6bdf2b3e2bf38cdf11ee82dd7924b90a779f-hello-package
$ cat ./result/hello.txt
hello world!
```

Packages must write their output to a designated output path, ```(dyn :pkg-out)``` fetches this value from the janet dynamically scoped variable named
by the janet keyword :pkg-out. The builder then writes this file using the 'spit' function, to spit data to disk.


Finally, let us put everything we tried together:

Create hello.hpkg
```
(use ./hpkgs/seed)

(def hello-src
  (fetch
      :url "https://raw.githubusercontent.com/andrewchambers/hermes/master/doc/quick-start/hello.c"
      :hash "sha256:606789023f0e1da5a251fb56a82b3017900aa1125a6d51bddbe063a189691ae7"))

(def hello
  (pkg
    :name "hello"
    :builder
    (fn []
      (os/setenv "PATH" (string (seed :path) "/bin"))
      (def src (first (sh/glob (string (hello-src :path) "/*.c"))))
      (def out (string (dyn :pkg-out) "/hello"))
      (sh/$ x86_64-linux-musl-gcc -static -o ,out src))))
```

Now we can build our package:

```
$ hermes build ./hello.hpkg -e hello
/hpkg/76013284e6ec167a99bdd58b945175fefc00d5d2-hello
$ ./result/hello
hello world!
```

Janet is a powerful programming language that lets us create abstractions.
With a little effort, we can create more powerful ways to define packages, for example, with some
Janet practice you might be able to create a way to define gnu packages like this:

```
(defgnu tar
  :version
    "tar-1.32"
  :src-hash
    "sha256:b59549594d91d84ee00c99cf2541a3330fed3a42c440503326dab767f2fbb96c")
```

as a shorthand for:

```
(def tar-src
  (fetch
    :url "https://raw.githubusercontent.com/andrewchambers/hermes/master/doc/quick-start/hello.c"
    :hash "sha256:606789023f0e1da5a251fb56a82b3017900aa1125a6d51bddbe063a189691ae7"))

(def tar
  (pkg
    :name "tar-1.32"
    :builder
    (fn []
      (unpack-src tar-src)
      ...
      (sh/$ ./configure ...)
      (sh/$ make install))))
```

How to define such package abstractions is beyond the scope of the quickstart, but just remember, you don't need to be a janet programmer to write
packages if someone else has defined suitable functions for you to use. But if you invest in learning some janet programming, 
not only the ability to define neater packages, but also a great general purpose language to use in your day to day programming.

## Multi user mode

Until now, you have been using a private package store that only your
user can access. Hermes also supports a shared global package store, that allows 
all users on the same system to share a package store securely.

Usage in multi user mode is the same, but packages are installed into /hpkg instead of your HERMES_STORE.

To enable multi user mode, unset HERMES_STORE and follow the instructions in [installation guide](../installing.md).

## Transparent remote builds

When building a package on a laptop, or other underpowered device, it is
useful to perform remote builds on a more powerful server. This can
easily be done with hermes, simply add the --build-host flag to your
build command.

```
$ hermes build ./hpkgs/core.hpkg -e seed-out --build-host ssh://your-server.com
```

The build will proceed exactly the same as a local build, but be performed on the
remote host, with the resulting package copied back locally.

It is important to note that builds referring to 'local-file packages still work without
change. The remote build transparently handles sending these files to the build host 
when they are needed.

## Transferring packages between computers

We can use ```hermes cp``` to transfer arbitrary packages (and their dependencies) between computers, provided hermes is installed
and has a package store at the same path. Hermes cp is efficient and only copies packages that do not exist on the remote server.


localhost to remote host:
```
$ hermes cp ./my-package ssh://my-server.com/home/me/my-package
```

remote host to local host:
```
$ hermes cp ssh://my-server.com/home/me/my-package ./my-package
```

between hosts:
```
$ hermes cp ssh://my-server1.com/package ssh://my-server2.com/package
```

## Atomic deployments with Hermes

Hermes cp can be used for atomic deployments:

```
$ cd my-application
$ git pull
$ hermes build -e my-application -o my-application ./our-hermes-definitions.hpkg
$ hermes cp ./my-application ssh://root@my-server.com/production \
    && ssh root@my-server.com restart-services \
    && ssh root@my-server.com hermes gc
```

If the network connection breaks, the existing package will not be changed. The update of the
``` production ``` symlink is only done atomically at the end. Simply try again to safely update your system.


## Uninstalling hermes

[see here](../uninstalling.md).
