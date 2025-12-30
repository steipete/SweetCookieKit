# Releasing SweetCookieKit

## Checklist

- Update `CHANGELOG.md` with the release date and notes.
- Ensure tests pass: `swift test`.
- Create a semver tag: `git tag -a <version> -m "<version>"`.
- Push commits and tags: `git push` and `git push --tags`.
- Create a GitHub release (source archives auto-generated).

## GitHub Release

- Use `gh release create <version> --title "<version>" --notes "<notes>"`.
- Keep release notes short and point to `CHANGELOG.md` for details.

## Swift Package Index

- Make sure the repo is public, `Package.swift` is at the root, and the tag exists.
- Submit the package URL (`https://github.com/steipete/SweetCookieKit.git`) in SPI.
