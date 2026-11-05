#!/usr/bin/env bats
#
# Guarda contra dependencias alucinadas por IA ("slopsquatting") nas extensoes.
#
# Nao existe lista publica canonica dos nomes "mais comuns" alucinados (apenas
# casos isolados como huggingface-cli); a defesa e ESTRUTURAL: todo modulo,
# comando e crate declarado precisa estar numa allowlist verificada por humano
# (tests/deps/*.txt). Nome novo quebra o teste ate alguem confirmar que existe.
# Com NPASS_TEST_NETWORK=1 tambem consulta crates.io e PyPI.
#
# Limites: py-commands so ve literais no 1o elemento da lista; comandos Bash so
# aparecem se sondados com `command -v`/`type -P`.

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	DEPS="$BATS_TEST_DIRNAME/deps"
	SCAN="$DEPS/scan.py"
	command -v python3 >/dev/null || skip "python3 ausente"
}

list_names() {
	grep -vE '^[[:space:]]*(#|$)' "$1" | sed -E 's/[[:space:]]*(#|\|).*$//; s/[[:space:]]+$//' | awk 'NF{print $1}'
}

not_in_list() { # $1 = allowlist; stdin = nomes; imprime os ausentes
	local n allowed
	allowed="$(list_names "$1")"
	while IFS= read -r n; do
		[[ -z $n ]] && continue
		grep -qxF -- "$n" <<<"$allowed" || printf '%s\n' "$n"
	done
}

@test "allowlists e denylist existem, sem duplicatas, e a denylist traz motivo" {
	local f dup
	for f in python-packages python-commands shell-commands cargo-crates denylist; do
		[ -s "$DEPS/$f.txt" ]
		dup="$(list_names "$DEPS/$f.txt" | sort | uniq -d)"
		[ -z "$dup" ] || { echo "duplicado em $f.txt: $dup" >&2; false; }
	done
	run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$DEPS/denylist.txt' | grep -vE '\\|[[:space:]]*[^[:space:]]'"
	[ -z "$output" ]
}

@test "o scanner enxerga imports, subprocess e which de um Python de amostra (o guarda nao pode apodrecer)" {
	local tmp="$BATS_TEST_TMPDIR/amostra"
	mkdir -p "$tmp/tests/deps" "$tmp/passkey"
	cp "$SCAN" "$tmp/tests/deps/scan.py"
	cat >"$tmp/ferramenta" <<'AMOSTRA'
#!/usr/bin/env python3
import os, requests_utils
from pacote_falso.sub import coisa
import subprocess, shutil
subprocess.run(["binario-falso", "-x"])
shutil.which("outro-falso")
AMOSTRA
	run python3 "$tmp/tests/deps/scan.py" py-imports
	[ "$output" = $'pacote_falso\nrequests_utils' ]
	run python3 "$tmp/tests/deps/scan.py" py-commands
	[ "$output" = $'binario-falso\noutro-falso' ]
}

@test "todo modulo Python nao-stdlib importado esta na allowlist (pega pacotes inventados)" {
	local missing
	missing="$(python3 "$SCAN" py-imports | not_in_list "$DEPS/python-packages.txt")"
	[ -z "$missing" ] || { printf 'modulo fora da allowlist: %s\n' $missing >&2; false; }
}

@test "todo binario chamado por subprocess/which nas extensoes Python esta na allowlist" {
	local missing
	missing="$(python3 "$SCAN" py-commands | not_in_list "$DEPS/python-commands.txt")"
	[ -z "$missing" ] || { printf 'comando fora da allowlist: %s\n' $missing >&2; false; }
}

@test "todo comando sondado por command -v nas extensoes Bash esta na allowlist" {
	local f missing
	missing="$(for f in "$ROOT"/npass-*; do
		[[ -f $f ]] || continue
		head -n1 "$f" | grep -q bash || continue
		grep -vE '^[[:space:]]*#' "$f" \
			| grep -oE '(command -v|type -P)[[:space:]]+[A-Za-z0-9_][A-Za-z0-9_.+-]*' | awk '{print $NF}'
	done | sort -u | not_in_list "$DEPS/shell-commands.txt")"
	[ -z "$missing" ] || { printf 'comando fora da allowlist: %s\n' $missing >&2; false; }
}

@test "todo crate direto de Cargo.toml esta na allowlist e os marcados 'pin' tem versao exata" {
	[ -f "$ROOT/passkey/Cargo.toml" ] || skip "sem passkey/Cargo.toml"
	local name ver missing="" unpinned=""
	while IFS=$'\t' read -r name ver; do
		grep -qxF -- "$name" <(list_names "$DEPS/cargo-crates.txt") || { missing+="$name "; continue; }
		if grep -vE '^[[:space:]]*#' "$DEPS/cargo-crates.txt" | awk -v n="$name" '$1==n && $2=="pin"{f=1} END{exit !f}'; then
			[[ $ver == =* ]] || unpinned+="$name($ver) "
		fi
	done < <(python3 "$SCAN" cargo-deps)
	[ -z "$missing" ] || { echo "crate fora da allowlist: $missing" >&2; false; }
	[ -z "$unpinned" ] || { echo "crate 'pin' sem versao exata (=x.y.z): $unpinned" >&2; false; }
}

@test "Cargo.lock: so crates.io com checksum, sem git/path/registry alternativo, e cobre as deps diretas" {
	[ -f "$ROOT/passkey/Cargo.lock" ] || skip "sem Cargo.lock"
	run python3 "$SCAN" lock-bad
	[ -z "$output" ] || { echo "$output" >&2; false; }
	run python3 "$SCAN" lock-missing
	[ -z "$output" ] || { echo "dep direta ausente do lock: $output" >&2; false; }
}

@test "nenhum nome da denylist aparece no projeto nem no Cargo.lock" {
	local name hits all=""
	while IFS= read -r name; do
		hits="$(grep -rInwiF \
			--exclude-dir=.git --exclude-dir=gnupg_test --exclude-dir=gnupg_atacante \
			--exclude-dir=dist --exclude-dir=target --exclude-dir=deps --exclude-dir=__pycache__ \
			--exclude=deps.bats \
			-e "$name" -- "$ROOT" 2>/dev/null || true)"
		[ -z "$hits" ] || all+="[$name]"$'\n'"$hits"$'\n'
	done < <(list_names "$DEPS/denylist.txt")
	[ -z "$all" ] || { printf '%s' "$all" >&2; false; }
}

@test "workflows usam so acoes de owners confiaveis e nunca refs flutuantes (@main/@master)" {
	local f bad=""
	shopt -s nullglob
	for f in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
		bad+="$(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$f" | grep -vE 'uses:[[:space:]]*actions/[A-Za-z0-9_.-]+@(v[0-9]+(\.[0-9]+){0,2}|[0-9a-f]{40})([[:space:]]|$)' || true)"
	done
	[ -z "$bad" ] || { printf 'uses fora da politica (actions/* @vN ou SHA):\n%s\n' "$bad" >&2; false; }
}

@test "[rede] todo crate do Cargo.lock existe, bate o checksum e nao esta yanked; modulos Python existem no PyPI" {
	[ "${NPASS_TEST_NETWORK:-0}" = 1 ] || skip "defina NPASS_TEST_NETWORK=1 para consultar crates.io e PyPI"
	run python3 "$SCAN" registry
	[ -z "$output" ] || { echo "$output" >&2; false; }
}
