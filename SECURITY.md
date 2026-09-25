# Security

## Supported versions

Only the latest release gets fixes. Please update before reporting.

## Reporting a vulnerability

Please don't open a public issue for security problems. Report them privately
through GitHub instead: open the repository's **Security** tab and click
**Report a vulnerability**.

Include the macOS version, the hidnr version, and the steps to reproduce.
I'll reply within a week and credit you in the release notes if you'd like.

## What hidnr has access to

So you know what's in scope:

- **Accessibility.** On macOS 27, hidnr uses Accessibility to read where each
  menu bar icon sits. It only reads positions; it doesn't read window contents
  or type anything.
- **No sandbox.** The app isn't sandboxed, because macOS 27 blocks the
  Accessibility reads it needs from inside the sandbox.
- **A private macOS framework.** Hiding on macOS 27 goes through a private
  menu bar allow-list. If that API is missing or fails, hidnr shows everything.
- **No network.** hidnr doesn't make network requests or collect any data.

Releases are signed with a Developer ID and notarized by Apple. Only install
builds from this repository's releases page or its Homebrew tap.
