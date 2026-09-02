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

# ── Скачиваем бинарник из актуального upstream ───────────
info "Проверяем официальный релиз OlcRTC (${ARCH_NAME})..."
for candidate in \
    "https://github.com/openlibrecommunity/olcrtc/releases/latest/download/olcrtc-linux-${ARCH_NAME}.tar.gz" \
    "https://github.com/openlibrecommunity/olcrtc/releases/latest/download/olcrtc-linux-${ARCH_NAME}" \
    "https://github.com/openlibrecommunity/olcrtc/releases/latest/download/olcrtc-${ARCH_NAME}"; do
    if wget -q --spider "$candidate" 2>/dev/null; then
        BINARY_URL="$candidate"
        break
    fi
done

if [ -n "$BINARY_URL" ]; then
    info "Скачиваем бинарник olcrtc (${ARCH_NAME}) из upstream..."
    wget -q -O "$BINARY_DST" "$BINARY_URL" || \
        warn "Кэшированный релиз недоступен, необходимо собрать бинарник вручную из upstream"
else
    warn "Автоматический релиз не найден. Установите актуальный бинарник OlcRTC вручную из https://github.com/openlibrecommunity/olcrtc"
fi

if [ -x "$BINARY_DST" ] || [ -f "$BINARY_DST" ]; then
    chmod 755 "$BINARY_DST" 2>/dev/null || true
    info "Бинарник установлен: $BINARY_DST (${ARCH_NAME})"
else
    warn "Бинарник OlcRTC пока не установлен. Это панель LuCI, а реальный клиент должен быть взят из официального upstream проекта."
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
