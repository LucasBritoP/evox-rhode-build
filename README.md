# Evolution X 15 para moto g52 (rhode) com SukiSU-Nova + SUSFS

Script de build da **Evolution X 10.x (branch `vic`, Android 15)** para o moto g52 (`rhode`), com:

- **SukiSU-Nova** (branch `builtin`, commit fixado) embutido no kernel 4.19;
- **SUSFS v2.4.0** adaptado ao `kernel_motorola_sm6225` da Evo;
- um **pacote de RAM para a variante de 4 GB**;
- a correção de um erro de sepolicy que hoje impede a build do rhode.

As árvores usadas são as oficiais da Evo (`Evolution-X-Devices`, mantenedor Deivid21). A última build oficial do rhode no A15 saiu em 17/09/2025.

> **Status:** testado e **funcionando** no moto g52 (ROM + SukiSU-Nova + SUSFS) desde 21/11/2026. Projeto **mantido ativamente**. Fico no **Android 15** de propósito: do Android 16 em diante o aparelho fica instável com os 4 GB de RAM — travamentos e reinícios do nada. Use por sua conta e risco e tenha o `boot.img` anterior à mão.

## Download

Imagens prontas (flash completo) para o `rhode`: **(link do Google Drive em breve)**

O pacote traz o **zip de flash completo** (ROM + kernel SukiSU-Nova + SUSFS embutido) e os `.img` da primeira instalação (`boot`, `dtbo`, `vendor_boot`, `vbmeta`, `vbmeta_system`), com `SHA256SUMS`. Instruções em [Instalação](#instalação).

Quem quiser compilar do zero continua podendo — veja [Uso](#uso) abaixo.

## Uso

Em uma máquina Ubuntu 22.04 com ~450 GB livres e 32 GB de RAM ou mais (64 GB é o recomendado), dentro do `tmux`:

```bash
git clone https://github.com/LucasBritoP/evox-rhode-build && cd evox-rhode-build
bash build-evo-rhode.sh 2>&1 | tee build.log
```

O script instala as dependências, faz o `repo sync` e aplica os patches de `patches/` uma vez só (pula os que já estiverem aplicados e aborta se algum não aplicar limpo). Ele compila o `boot.img` primeiro, para conferir o SukiSU/SUSFS logo no começo, e depois a ROM inteira.

O resultado fica em `~/evo/release/`: o zip de flash completo (`EvolutionX-*.zip`, com o kernel SukiSU + SUSFS dentro), os `.img` da primeira instalação e o `SHA256SUMS`.

Variáveis opcionais: `SRC`, `JOBS`, `SUKISU_REF`, `PATCH_DIR` e `SKIP_SYNC=1` (para rodar de novo só a build).

## Patches

| Arquivo | Repo | O que faz |
|---|---|---|
| `susfs-v2.4.0-rhode-4.19.patch` | `kernel/motorola/sm6225` | SUSFS v2.4.0 com os hooks inline do SukiSU (veja abaixo) |
| `sukisu-4.19.patch` | `kernel/motorola/sm6225/KernelSU` | Faz o SukiSU-Nova `builtin` (4bec532d) compilar no 4.19 (veja abaixo) |
| `motcamera-common-sepolicy.patch` | `vendor/motorola/MotCamera-common` | Esvazia dois `property_contexts` duplicados |
| `rhode-ram.patch` | `device/motorola/rhode` | `TARGET_ENABLE_BLUR := false` e `TARGET_SUPPORTS_QUICK_TAP := false` |
| `sm6225-common-ram.patch` | `device/motorola/sm6225-common` | `dalvik.vm.heapmaxfree` de 24m para 16m (4 GB) |

### Sepolicy da câmera (`MotCamera-common`)

O branch `android-15` de `gitlab.com/Deivid21/proprietary_vendor_motorola_MotCamera-common` foi reescrito em 07/06/2026. Nele, `sepolicy/private/property_contexts` e `sepolicy/system_ext/property_contexts` declaram as mesmas propriedades duas vezes no próprio arquivo, e essas entradas também já existem em `hardware/motorola/sepolicy/qti/private` (movidas para lá em 06/06/2026) e em `device/qcom/sepolicy`. A build para em:

```
host_init_verifier: Unable to serialize property contexts: Duplicate exact match detected for 'camera.mot.is.coming.cts'
```

O patch esvazia os **dois** arquivos. Os dois são necessários porque o `common.mk` escolhe o diretório por `TARGET_BOARD_PLATFORM`, e essa variável é definida no BoardConfig, que é lido depois dos product makefiles. Na prática, o branch `else` (`system_ext`) sempre vence. Além disso, os arquivos usam o tipo `moto_camera_config_prop`, que só existe na política de vendor.

### SUSFS no kernel 4.19

A base é o `susfs_patch_to_4.19.patch` e o `susfs_inline_hook_patches.sh` do [NonGKI_Kernel_Build_2nd](https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd), adaptados a este kernel (que tem backports de `fs_context` e `mmap_lock`). Correções em relação à base:

- o hook pós-execve (`ksu_handle_post_execveat_sucompat`) foi movido para o caminho de sucesso, porque no 4.19 o sucesso retorna antes de `out_free`;
- `ksu_su_compat_enabled` é declarado como `bool`, que é como o SukiSU-Nova o define, e não como static key (o tipo errado corromperia memória no `jump_label_init`);
- `ksu_handle_sys_read` passou a receber os 3 argumentos da definição;
- o caminho do `ksud` (`second_stage` e primeiro zygote) não depende mais do `su_compat`;
- `clone_mnt` não herda o bit `KSU_UNSHARED`, o que evita vazar IDs de mount (bug do SUSFS upstream);
- `kfree(scontext)` no spoof do log AVC, que corrige um vazamento de memória (bug do SUSFS upstream).

### SukiSU-Nova `builtin` no kernel 4.19

O commit `4bec532d` não compila em kernels anteriores ao 5.10:

- `kernel_includes.h` inclui `<linux/static_call.h>` sem guarda de versão (o header só existe a partir do 5.10, e nada no código usa `static_call`);
- `extension/kpm/kpm.c` chama `access_ok()` com 2 argumentos em vez do wrapper `ksu_access_ok()`, que cobre a assinatura de 3 argumentos dos kernels antigos;
- em `selinux/rules.c`, `pol` e `old_pol` só são usados no ramo >= 5.10, e o `-Werror` do kernel transforma o aviso em erro.

Com o patch, o kernel compila com `CONFIG_KSU=y` e `CONFIG_KSU_SUSFS=y`, e o boot mostra `susfs is initialized! version: v2.4.0`.

## Instalação

A build é assinada com chaves de teste, então é preciso uma **instalação limpa (formatar os dados)**. Faça backup antes. Grave `boot`, `dtbo`, `vendor_boot`, `vbmeta` e `vbmeta_system` pelo fastboot, formate os dados no recovery e faça `adb sideload` do zip. Depois instale o gerenciador do [SukiSU-Nova](https://github.com/SukiSU-Nova/SukiSU-Nova/releases).

## Créditos

Evolution X, Deivid21 (árvores do rhode), LineageOS, [SukiSU-Nova](https://github.com/SukiSU-Nova/SukiSU-Nova), [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (simonpunk), [NonGKI_Kernel_Build_2nd](https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd) (JackA1ltman) e backslashxx (hooks). Os patches do kernel derivam de código GPL-2.0.
