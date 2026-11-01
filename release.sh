#!/usr/bin/env bash
# Build and sign official NPASS extension artifacts on the maintainer's machine.
# The private release key must never be stored in this repository or CI.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

usage() {
	cat <<'EOF'
Uso:
  ./release.sh [--out DIR] [--target TRIPLE]

Assina com a mesma chave GPG usada pelo npass-tui. A chave é selecionada nesta ordem:
  1. NPASS_RELEASE_SIGNING_KEY (opcional, fingerprint ou ID)
  2. git config user.signingkey
  3. chave secreta padrão do GPG

A chave pública oficial versionada neste repositório é packaging/npass-release.asc.
Use NPASS_RELEASE_PUBLIC_KEY apenas para apontar explicitamente para uma chave substituta.

Compila npass-passkeyd, prepara extensões e helpers em staging isolado,
assina e verifica cada artefato e publica o diretório completo por rename.
O diretório --out é substituído integralmente; use um diretório dedicado.

Exemplo:
  ./release.sh
  ./release.sh --target x86_64-unknown-linux-gnu

Saída padrão: dist/<triple>/
EOF
}

OUT=""
TARGET=""
while (($#)); do
	case "$1" in
		--out) [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }; OUT="$2"; shift 2 ;;
		--target) [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }; TARGET="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
	esac
done

KEY="${NPASS_RELEASE_SIGNING_KEY:-}"
PUBKEY="${NPASS_RELEASE_PUBLIC_KEY:-$ROOT/packaging/npass-release.asc}"
for tool in gpg cargo rustc tar gzip sha256sum install; do
	command -v "$tool" >/dev/null 2>&1 || { echo "$tool não encontrado." >&2; exit 1; }
done

# Keep key selection consistent with npass-tui/release.sh.
if [[ -z "$KEY" ]] && command -v git >/dev/null 2>&1; then
	KEY="$(git config --get user.signingkey 2>/dev/null || true)"
fi
if [[ -z "$KEY" ]]; then
	KEY="$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1=="sec"{want=1;next} want && $1=="fpr"{print $10;exit}')"
fi
[[ -n "$KEY" ]] || { echo "Nenhuma chave secreta GPG encontrada. Configure git config user.signingkey ou NPASS_RELEASE_SIGNING_KEY." >&2; exit 1; }
if [[ -z ${GPG_TTY:-} ]] && tty_path="$(tty 2>/dev/null)"; then
	export GPG_TTY="$tty_path"
fi
[[ -s "$PUBKEY" && ! -L "$PUBKEY" ]] || { echo "Chave pública oficial não encontrada ou inválida: $PUBKEY (defina NPASS_RELEASE_PUBLIC_KEY)." >&2; exit 1; }

VERIFY_HOME="$(mktemp -d "${TMPDIR:-/tmp}/npass-release-key.XXXXXX")"
chmod 700 "$VERIFY_HOME"
cleanup_verify() {
	GNUPGHOME="$VERIFY_HOME" gpgconf --kill all >/dev/null 2>&1 || true
	rm -rf -- "$VERIFY_HOME"
}
trap cleanup_verify EXIT
GNUPGHOME="$VERIFY_HOME" gpg --batch --quiet --import "$PUBKEY"
PUB_COUNT="$(GNUPGHOME="$VERIFY_HOME" gpg --batch --with-colons --list-keys 2>/dev/null | grep -c '^pub:' || true)"
EXPECTED_FPR="$(GNUPGHOME="$VERIFY_HOME" gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
[[ "$PUB_COUNT" == 1 ]] || { echo "A chave pública oficial precisa conter exatamente uma chave primária." >&2; exit 1; }
SECRET_FPR="$(gpg --batch --with-colons --list-secret-keys "$KEY" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
[[ -n "$EXPECTED_FPR" && "$SECRET_FPR" == "$EXPECTED_FPR" ]] || {
	echo "A chave privada selecionada não corresponde à chave pública oficial ($EXPECTED_FPR)." >&2
	exit 1
}
KEY="$EXPECTED_FPR"

