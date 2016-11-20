## dotfiles

[![Travis CI](https://travis-ci.org/mdonkers/dotfiles.svg?branch=master)](https://travis-ci.org/mdonkers/dotfiles)

**To install:**

```console
$ make
```

This will create symlinks from this repo to your home folder.

**To customize:**

Save env vars, etc in a `.extra` file, that looks something like
this:

```bash
###
### Git credentials
###

GIT_AUTHOR_NAME="Your Name"
GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
git config --global user.name "$GIT_AUTHOR_NAME"
GIT_AUTHOR_EMAIL="email@you.com"
GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
git config --global user.email "$GIT_AUTHOR_EMAIL"
GH_USER="nickname"
git config --global github.user "$GH_USER"
```

#### Thx

Big thanks to Jessie Frazelle of which this repo is largely (or at least started as) a copy.
The original repo can be found here; [https://github.com/jfrazelle/dotfiles](https://github.com/jfrazelle/dotfiles).

Also many thanks to the great Arch Linux wiki pages which contain many valuable resources.

