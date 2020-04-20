set -eux

hermes build -m ./support/dev-env.hpkg -e dev-env -o dev-env -j $(nproc)
export JANET_PATH="$(pwd)/janet_modules"
export JANET_LIBPATH="$(realpath $(dirname $(realpath ./dev-env/bin/janet))/../lib)"
export PATH="$(pwd)/dev-env/bin:$PATH"
exec bash --norc --noprofile