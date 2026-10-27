# Helper dos testes do repositorio de extensoes (npass_extensions).
#
# Os testes sao de INTEGRACAO: rodam as extensoes contra o npass de verdade, que mora em
# outro repositorio (npass-store). O helper do core e reaproveitado (chaves GPG
# descartaveis, md1_doc, npass_test_install_ext...) e so o que depende do layout do core
# e sobrescrito aqui.
#
#   NPASS_CORE_DIR   checkout do npass-store (padrao: ../npass-store, ao lado deste repo)
#
# Uso, como no core: export GNUPGHOME="$BATS_TEST_DIRNAME/gnupg_test"; load helper

NPASS_CORE_DIR="${NPASS_CORE_DIR:-$(cd "$BATS_TEST_DIRNAME/../../npass-store" 2>/dev/null && pwd)}"
if [[ -z "$NPASS_CORE_DIR" || ! -f "$NPASS_CORE_DIR/tests/helper.bash" ]]; then
	echo "npass-store nao encontrado: defina NPASS_CORE_DIR=/caminho/do/npass-store" >&2
	return 1
fi
export NPASS_CORE_DIR
# shellcheck source=/dev/null
source "$NPASS_CORE_DIR/tests/helper.bash"

# Garante o bin/npass do CORE (construido a partir de lib/*.bash dele).
npass_test_build() {
	local root="$NPASS_CORE_DIR" bin="$NPASS_CORE_DIR/bin/npass" stale=0 f
	if [[ ! -x "$bin" ]]; then
		stale=1
	else
		for f in "$root"/lib/*.bash "$root/build.sh"; do
			[[ "$f" -nt "$bin" ]] && { stale=1; break; }
		done
	fi
	((stale)) || return 0
	(
		flock 8
		cd "$root" && bash build.sh >/dev/null 2>&1
	) 8>"$BATS_TEST_DIRNAME/.keys.lock"
	[[ -x "$bin" ]] || { echo "falha ao construir o bin/npass do core (rode ./build.sh em $root)" >&2; return 1; }
}

# Copia DESTE repositorio (e nao do core) para $BATS_TEST_TMPDIR/extsrc.
npass_test_ext_src() {
	local root="$BATS_TEST_DIRNAME/.." dst="$BATS_TEST_TMPDIR/extsrc" n
	mkdir -p "$dst"
	if (($#)); then
		for n in "$@"; do cp -a -- "$root/$n" "$dst/" || return 1; done
	else
		cp -a -- "$root"/npass-* "$dst/" || return 1
	fi
	if [[ -d "$root/passkey" && ! -e "$dst/passkey" ]]; then
		cp -a -- "$root/passkey" "$dst/passkey" && rm -rf "$dst/passkey/target"
	fi
	export NPASS_EXTENSIONS_SRC="$dst"
}

npass_test_raw() {
	NPASS_SRC="$NPASS_CORE_DIR/bin/npass" bash -c '
		source <(sed "\$d" "$NPASS_SRC")
		npass_tmp_init
		dir="$(npass_identity_dir "$1")" && npass_blob_write "$dir" "$2" "$3"' _ "$@"
}
