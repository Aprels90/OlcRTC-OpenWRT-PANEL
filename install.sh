#!/bin/sh
# =============================================================================
# Установочный скрипт OlcRTC-OpenWRT
# Проект: https://github.com/tankionline2005/OlcRTC-OpenWRT
# Основан на OlcRTC: https://github.com/openlibrecommunity/olcrtc
#   автора zarazaex / openlibrecommunity
# =============================================================================

set -e

REPO_RAW="https://raw.githubusercontent.com/Aprels90/OlcRTC-OpenWRT-PANEL/main"
BINARY_ARM64_URL="https://github.com/openlibrecommunity/olcrtc/releases/latest/download/olcrtc-linux-arm64"
BINARY_AMD64_URL="https://github.com/openlibrecommunity/olcrtc/releases/latest/download/olcrtc-linux-amd64"
BINARY_DST="/usr/bin/olcrtc"
INITD="/etc/init.d/olcrtc"
UCI_CONF="/etc/config/olcrtc"
LUCI_MENU="/usr/share/luci/menu.d/luci-app-olcrtc.json"
LUCI_ACL="/usr/share/rpcd/acl.d/luci-app-olcrtc.json"
LUCI_VIEW_DIR="/www/luci-static/resources/view/olcrtc"
LUCI_VIEW="${LUCI_VIEW_DIR}/main.js"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[ОК]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!!]${NC} $*"; }
error() { echo -e "${RED}[ОШ]${NC} $*"; exit 1; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║      Установка OlcRTC-OpenWRT        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Проверки ──────────────────────────────────────────────
command -v wget  >/dev/null 2>&1 || error "wget не найден"
command -v uci   >/dev/null 2>&1 || error "uci не найден (это не OpenWRT?)"

# ── Выбор архитектуры ─────────────────────────────────────
echo "Выберите архитектуру:"
echo "  1) arm64  — роутеры (Cudy, GL.iNet, OpenWRT на ARM)"
echo "  2) amd64  — ПК или сервер под OpenWRT (x86-64)"
printf "Ваш выбор [1/2]: "
read ARCH_CHOICE
case "$ARCH_CHOICE" in
    2) BINARY_URL="$BINARY_AMD64_URL"; ARCH_NAME="AMD64" ;;
    *) BINARY_URL="$BINARY_ARM64_URL"; ARCH_NAME="ARM64" ;;
esac

# ── Получаем бинарник OlcRTC ─────────────────────────────
install_go_toolchain() {
    if command -v opkg >/dev/null 2>&1; then
        opkg update
        opkg install -y git git-http ca-certificates go
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache git go
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y git ca-certificates golang
    fi
}

build_olcrtc_from_source() {
    local src_dir="/tmp/olcrtc-src"

    if ! command -v git >/dev/null 2>&1; then
        warn "git не найден, пробуем установить инструменты сборки..."
        install_go_toolchain || true
    fi

    if ! command -v go >/dev/null 2>&1; then
        warn "Go не найден после попытки установки. Сначала установите go и git, затем повторите установку."
        return 1
    fi

    rm -rf "$src_dir"
    git clone --depth 1 --branch master "https://github.com/openlibrecommunity/olcrtc.git" "$src_dir" || \
        return 1

    cd "$src_dir" || return 1
    go build -trimpath -ldflags "-s -w" -o "$BINARY_DST" ./cmd/olcrtc || \
        return 1

    chmod 755 "$BINARY_DST"
    info "Бинарник собран из актуального upstream: $BINARY_DST"
    return 0
}

info "Проверяем наличие бинарника OlcRTC (${ARCH_NAME})..."
if [ -x "$BINARY_DST" ]; then
    info "Бинарник уже установлен: $BINARY_DST"
elif [ -n "$BINARY_URL" ] && wget -q --spider "$BINARY_URL" 2>/dev/null; then
    info "Скачиваем бинарник OlcRTC (${ARCH_NAME}) из upstream..."
    wget -q -O "$BINARY_DST" "$BINARY_URL" || warn "Скачивание релиза не удалось, пробуем сборку из исходников"
    chmod 755 "$BINARY_DST" 2>/dev/null || true
