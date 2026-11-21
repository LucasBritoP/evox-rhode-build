#!/usr/bin/env bash
# Evolution X 10.x (branch vic, Android 15) para moto g52 (rhode) + SukiSU-Nova + SUSFS v2.4.0
# + pacote de RAM para 4 GB (blur desligado, sem Quick Tap, heapmaxfree 16m).
# Fontes: árvores oficiais da Evo para o rhode (Evolution-X-Devices, mantenedor Deivid21).
#
# Uso (Ubuntu 22.04, ex.: vast.ai, dentro do tmux), com a pasta patches/ ao lado do script:
#   bash build-evo-rhode.sh 2>&1 | tee build.log
# Requisitos: ~450 GB livres, >=32 GB RAM (64 GB recomendado).
# Variáveis opcionais: SRC (pasta), JOBS, SUKISU_REF, PATCH_DIR, SKIP_SYNC=1 (re-rodar só a build).
set -eo pipefail

SRC=${SRC:-$HOME/evo}
JOBS=${JOBS:-$(nproc)}
# Commit do branch builtin do SukiSU-Nova contra o qual o patch do SUSFS foi validado (21/11/2026).
SUKISU_REF=${SUKISU_REF:-4bec532dd447e2852aa8932afa768255350c103a}
PATCH_DIR=${PATCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches}
SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

# Aplica um patch uma vez só: pula se já estiver aplicado (o reverso aplica limpo); aborta se não aplicar limpo.
# -f/-N evitam que o patch pare para perguntar no terminal.
apply_once() {  # $1 = pasta do repo, $2 = arquivo .patch
  [ -f "$2" ] || die "patch não encontrado: $2"
  patch -d "$1" -p1 -R -f -F0 --dry-run -s < "$2" >/dev/null 2>&1 && return 0
  patch -d "$1" -p1 -N -F0 --dry-run -s < "$2" || die "$(basename "$2") não aplica limpo em $1 (o código mudou?)"
  patch -d "$1" -p1 -N -F0 -s < "$2"
}

# --- Checagens da máquina --------------------------------------------------
mkdir -p "$SRC"
if [ ! -d "$SRC/.repo" ]; then
  free_gb=$(df -BG --output=avail "$SRC" | tail -1 | tr -dc 0-9)
  [ "$free_gb" -ge 450 ] || die "só ${free_gb} GB livres em $SRC; precisa de ~450 GB"
fi
# Em container o /proc/meminfo mostra a RAM do host; o limite real está no cgroup.
mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
for f in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
  v=$(cat "$f" 2>/dev/null || true)
  if [[ "$v" =~ ^[0-9]+$ ]] && (( v / 1024 < mem_kb )); then mem_kb=$(( v / 1024 )); fi
done
ram_gb=$(( mem_kb / 1048576 ))
[ "$ram_gb" -ge 30 ] || die "só ${ram_gb} GB de RAM; Android 15 precisa de >=32 GB"
(( JOBS > ram_gb / 2 )) && JOBS=$(( ram_gb / 2 ))   # ~2 GB por job evita OOM no Java/R8
log "RAM: ${ram_gb} GB | jobs: $JOBS | pasta: $SRC"

# --- Dependências ----------------------------------------------------------
PKGS="bc bison build-essential ccache cpio curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf
  imagemagick kmod lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libncurses5 libsdl1.2-dev libssl-dev
  libxml2 libxml2-utils lzop pngcrush python3 python-is-python3 rsync schedtool squashfs-tools unzip xsltproc
  zip zlib1g-dev"
if dpkg -s $PKGS >/dev/null 2>&1; then
  log "Dependências já instaladas"
else
  log "Instalando dependências"
  export DEBIAN_FRONTEND=noninteractive
  # Lock::Timeout: espera o unattended-upgrades soltar o dpkg em vez de falhar
  $SUDO apt-get -o DPkg::Lock::Timeout=900 update -qq
  $SUDO apt-get -o DPkg::Lock::Timeout=900 install -y -qq $PKGS
fi

mkdir -p "$HOME/bin"
[ -x "$HOME/bin/repo" ] || curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
chmod +x "$HOME/bin/repo"
export PATH="$HOME/bin:$PATH"
git config --global user.name  >/dev/null || git config --global user.name  builder
git config --global user.email >/dev/null || git config --global user.email builder@localhost
git config --global color.ui false   # evita a pergunta interativa do repo init
git lfs install

