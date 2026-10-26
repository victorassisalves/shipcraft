# R: an old config filename alone must refuse before project commands run.
rename_case() {
  local command="${CASE#r-legacy-config-}"
  EXPECT="legacy configuration filename migration"
  v1_start
  setup_init
  if [ "$command" = unstaged-hooks ]; then
    printf 'staged product change\n' > product.txt
    git add product.txt || fail "fixture: stage product change"
    git diff --cached --binary > "$CW/index.before"
    must_accept "hook accepts the staged product change" cmd shipcraft check
    must_accept "commit-msg accepts the staged product change" cmd shipcraft check --commit-msg .git/COMMIT_EDITMSG
    mv .shipcraft.toml .sc2.toml
    must_accept "hook ignores the unstaged config rename" cmd shipcraft check
    must_accept "commit-msg ignores the unstaged config rename" cmd shipcraft check --commit-msg .git/COMMIT_EDITMSG
    git diff --cached --binary > "$CW/index.after"
    chk "both hook routes preserve the pending commit" cmp -s "$CW/index.before" "$CW/index.after"
    must_accept "CI judges HEAD despite the unstaged rename" cmd shipcraft ci --base HEAD
    pass
    return
  fi
  cp .shipcraft.toml "$CW/config.before"
  mv .shipcraft.toml .sc2.toml
  if [ "$command" = coexists ]; then
    cp .sc2.toml .shipcraft.toml
    must_accept "the new filename takes precedence" cmd shipcraft init
  else
    case "$command" in
      check|commit-msg|ci)
        git add -A -- .shipcraft.toml .sc2.toml || fail "fixture: stage the legacy config rename"
        ;;
    esac
    case "$command" in
      ci)
        must_accept "fixture: publish the legacy filename" commit git -c core.hooksPath="$CW/no-hooks" commit -q -m 'test: legacy config filename'
        run_cmd shipcraft ci --base HEAD ;;
      commit-msg) run_cmd shipcraft check --commit-msg .git/COMMIT_EDITMSG ;;
      *) run_cmd shipcraft "$command" ;;
    esac
    chk "legacy filename refuses" eq "$RC" 1
    msg_check || fail "missing migration refusal: $MSGERR"
    chk "Next explains the filename migration" grep -F -q 'Next: rename .sc2.toml to .shipcraft.toml' "$OUT.last3"
    chk "no new configuration was created" test ! -e .shipcraft.toml
    chk "old configuration is unchanged" cmp -s .sc2.toml "$CW/config.before"
  fi
  pass
}
