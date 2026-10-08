# Contributing

## AI-assisted development

The Kalinka app is developed **predominantly with AI assistance**. Most of the code in this repository has been produced with AI assistance, working from maintainer-defined requirements. Product and design decisions, technical direction, review, testing and acceptance of changes remain the responsibility of the maintainer.

AI use is disclosed at the repository level rather than on individual commits, so commit messages and pull requests carry no co-authorship trailers or generated-with footers.

Changes are reviewed and tested to the same standard however they were produced.

If AI assistance played a significant part in a pull request you send, a note in the description is welcome — it helps direct review.

## Sending a change

Use Flutter **3.47.6** (Dart **3.13**) to match the test and release workflows. The dependency constraints require at least these versions; see the [dependency upgrade audit](docs/dependency-upgrade-audit.md) for the remaining upstream constraints.

Fork the repository, create a feature branch, and open a pull request describing what changed and why. Run `flutter analyze` and `flutter test` for the area you touched; note that the repository is not `dart format` clean as a whole, so format only the code you actually changed rather than reformatting whole files.

Some cross-cutting changes — anything touching generated models or events — need `build_runner` re-run, and may also require a matching change in the backend repository ([KalinkaPlayer](https://github.com/madenvel/KalinkaPlayer)). Mention it in the pull request when that is the case.

## Licensing

Source code is Apache License 2.0. Visual assets (icons, logos, images) are **not** open-source and are covered by a separate private licence — see `LICENSE-ASSETS`. Contributions must not add third-party assets without checking their licence first.