# --- Código-fonte ----------------------------------------------------------
cd "$SRC"
K=$SRC/kernel/motorola/sm6225
if [ "${SKIP_SYNC:-0}" != 1 ]; then
  log "repo init (Evolution X vic)"
  [ -d .repo ] || repo init -u https://github.com/Evolution-X/manifest -b vic --git-lfs --depth=1 --no-clone-bundle

  # Mesmas dependências do evolution.dependencies das árvores oficiais (branch vic).
  mkdir -p .repo/local_manifests
  cat > .repo/local_manifests/rhode.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="rhode-evo" fetch="https://github.com/Evolution-X-Devices" revision="vic" />
  <remote name="rhode-gh"  fetch="https://github.com" />
  <remote name="rhode-gl"  fetch="https://gitlab.com" />

  <project path="device/motorola/rhode"         name="device_motorola_rhode"         remote="rhode-evo" />
  <project path="device/motorola/sm6225-common" name="device_motorola_sm6225-common" remote="rhode-evo" />
  <project path="kernel/motorola/sm6225"        name="kernel_motorola_sm6225"        remote="rhode-evo" />
  <project path="hardware/motorola"             name="hardware_motorola"             remote="rhode-evo" />

  <project path="vendor/motorola/rhode"         name="Deivid-21s-Sources/proprietary_vendor_motorola_rhode"         remote="rhode-gh" revision="lineage-22.2" />
  <project path="vendor/motorola/sm6225-common" name="Deivid-21s-Sources/proprietary_vendor_motorola_sm6225-common" remote="rhode-gh" revision="lineage-22.2" />

  <project path="vendor/motorola/MotCamera-common"         name="Deivid21/proprietary_vendor_motorola_MotCamera-common"         remote="rhode-gl" revision="android-15" />
  <project path="vendor/motorola/MotCameraAI-common"       name="Deivid21/proprietary_vendor_motorola_MotCameraAI-common"       remote="rhode-gl" revision="android-15" />
  <project path="vendor/motorola/MotCamera2"               name="Deivid21/proprietary_vendor_motorola_MotCamera2"               remote="rhode-gl" revision="android-15" />
  <project path="vendor/motorola/MotCamera2AI"             name="Deivid21/proprietary_vendor_motorola_MotCamera2AI"             remote="rhode-gl" revision="android-15" />
  <project path="vendor/motorola/MotCamera3AI-bengal"      name="Deivid21/proprietary_vendor_motorola_MotCamera3AI-bengal"      remote="rhode-gl" revision="android-15" />
  <project path="vendor/motorola/MotCamera4-bengal"        name="Deivid21/proprietary_vendor_motorola_MotCamera4-bengal"        remote="rhode-gl" revision="android-15" />
  <project path="vendor/motorola/MotoPhotoEditor"          name="Deivid21/proprietary_vendor_motorola_MotoPhotoEditor"          remote="rhode-gl" revision="android-15" />
  <project path="vendor/motorola/MotoSignatureApp"         name="Deivid21/proprietary_vendor_motorola_MotoSignatureApp"         remote="rhode-gl" revision="android-15" />
  <project path="vendor/motorola/MotorolaSettingsProvider" name="Deivid21/proprietary_vendor_motorola_MotorolaSettingsProvider" remote="rhode-gl" revision="android-15" />
</manifest>
EOF

  # Desfaz os nossos patches para o sync não travar; eles são reaplicados abaixo.
  [ -e "$K/.git" ] && git -C "$K" reset -q --hard && git -C "$K" clean -fdq fs include
  for d in device/motorola/rhode device/motorola/sm6225-common vendor/motorola/MotCamera-common; do
    [ -e "$d/.git" ] && git -C "$d" reset -q --hard
  done

  log "repo sync (1-2 h, depende da rede)"
  sj=$(( JOBS < 16 ? JOBS : 16 ))   # muitas conexões simultâneas levam rate-limit do GitHub
  for i in 1 2 3; do
    repo sync -c -j"$sj" --force-sync --no-clone-bundle --no-tags --optimized-fetch && break
    [ "$i" = 3 ] && die "repo sync falhou 3 vezes"
    log "sync falhou, tentando de novo ($i/3)"
  done
fi

# --- SukiSU-Nova + SUSFS ---------------------------------------------------
# Mesmo que o kernel/setup.sh oficial faz (clone + symlink + Makefile/Kconfig), sem baixar script remoto.
log "Integrando SukiSU-Nova (builtin @ ${SUKISU_REF:0:8}) + SUSFS no kernel"
if [ ! -d "$K/KernelSU/.git" ]; then
  git clone -b builtin https://github.com/SukiSU-Nova/SukiSU-Nova "$K/KernelSU"
  git -C "$K/KernelSU" branch -q main origin/main   # o Makefile conta commits de "main" se a API do GitHub falhar
