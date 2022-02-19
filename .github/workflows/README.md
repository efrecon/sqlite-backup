# GitHub Actions Workflows

## Workflows

### Accepted Changes

Changes brought to the `master` branch will build images at the GHCR only,
through the [publish](./publish.yml) workflow. In between
[releases](../../docs/RELEASE.md), accepted changes will generate Docker images
tagged with an "upcoming" semantic version, i.e. expressing how [far][merge]
from the latest release this merge is.

  [merge]: https://github.com/Mitigram/gh-action-versioning#merging-features

### Releasing

The [`release.yml`](./release.yml) supports the [release](../../docs/RELEASE.md)
process by automatically generating a GitHub release when properly formed tags
are made onto the `master` branch. Note that the implementation for the
extraction of the release notes is stringent when it comes to how the release
header should be formatted in the [`CHANGELOG.md`](../../CHANGELOG.md).

## Running Locally

It was possible to run and test workflows locally using [act], but this is not
possible as [act] does not have support for reusable workflows (yet?). Provided
[act] is installed, the following command, run from the root directory of this
project, would exercise these workflows. **DANGER** some of these workflows
actually publish Docker images to the registry, you might want to temporarily
switch off that behaviour while debugging.

```console
act \
  -b \
  -P self-hosted=ghcr.io/catthehacker/ubuntu:act-latest \
  -W . \
  -e ./.github/workflows/act-event.json
```

Running [act] through [dew] is possible if you do not want to install [act] in
your environment. Just replace `act` with `dew act` in the command above.

  [act]: https://github.com/nektos/act
  [dew]: https://github.com/efrecon/dew
