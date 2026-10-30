# npass-extensions

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
cd ~/Projetos/npass-store                      # com este repositório ao lado: ~/Projetos/npass-extensions
                                               # (a pasta com o nome antigo, npass_extensions, também vale)
sudo ./install.sh                              # instala o npass e, num terminal, oferece as extensões
./install.sh --extensions-only                 # só as extensões
./install.sh --extensions-src=/caminho/aqui    # este checkout, em qualquer lugar
./install.sh --extensions-ref=v1.0             # sem cópia local: baixa a release v1.0
```

Sem uma cópia local, o instalador avisa e **pergunta** antes de baixar.

## Confiança e distribuição

Extensões oficiais são assinadas pelo mantenedor com a chave privada de release do NPASS,
mantida offline e nunca armazenada neste repositório. O instalador e o runtime do core validam
assinaturas destacadas `.sig` usando exclusivamente a chave pública oficial instalada em
`$PREFIX/share/npass/extension-signing-key.asc`. O keyring pessoal do usuário não participa
da decisão de confiança; não existe comando para assinar extensões nem variável para ativá-las.

O instalador só deve receber artefatos já assinados. Um checkout Git, mesmo de uma branch ou tag
oficial, não substitui a assinatura criptográfica do artefato. Revise os artefatos e a origem
antes de instalar, como convém a qualquer código que executa com acesso ao store de senhas.

Para preparar uma distribuição, execute em uma máquina de release offline, com o checkout
`npass-store` ao lado (para localizar a chave pública oficial):

```bash
NPASS_RELEASE_SIGNING_KEY=FINGERPRINT scripts/release-sign.sh
```

Se o checkout do core estiver em outro local, informe `NPASS_RELEASE_PUBLIC_KEY=/caminho/npass-release.asc`.
O script gera `dist/TRIPLE/npass-extensions-TRIPLE.tar.gz` e sua assinatura destacada.
Publique ambos como assets de uma GitHub Release com a mesma tag; o instalador procura esse nome
exato. Para cada target suportado, gere um pacote próprio. Nunca copie a chave privada para o
checkout, pacote ou CI.

## Estrutura

```text
npass-*            uma extensão por arquivo (o sufixo .bash é tirado na instalação)
passkey/           código-fonte do daemon FIDO2/CTAP2/UHID em Rust
docs/              arquitetura do passkey, requisitos do Windows
tests/             testes de integração (bats) contra o npass de verdade
```

Cada extensão começa com cabeçalhos `# npass-extension-desc:` e `# npass-extension-needs:`.
A extensão `npass-passkey` também declara o helper nativo em `# npass-extension-helper:`;
o daemon é um artefato de release separado, não compilado nem assinado pelo usuário durante
a instalação.

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