fi
git -C "$K/KernelSU" checkout -q -f "$SUKISU_REF"
# Ajustes para compilar o builtin no 4.19: static_call.h só existe a partir do 5.10, access_ok de 3 args
# no KPM e variáveis só usadas no ramo >= 5.10 (com -Werror).
apply_once "$K/KernelSU" "$PATCH_DIR/sukisu-4.19.patch"
ln -sfn ../KernelSU/kernel "$K/drivers/kernelsu"
grep -q 'kernelsu/' "$K/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$K/drivers/Makefile"
grep -q 'drivers/kernelsu/Kconfig' "$K/drivers/Kconfig" || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$K/drivers/Kconfig"

# SUSFS v2.4.0 + inline hooks, já adaptado e testado contra este kernel.
apply_once "$K" "$PATCH_DIR/susfs-v2.4.0-rhode-4.19.patch"

# rhode-default.config já entra no TARGET_KERNEL_CONFIG do BoardConfig.mk do rhode.
# As sub-opções do SUSFS vêm ligadas por padrão no Kconfig do SukiSU.
CFG=$K/arch/arm64/configs/vendor/ext_config/rhode-default.config
grep -q '^CONFIG_KSU=' "$CFG" || cat >> "$CFG" <<'EOF'

# SukiSU-Nova (builtin, hooks inline do SUSFS)
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
EOF

# --- Correção de fonte: sepolicy da câmera ----------------------------------
# MotCamera-common (android-15, jun/2026) duplica entradas que já estão em hardware/motorola e
# device/qcom/sepolicy, e o host_init_verifier aborta com "Duplicate exact match".
apply_once "$SRC/vendor/motorola/MotCamera-common" "$PATCH_DIR/motcamera-common-sepolicy.patch"

# --- Pacote de RAM (4 GB) ---------------------------------------------------
log "Aplicando o pacote de RAM nas device trees"
apply_once "$SRC/device/motorola/rhode"         "$PATCH_DIR/rhode-ram.patch"
apply_once "$SRC/device/motorola/sm6225-common" "$PATCH_DIR/sm6225-common-ram.patch"

# --- Build -----------------------------------------------------------------
cd "$SRC"
set +e; source build/envsetup.sh; set -e   # envsetup.sh não foi feito para set -e
# Funções do envsetup chamadas com "|| die": o set -e não age dentro delas.
lunch lineage_rhode-bp1a-userdebug || die "lunch falhou"

log "Compilando boot.img primeiro (checa o KernelSU em minutos, não em horas)"
m bootimage -j"$JOBS" || die "falha ao compilar o boot.img/kernel (veja o log acima)"
KO=$OUT/obj/KERNEL_OBJ
grep -q '^CONFIG_KSU=y' "$KO/.config" && grep -q '^CONFIG_KSU_SUSFS=y' "$KO/.config" \
  || die "SukiSU/SUSFS não entrou no .config final ($KO/.config)"
# Pelo System.map: o nome do objeto muda entre versões do kbuild (ksu.o / ksu_main.o).
grep -qw apply_kernelsu_rules "$KO/System.map" || die "SukiSU não está no kernel (System.map)"
grep -qw susfs_init "$KO/System.map" || die "SUSFS não está no kernel (System.map)"
log "SukiSU-Nova + SUSFS OK no kernel"

log "Compilando a ROM (2-4 h)"
m evolution -j"$JOBS" || die "falha na build da ROM (veja o log acima)"

# --- Saída -----------------------------------------------------------------
ZIP=$(ls -t "$OUT"/EvolutionX*.zip 2>/dev/null | head -1 || true)
[ -n "$ZIP" ] || die "zip da ROM não encontrado em $OUT"
R=$SRC/release
mkdir -p "$R"
cp "$ZIP" "$R/"
for i in boot dtbo vendor_boot vbmeta vbmeta_system; do
  if [ -f "$OUT/$i.img" ]; then cp "$OUT/$i.img" "$R/"; else echo "aviso: $i.img não gerado"; fi
done
(cd "$R" && sha256sum -- * > SHA256SUMS)

# Confere se o pacote de RAM chegou à imagem (aviso, não erro: o zip já está pronto).
grep -q '^ro.custom.blur.enable=false' "$OUT/system/build.prop" || echo "AVISO: blur não aparece desligado em system/build.prop"
find "$OUT/system" "$OUT/system_ext" "$OUT/product" -name 'ColumbusService*' 2>/dev/null | grep -q . \
  && echo "AVISO: ColumbusService (Quick Tap) ainda está na imagem"
grep -rqs 'heapmaxfree 16m' "$OUT/vendor/etc/init" || echo "AVISO: heapmaxfree 16m não encontrado em vendor/etc/init"

log "Pronto! Arquivos em $R"
ls -lh "$R"
