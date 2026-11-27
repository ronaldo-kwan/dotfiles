# Security

These dotfiles set up a computer with `sudo`: they add app sources and signing keys, install packages and change system settings. A mistake here could reach everyone who runs the install command, so please report one privately rather than in a public issue.

## Reporting a problem

Use **[Report a vulnerability](https://github.com/ronaldo-kwan/dotfiles/security/advisories/new)** (the repo's **Security** tab). Only you and the repo's owner can see the report. Please say what's wrong, which file it's in, and how it could be used.

For example:

- a download, app source or signing key that could be swapped for someone else's
- a script that could run something it shouldn't, or with more rights than it needs
- the website's install command doing something other than what it shows
- a password, token or key committed to the repo

## What's covered

`main` and the [latest release](https://github.com/ronaldo-kwan/dotfiles/releases/latest). Fixes go to `main`, and to a new release when the problem affects setting up from one.

This is a personal project, kept up in spare time, so there's no promised response time. A real problem gets fixed first, and you're welcome to be credited in the advisory.

## Disclosure

Please keep the details of a vulnerability private until a fix is out, or for 90 days after your report, whichever comes first, so people who ran the install command can update before it's public. The fix is then published as a GitHub security advisory for this repo, with what was affected and what to do.

## Problems in the apps themselves

A problem in Chrome, VS Code, Steam or another app this setup installs belongs with that app's maker; these dotfiles only install it from the maker's own source.
