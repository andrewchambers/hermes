set -eux

hermes build -e dev-env -o dev-env -j $(nproc) ./support/dev-env.hpkg
unset JANET_MODPATH
export JANET_LIBPATH="$(realpath $(dirname $(realpath ./dev-env/bin/janet))/../lib)"
export ORIG_PATH=$PATH
. ./dev-env/activate
export JANET_LIBPATH="$(dirname $(which janet))/../lib"
export JANET_HEADERPATH="$(dirname $(which janet))/../include/janet"
export PATH=$PATH:$ORIG_PATH
export HERMES_STATIC_BUILD=yes
exec /bin/sh --norc --noprofile "$@"
