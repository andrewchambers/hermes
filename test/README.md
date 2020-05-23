# Test suite for hermes

When adding tests try to keep a few things in mind:

- The tests run against the hermes on your PATH and the current $HERMES_STORE.
- Don't run the test suite unless you are prepared for 'hermes gc'
- It should be easy to manually run a single test by just launching that file.
- Avoid depending on the network for tests.
- We are testing hermes here, not a particular package repository.