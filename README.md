# npass_extensions

Extensões opcionais do [npass](https://github.com/HGBits/npass-store), o gerenciador de senhas
para Linux/Wayland com GPG.

| Extensão | Faz |
|---|---|
| `npass-audit` | audita senhas por vazamentos, força e reutilização |
| `npass-import` | importa de outros gerenciadores (Bitwarden, KeePassXC, Firefox, Aegis, ...) e de stores `pass`/`pass-secrets` para md1 |
| `npass-passkey` | passkeys (WebAuthn/FIDO2) no desktop Linux, guardadas só no npass (daemon em Rust, `passkey/`) |
| `npass-clip-x11.bash` | `clip` para sessões X11 (xclip) |
| `npass-wclip.bash` | `clip` para Windows |

## Instalar

Pelo instalador do npass, que oferece cada extensão com uma descrição curta e só instala o que
você aceitar:

```bash
cd ~/Projetos/npass-store                      # com este repositório ao lado: ~/Projetos/npass_extensions
sudo ./install.sh                              # instala o npass e, num terminal, oferece as extensões
./install.sh --extensions-only                 # só as extensões
./install.sh --extensions-src=/caminho/aqui    # este checkout, em qualquer lugar
./install.sh --extensions-ref=v1.0             # sem cópia local: baixa este ref (tag ou branch)
```

Sem uma cópia local, o instalador avisa e **pergunta** antes de baixar.

## Por que a confiança é sua

Extensões rodam **como programas seus, com acesso aos seus segredos**. Por isso só funcionam
depois de assinadas **por você** (`npass extension sign`) e com `NPASS_ENABLE_EXTENSIONS=1`.
O instalador assina com a sua chave o que você aceitou: **o que está neste repositório no
momento em que você aceita é o que você passa a confiar.** Leia o diff antes, prefira um `ref`
fixo (tag) e confira o commit que o instalador mostra (inclusive se ele é assinado).

## Estrutura

```text
npass-*            uma extensão por arquivo (o sufixo .bash é tirado na instalação)
passkey/           o daemon FIDO2/CTAP2/UHID em Rust, compilado só se você escolher npass-passkey
docs/              arquitetura do passkey, requisitos do Windows
tests/             testes de integração (bats) contra o npass de verdade
```

Cada extensão começa com cabeçalhos `# npass-extension-desc:`, `# npass-extension-needs:` e,
para a que tem helper nativo, `# npass-extension-cargo: CAMINHO/Cargo.toml NOME` (o caminho é
relativo à raiz deste repositório).

## Testes

Os testes rodam as extensões contra o npass, que está em outro repositório:

```bash
git clone https://github.com/HGBits/npass-store ../npass-store    # se ainda não estiver ao lado
NPASS_CORE_DIR=../npass-store bats tests/
```

Precisam de `bats`, `gpg`, `python3`; os do daemon (`passkey`) precisam de `cargo` e são pulados
sem ele.

## Contrato com o core

As extensões recebem do npass `NPASS_STORE`, `NPASS_GPG`, `NPASS_LANG` e `NPASS_BIN`, e pedem
dados ao core por comandos (`npass get`, `npass ls --flat`, ...). O formato md1 de uma entrada é
interpretado pelo core (`lib/14-entry.bash`); `parse_md1()` em `npass-import` e `npass-audit`
espelha esse parser: **se o formato mudar no core, mude aqui também.** Mudança de comando do
core que as extensões usam (por exemplo o nome `ls`) é mudança de contrato.

Licença: veja `LICENSE`.
