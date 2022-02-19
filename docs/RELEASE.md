# Releasing

## Semantic Versioning

This project follows [semver] (semantic versioning). Release versions should
look like `MAJOR.MINOR.PATCH`. Increment the:

+ `MAJOR` version when you make incompatible API changes,
+ `MINOR` version when you add functionality in a backwards compatible manner,
  and
+ `PATCH` version when you make backwards compatible bug fixes.

  [semver]: https://semver.org/

## Release Process

To make a release:

1. Decide upon (semantic) version that matches the [rules](#semantic-versioning)
   from above.
2. Add a section to the [`CHANGELOG.md`](../CHANGELOG.md), second-level of
   heading with the same version as above, but a leading letter `v`, e.g.
   `## v0.2.3`. Latest release should be at the top of the file. There **MUST**
   be exactly one space between the `##` and the name of the release, e.g.
   `v0.2.3`, in the markdown.
3. Create a git tag with the version as its name on the `main` branch.
4. Push the tag, e.g. `git push --tags`.

The release workflow should automatically generate a GitHub release with this
information.

Note: Authoring the [`CHANGELOG.md`](../CHANGELOG.md) can be a collaborative
process. Every change that is deemed worthy to mention by collaborators can
generate an entry in the file. Just before a release is made, the list of these
entries should be curated, and perhaps the version number (backwards
compatibility or not).
