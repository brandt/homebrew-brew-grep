Homebrew Grep
=============

Search Homebrew formulae code.

## Installation ##

```
brew tap brandt/brew-grep
```

## Usage

Search all formulae for "foobar":

```
$ brew grep "foobar"
```

If `ack` is available, it will be used.  Otherwise, `grep` is used.
