  $ export TERM=dumb
  $ export RUST_LOG_STYLE=never

  $ git init -q real_repo 1> /dev/null
  $ cd real_repo

History without any workspace config. lib/ has a vendored dependency and BUCK files.

  $ mkdir -p lib/vendor/dep
  $ echo code > lib/code
  $ echo build > lib/BUCK
  $ echo dep > lib/vendor/dep/dep.h
  $ git add .
  $ git commit -m "add lib" 1> /dev/null

  $ echo more > lib/more
  $ git add .
  $ git commit -m "add more" 1> /dev/null

Move the dependency to the repo root.

  $ mkdir -p vendor
  $ git mv lib/vendor/dep vendor/dep
  $ echo build > vendor/dep/BUCK
  $ git add .
  $ git commit -m "move dep to the root" 1> /dev/null

A directory that must not end up in the view.

  $ mkdir secret
  $ echo secret > secret/file
  $ git add .
  $ git commit -m "add secret" 1> /dev/null

workspace.josh is ignored when josh.toml exists. It still shows up as a normal file.

  $ echo ":/secret" > lib/workspace.josh
  $ cat > lib/josh.toml <<EOF
  > exclude = ["**/BUCK"]
  >
  > [map]
  > "vendor/dep" = "vendor/dep"
  > EOF
  $ git add .
  $ git commit -m "add josh.toml" 1> /dev/null

Older history gets the config too.

  $ josh-filter :workspace=lib master --update refs/heads/filtered
  6d6dbe5a93d93fb30e8aeaa81888b329b1f6afb4
  $ git log --graph --pretty=%s refs/heads/filtered
  * add josh.toml
  * add more
  * add lib
  $ git ls-tree -r --name-only refs/heads/filtered
  code
  josh.toml
  more
  vendor/dep/dep.h
  workspace.josh
  $ git ls-tree -r --name-only refs/heads/filtered~2
  code
  vendor/dep/dep.h

A new commit fast-forwards.

  $ echo again > lib/again
  $ git add .
  $ git commit -m "add again" 1> /dev/null
  $ export PREVIOUS=$(git rev-parse refs/heads/filtered)
  $ josh-filter :workspace=lib master --update refs/heads/filtered
  dda2e1f9c26e6b00aae881e4baffbda537607749
  $ test "$(git rev-parse refs/heads/filtered~1)" = "$PREVIOUS"

Changing the config only affects commits from then on.

  $ sed -i 's/^exclude = .*/exclude = []/' lib/josh.toml
  $ git add .
  $ git commit -m "keep BUCK files" 1> /dev/null
  $ export PREVIOUS=$(git rev-parse refs/heads/filtered)
  $ josh-filter :workspace=lib master --update refs/heads/filtered
  4a05a7d22d435d3e4c19c6c7010f28c72124d40f
  $ test "$(git rev-parse refs/heads/filtered~1)" = "$PREVIOUS"
  $ git ls-tree -r --name-only refs/heads/filtered | grep BUCK
  BUCK
  vendor/dep/BUCK

An invalid config is an error.

  $ git checkout -q -b bad
  $ cat > lib/josh.toml <<EOF
  > [map]
  > "x" = "../secret"
  > EOF
  $ git commit -q -am "bad map"
  $ josh-filter :workspace=lib bad
  ERROR: josh.toml: map source `../secret` must be a relative path without `.` or `..`
  [1]

  $ echo "exclud = []" > lib/josh.toml
  $ git commit -q -am "unknown key"
  $ josh-filter :workspace=lib bad
  ERROR: invalid lib/josh.toml: TOML parse error at line 1, column 1
    |
  1 | exclud = []
    | ^^^^^^
  unknown field `exclud`, expected `map` or `exclude`
  
  [1]
