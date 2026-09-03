fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios generate

```sh
[bundle exec] fastlane ios generate
```

Regenerate the demo project from Demo/project.yml

### ios package

```sh
[bundle exec] fastlane ios package
```

Build and test the package on the host — the fastest failure signal available

### ios imports

```sh
[bundle exec] fastlane ios imports
```

Check the layering rule. Nothing else enforces it: SwiftPM does not restrict imports.

### ios method_docs

```sh
[bundle exec] fastlane ios method_docs
```

Check that the method pages still describe symbols that exist

### ios demo

```sh
[bundle exec] fastlane ios demo
```

Build the demo for a simulator

### ios run_demo

```sh
[bundle exec] fastlane ios run_demo
```

Build the demo, install it on a booted simulator and launch it

### ios ci

```sh
[bundle exec] fastlane ios ci
```

Everything CI runs

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
