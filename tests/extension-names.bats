#!/usr/bin/env bats

@test "artefatos oficiais usam exatamente npass-NOME com NOME lógico lowercase" {
  declare -A seen=()
  local file base logical count=0
  for file in "$BATS_TEST_DIRNAME"/../npass-*; do
    [ -f "$file" ] || continue
    base="${file##*/}"
    base="${base%.bash}"
    [[ "$base" =~ ^npass-[a-z0-9][a-z0-9-]*$ ]]
    logical="${base#npass-}"
    [[ "$logical" != npass-* ]]
    [ -z "${seen[$logical]:-}" ]
    seen[$logical]=1
    count=$((count + 1))
  done
  [ "$count" -ge 5 ]
}

@test "documentação e mensagens de uso apresentam o namespace extension" {
  grep -Fq 'npass extension audit ID' "$BATS_TEST_DIRNAME/../npass-audit"
  grep -Fq 'npass extension clip-x11' "$BATS_TEST_DIRNAME/../npass-clip-x11.bash"
  grep -Fq 'npass extension import' "$BATS_TEST_DIRNAME/../npass-import"
  grep -Fq 'npass extension passkey' "$BATS_TEST_DIRNAME/../npass-passkey"
  grep -Fq 'npass extension wclip' "$BATS_TEST_DIRNAME/../npass-wclip.bash"
}

@test "release help documents the default GPG key and canonical entrypoint" {
  run bash "$BATS_TEST_DIRNAME/../release.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"./release.sh [--out DIR] [--target TRIPLE]"* ]]
  [[ "$output" == *"git config user.signingkey"* ]]
  [[ "$output" != *"scripts/release-sign.sh [--out DIR]"* ]]
  [ ! -e "$BATS_TEST_DIRNAME/../scripts/release-sign.sh" ]
}
