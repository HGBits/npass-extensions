# AGENTS.md - npass_extensions

## Escopo

Extensões opcionais executadas pelo sistema de extensões do `npass`. Este repositório (`npass_extensions`) é separado do core (`npass-store`): o instalador do core (`install.sh`) as oferece, uma a uma, e as assina com a chave do usuário.

As extensões possuem contrato próprio com o core. O core fornece contexto como `NPASS_STORE`, `NPASS_GPG`, `NPASS_LANG` e `NPASS_BIN`.

## Arquivos

### `npass-import`

Importação de dados de outros gerenciadores e layouts compatíveis.

Use para tarefas envolvendo:

- Bitwarden;
- KeePass/KeePassXC;
- Firefox;
- Chrome;
- LastPass;
- 1Password;
- Aegis;
- andOTP;
- CSV genérico;
- `pass`;
- `pass-secrets`;

Todo import grava **md1** (`render()` / `render_md1()`); o corpo dos stores `pass` passa por `pass_body_to_md1()` e por `verify_conversion()`, que reprova a conversão que perder ou duplicar uma linha. `parse_md1()` aqui e em `npass-audit` espelha `lib/14-entry.bash`: mudou o formato, mude os três.

Testes relacionados: `tests/import.bats`, `tests/import-pass.bats`, `tests/import-pass-secrets.bats`, `tests/import-convert.bats`.

### `npass-passkey`

Backend de passkeys (`Fido/.map`, `Fido/*.gpg`), verificação, `serve` do helper Rust (`passkey/`) e `seal`.

Teste: `tests/passkey.bats`. Daemon: `passkey/AGENTS.md`. Único `npass-*` que dispara `cargo` no `install.sh` (cabeçalho `npass-extension-cargo`).

### `npass-clip-x11.bash`

Clipboard X11 usando `xclip`.

Use para:

- seleção CLIPBOARD;
- expiração/limpeza;
- comportamento do comando `clip-x11`.

Não interpreta a entrada: chama `"${NPASS_BIN:-npass}" get [CAMPO] ID CAMINHO` e copia o que o core devolve (o formato md1 só é lido em `lib/14-entry.bash`).

Teste principal: `tests/clip-ext.bats`.

### `npass-wclip`

Clipboard Windows usando `wclip`.

Uso documentado inclui senha, campo específico e entrada inteira. O script obtém a entrada por `npass show` e resolve campos localmente. fileciteturn0file0L80-L104

Requisitos e detalhes específicos de Windows: `windows_Requisitos.md`.

## Cadeia de leitura

```text
extensão
  -> lib/11-extensions.bash
  -> teste correspondente
  -> documentação correspondente
```

Para importação:

```text
npass-import
  -> tests/import.bats
  -> tests/import-pass.bats
  -> tests/import-pass-secrets.bats
```

Não leia todas as extensões para alterar uma única extensão.

## Testes e o core

Os testes (`tests/`, bats) são de integração: rodam as extensões contra o `npass` do repositório `npass-store`, achado por `NPASS_CORE_DIR` (padrão `../npass-store`). `tests/helper.bash` reaproveita o helper do core e sobrescreve só o que depende do layout dele (`npass_test_build`, `npass_test_ext_src`, `npass_test_raw`). Os testes do instalador (`install-ext.bats`, `install-passkey.bats`) ficam no core, porque testam o `install.sh`.

## Regras

1. Mudou o formato md1 no core: mude `parse_md1()` em `npass-import` e `npass-audit`.
2. Mudou o nome ou a saída de um comando do core que uma extensão usa: é mudança de contrato; ajuste aqui e nos testes.
3. O caminho em `# npass-extension-cargo:` é relativo à raiz deste repositório; o instalador compila em `passkey/`, só se a extensão for escolhida.
