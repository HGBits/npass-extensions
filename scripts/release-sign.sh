#!/usr/bin/env bash
# Build and sign official NPASS extension artifacts on the maintainer's machine.
# The private release key must never be stored in this repository or CI.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
	cat <<'EOF'
Uso:
  NPASS_RELEASE_SIGNING_KEY=FINGERPRINT scripts/release-sign.sh [--out DIR] [--target TRIPLE]

A chave privada precisa estar disponível localmente no GnuPG. O script:
  - compila npass-passkeyd com Cargo --locked;
  - copia e assina cada arquivo npass-*;
  - gera um selo que vincula daemon, protocolo e extensão;
  - assina daemon e selo com a chave oficial.

Saída padrão: dist/<triple>/
EOF
}

OUT=""
TARGET=""
while (($#)); do
	case "$1" in
		--out) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; OUT="$2"; shift 2 ;;
		--target) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; TARGET="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
	esac
done

KEY="\${NPASS_RELEASE_SIGNING_KEY:-}"
[[ -n "$KEY" ]] || { echo "Defina NPASS_RELEASE_SIGNING_KEY com o fingerprint da chave oficial." >&2; exit 1; }
command -v gpg >/dev/null 2>&1 || { echo "gpg não encontrado." >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "cargo não encontrado." >&2; exit 1; }
command -v rustc >/dev/null 2>&1 || { echo "rustc não encontrado." >&2; exit 1; }

if [[ -z "$TARGET" ]]; then
	TARGET="$(rustc -vV | sed -n 's/^host: //p')"
fi
[[ "$TARGET" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Target inválido: $TARGET" >&2; exit 1; }

if [[ -z "$OUT" ]]; then OUT="$ROOT/dist/$TARGET"; fi
mkdir -p "$OUT/extensions" "$OUT/helpers"
OUT="$(cd "$OUT" && pwd)"

sign_file() {
	local file="$1"
	gpg --batch --yes --local-user "$KEY" --detach-sign --output "$file.sig" "$file"
}

echo "Compilando npass-passkeyd para $TARGET..."
if [[ "$TARGET" == "$(rustc -vV | sed -n 's/^host: //p')" ]]; then
	cargo build --manifest-path passkey/Cargo.toml --release --locked
	BIN="$ROOT/passkey/target/release/npass-passkeyd"
else
	cargo build --manifest-path passkey/Cargo.toml --release --locked --target "$TARGET"
	BIN="$ROOT/passkey/target/$TARGET/release/npass-passkeyd"
fi
[[ -s "$BIN" && -x "$BIN" ]] || { echo "Cargo não produziu o daemon esperado: $BIN" >&2; exit 1; }

for src in "$ROOT"/npass-*; do
	[[ -f "$src" && "$src" != *.sig ]] || continue
	name="\${src##*/}"
	cp -- "$src" "$OUT/extensions/$name"
	chmod 755 "$OUT/extensions/$name"
	sign_file "$OUT/extensions/$name"
done

cp -- "$BIN" "$OUT/helpers/npass-passkeyd"
chmod 755 "$OUT/helpers/npass-passkeyd"
{
	printf '%s\n' 'npass-passkeyd-stamp-v1'
	printf 'proto %s\n' 1
	printf 'helper-sha256 %s\n' "$(sha256sum "$OUT/helpers/npass-passkeyd" | awk '{print $1}')"
	printf 'extension-sha256 %s\n' "$(sha256sum "$OUT/extensions/npass-passkey" | awk '{print $1}')"
} >"$OUT/helpers/npass-passkeyd.stamp"
chmod 644 "$OUT/helpers/npass-passkeyd.stamp"
sign_file "$OUT/helpers/npass-passkeyd"
sign_file "$OUT/helpers/npass-passkeyd.stamp"

printf 'Artefatos assinados em: %s\n' "$OUT"
printf 'Target: %s\n' "$TARGET"
printf 'Chave: %s\n' "$KEY"
printf 'Publique os artefatos sem incluir qualquer chave privada.\n'
