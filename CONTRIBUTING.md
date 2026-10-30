# Contributing

## AI-assisted development

The Kalinka app is developed **predominantly with AI assistance**. Most of the code in this repository has been produced with AI assistance, working from maintainer-defined requirements. Product and design decisions, technical direction, review, testing and acceptance of changes remain the responsibility of the maintainer.

AI use is disclosed at the repository level rather than on individual commits, so commit messages and pull requests carry no co-authorship trailers or generated-with footers.

Changes are reviewed and tested to the same standard however they were produced.

If AI assistance played a significant part in a pull request you send, a note in the description is welcome — it helps direct review.

## Which pull requests are taken

Issues are welcome, on the [issue forms](https://github.com/Kalinka-Player/KalinkaAI/issues/new/choose). Pull requests are taken only for an open issue labelled [`help wanted`](https://github.com/Kalinka-Player/KalinkaAI/labels/help%20wanted). That label marks what needs someone else's hands, usually hardware the maintainer doesn't have, such as an iPhone, iPad or Mac. Everything else is fixed by Kalinka Bot, which works through the same issue list, so a pull request for it would duplicate work already planned.

If the issue you want to fix isn't labelled `help wanted`, or there is no issue yet, open one or comment on it asking for the label. Once it has it, send the pull request with `Fixes #<number>` in its description. A pull request that doesn't fix a `help wanted` issue is closed automatically.

The description must show the change was tested on the device the issue is about: which device, OS and version it ran on, what you checked, and the evidence. That is a screenshot or screen recording for a change to something you see, and logs or terminal output otherwise.

## Sending a change

Use Flutter **3.47.6** (Dart **3.13**) to match CI, and the checked-in Gradle wrapper for Android builds.

Fork the repository, create a feature branch, and open a pull request describing what changed and why. Run `flutter analyze` and `flutter test` for the area you touched; note that the repository is not `dart format` clean as a whole, so format only the code you actually changed rather than reformatting whole files.

Some cross-cutting changes — anything touching generated models or events — need `build_runner` re-run, and may also require a matching change in the backend repository ([KalinkaPlayer](https://github.com/Kalinka-Player/KalinkaPlayer)). Mention it in the pull request when that is the case.

## CI and merging

The Tests workflow runs `flutter analyze` and the full `flutter test` suite on each pull request's test merge with its base branch, on merge-queue commits, and on every push to `main`. Keep the checkout on the event's commit, not just the PR head: independently passing changes can fail when combined. Only superseded PR runs are cancelled; each push to `main` keeps its own run.

The `main` ruleset must require **Analyze** and **Unit and widget tests**, with **Require branches to be up to date before merging** enabled. After another PR merges, update the next branch and wait for fresh checks before merging it. Old green checks cannot establish that it works with the new base. If using a merge queue, the workflow's `merge_group` trigger runs the same checks on the queued combination. Do not bypass these checks for routine merges.

## Licensing

Source code is Apache License 2.0. Visual assets (icons, logos, images) are **not** open-source and are covered by a separate private licence — see `LICENSE-ASSETS`. Contributions must not add third-party assets without checking their licence first.
