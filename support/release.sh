set -eu

if test "$(git diff --stat)" != ""
then
  echo "unable to build a release from a dirty tree."
  exit 1
fi

if ! test -d  ./.git
then
  echo "run release script from project directory."
  exit 1
fi

set -x

# Set this so we don't get -dirty.
export HERMES_BUILD_VERISON="$(janet -e '(use ./src/version) (print version)')"
export HERMES_STATIC_BUILD=yes
sh ./support/dev-shell.sh -c "jpm load-lockfile lockfile.jdn && jpm build"
mkdir release
cp ./build/hermes.tar.gz ./release/hermes-$HERMES_BUILD_VERISON-linux-x64_64.tar.gz