HOST="$(rustc -vV | sed -n 's/^host: //p')"
if [[ -z "$TARGET" ]]; then TARGET="$HOST"; fi
[[ "$TARGET" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Target inválido: $TARGET" >&2; exit 1; }

if [[ -z "$OUT" ]]; then OUT="$ROOT/dist/$TARGET"; fi
OUT_PARENT="$(dirname -- "$OUT")"
OUT_NAME="$(basename -- "$OUT")"
[[ "$OUT_NAME" != "." && "$OUT_NAME" != "/" ]] || { echo "Diretório de saída inválido: $OUT" >&2; exit 2; }
mkdir -p -- "$OUT_PARENT"
OUT_PARENT="$(cd -- "$OUT_PARENT" && pwd)"
OUT="$OUT_PARENT/$OUT_NAME"

WORK="$(mktemp -d "$OUT_PARENT/.npass-release.XXXXXX")"
PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/extensions" "$PAYLOAD/helpers"
cleanup_work() { rm -rf -- "$WORK"; }
trap 'cleanup_work; cleanup_verify' EXIT

sign_file() {
	local file="$1"
	gpg --batch --yes --no-tty --local-user "$KEY" --detach-sign --output "$file.sig" "$file"
	GNUPGHOME="$VERIFY_HOME" gpg --batch --no-auto-key-retrieve --verify "$file.sig" "$file" >/dev/null 2>&1 || {
		echo "Assinatura não verificável: $file" >&2
		return 1
	}
}

echo "Compilando npass-passkeyd para $TARGET..."
if [[ "$TARGET" == "$HOST" ]]; then
	cargo build --manifest-path passkey/Cargo.toml --release --locked
	BIN="$ROOT/passkey/target/release/npass-passkeyd"
else
	cargo build --manifest-path passkey/Cargo.toml --release --locked --target "$TARGET"
	BIN="$ROOT/passkey/target/$TARGET/release/npass-passkeyd"
fi
[[ -s "$BIN" && -x "$BIN" ]] || { echo "Cargo não produziu o daemon esperado: $BIN" >&2; exit 1; }

extension_count=0
for src in "$ROOT"/npass-*; do
	[[ -f "$src" && ! -L "$src" && "$src" != *.sig ]] || continue
	name="${src##*/}"
	install -m 755 -- "$src" "$PAYLOAD/extensions/$name"
	sign_file "$PAYLOAD/extensions/$name"
	((++extension_count))
done
(( extension_count > 0 )) || { echo "Nenhuma extensão npass-* encontrada." >&2; exit 1; }
[[ -s "$PAYLOAD/extensions/npass-passkey" ]] || { echo "Extensão npass-passkey ausente; não é possível vincular o daemon." >&2; exit 1; }

install -m 755 -- "$BIN" "$PAYLOAD/helpers/npass-passkeyd"
{
	printf '%s\n' 'npass-passkeyd-stamp-v1'
	printf 'proto %s\n' 1
	printf 'helper-sha256 %s\n' "$(sha256sum "$PAYLOAD/helpers/npass-passkeyd" | awk '{print $1}')"
	printf 'extension-sha256 %s\n' "$(sha256sum "$PAYLOAD/extensions/npass-passkey" | awk '{print $1}')"
} >"$PAYLOAD/helpers/npass-passkeyd.stamp"
chmod 644 "$PAYLOAD/helpers/npass-passkeyd.stamp"
sign_file "$PAYLOAD/helpers/npass-passkeyd"
sign_file "$PAYLOAD/helpers/npass-passkeyd.stamp"

BUNDLE="$PAYLOAD/npass-extensions-$TARGET.tar.gz"
tar --sort=name --mtime="@${SOURCE_DATE_EPOCH:-0}" --owner=0 --group=0 --numeric-owner -cf - -C "$PAYLOAD" extensions helpers | gzip -n >"$BUNDLE"
[[ -s "$BUNDLE" ]] || { echo "Pacote vazio." >&2; exit 1; }
sign_file "$BUNDLE"

# Publica o conjunto completo por rename no mesmo filesystem. Se o rename
# falhar, restaura a versão anterior em vez de deixar a saída parcialmente atualizada.
PREVIOUS="$WORK/previous"
if [[ -e "$OUT" || -L "$OUT" ]]; then mv -- "$OUT" "$PREVIOUS"; fi
if ! mv -- "$PAYLOAD" "$OUT"; then
	if [[ -e "$PREVIOUS" ]]; then mv -- "$PREVIOUS" "$OUT"; fi
	echo "Falha ao publicar; versão anterior restaurada." >&2
	exit 1
fi

printf 'Pacote assinado: %s/%s\n' "$OUT" "npass-extensions-$TARGET.tar.gz"
printf 'Extensões: %s\n' "$extension_count"
printf 'Target: %s\n' "$TARGET"
printf 'Chave: %s\n' "$KEY"
printf 'Publique os artefatos sem incluir qualquer chave privada.\n'