fi

if [ ! -x "$BINARY_DST" ] && ! [ -f "$BINARY_DST" ]; then
    warn "Релиз не найден или недоступен; собираем бинарник из исходников upstream..."
    build_olcrtc_from_source || \
        error "Не удалось получить бинарник OlcRTC. Установите go/git вручную или соберите его из https://github.com/openlibrecommunity/olcrtc"
fi

if [ -x "$BINARY_DST" ] || [ -f "$BINARY_DST" ]; then
    chmod 755 "$BINARY_DST" 2>/dev/null || true
    info "Готово: $BINARY_DST (${ARCH_NAME})"
else
    error "Бинарник OlcRTC так и не появился в $BINARY_DST"
fi

# ── init.d скрипт ─────────────────────────────────────────
info "Устанавливаем init.d скрипт..."
wget -q -O "$INITD" "${REPO_RAW}/files/etc/init.d/olcrtc" || \
    error "Не удалось скачать init.d скрипт"
chmod 755 "$INITD"
"$INITD" enable
info "init.d скрипт установлен и включён в автозагрузку"

# ── UCI конфиг ────────────────────────────────────────────
if [ ! -f "$UCI_CONF" ]; then
    info "Создаём конфигурацию UCI..."
    wget -q -O "$UCI_CONF" "${REPO_RAW}/files/etc/config/olcrtc" || \
        error "Не удалось создать UCI конфиг"
    info "Конфиг создан: $UCI_CONF"
else
    warn "UCI конфиг уже существует, пропускаем ($UCI_CONF)"
fi

# ── HWID — идентификатор установки ───────────────────────
HWID_CUR="$(uci get olcrtc.config.hwid 2>/dev/null || true)"
if [ -z "$HWID_CUR" ]; then
    HWID="install-$(cat /proc/sys/kernel/random/uuid | tr -d '-')"
    uci set olcrtc.config.hwid="$HWID"
    uci commit olcrtc
    info "Идентификатор установки: $HWID"
else
    info "Идентификатор установки: $HWID_CUR (сохранён)"
fi

# ── LuCI: меню ────────────────────────────────────────────
info "Устанавливаем LuCI-меню..."
mkdir -p "$(dirname $LUCI_MENU)"
wget -q -O "$LUCI_MENU" "${REPO_RAW}/files/usr/share/luci/menu.d/luci-app-olcrtc.json" || \
    error "Не удалось скачать файл меню"

# ── LuCI: права доступа rpcd ──────────────────────────────
info "Устанавливаем ACL для rpcd..."
mkdir -p "$(dirname $LUCI_ACL)"
wget -q -O "$LUCI_ACL" "${REPO_RAW}/files/usr/share/rpcd/acl.d/luci-app-olcrtc.json" || \
    error "Не удалось скачать ACL"

# ── LuCI: JS-вид ──────────────────────────────────────────
info "Устанавливаем интерфейс LuCI..."
mkdir -p "$LUCI_VIEW_DIR"
wget -q -O "$LUCI_VIEW" "${REPO_RAW}/files/www/luci-static/resources/view/olcrtc/main.js" || \
    error "Не удалось скачать JS-вид LuCI"

# ── Перезапуск сервисов ───────────────────────────────────
info "Перезапускаем rpcd и uhttpd..."
/etc/init.d/rpcd    restart 2>/dev/null || warn "rpcd не перезапущен (возможно не установлен)"
/etc/init.d/uhttpd  restart 2>/dev/null || warn "uhttpd не перезапущен (возможно не установлен)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Установка завершена!                                ║"
echo "║                                                      ║"
echo "║  Откройте LuCI: Службы → OlcRTC                      ║"
echo "║  Заполните Room ID, Client ID и ключ —              ║"
echo "║  затем нажмите Старт                                 ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
