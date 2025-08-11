#!/bin/bash
set -e

DESKTOP_ENV=$(echo "${XDG_CURRENT_DESKTOP,,}")
ENV_FILE="${1:-$HOME/.config/jellyfin-podman.env}"

load_env_config() {
    if [[ -f "$ENV_FILE" ]]; then
        echo "🧠 تحميل الإعدادات من $ENV_FILE..."
        set -o allexport
        source "$ENV_FILE"
        set +o allexport
        return 0
    fi
    return 1
}

interactive_config() {
    echo "❓ ملف إعدادات مش موجود، هيتم سؤالك دلوقتي."

    read -rp "📦 اسم الكونتينر (default: myjellyfin): " CONTAINER_NAME
    CONTAINER_NAME="${CONTAINER_NAME:-myjellyfin}"

    echo "🖼️ اختار صورة Jellyfin:"
    echo "1) docker.io/jellyfin/jellyfin:latest (الرسمية)"
    echo "2) lscr.io/linuxserver/jellyfin:latest"
    read -rp "رقم الصورة [1/2] (default: 1): " IMAGE_CHOICE
    IMAGE=$([[ "$IMAGE_CHOICE" == "2" ]] && echo "lscr.io/linuxserver/jellyfin:latest" || echo "docker.io/jellyfin/jellyfin:latest")

    read -rp "📁 config dir: " CONFIG_DIR
    read -rp "📁 cache dir: " CACHE_DIR
    read -rp "📁 anime dir: " ANIME_DIR
    read -rp "📁 movies dir: " MOVIES_DIR
    read -rp "📁 TV shows dir (مثلاً /path/to/tvshows): " TVSHOWS_DIR

    read -rp "⬇️ تسحب أحدث نسخة من الصورة؟ [y/N]: " PULL_IMAGE
    read -rp "⚙️ تفعيل auto-update؟ [y/N]: " ENABLE_AUTOUPDATE

    mkdir -p "$(dirname "$ENV_FILE")"
    cat > "$ENV_FILE" <<EOF
CONTAINER_NAME="$CONTAINER_NAME"
IMAGE="$IMAGE"
CONFIG_DIR="$CONFIG_DIR"
CACHE_DIR="$CACHE_DIR"
ANIME_DIR="$ANIME_DIR"
MOVIES_DIR="$MOVIES_DIR"
TVSHOWS_DIR="$TVSHOWS_DIR"
PULL_IMAGE="$PULL_IMAGE"
ENABLE_AUTOUPDATE="$ENABLE_AUTOUPDATE"
EOF

    echo "💾 تم حفظ الإعدادات فى $ENV_FILE"
}

pull_image() {
    if [[ "$PULL_IMAGE" =~ ^[YyTt] ]]; then
        echo "⬇️ سحب أحدث نسخة من الصورة..."
        podman pull "$IMAGE"
    fi
}

remove_old_container() {
    if podman container exists "$CONTAINER_NAME"; then
        echo "🛑 حذف الكونتينر القديم..."
        podman stop "$CONTAINER_NAME" || true
        podman rm "$CONTAINER_NAME"
    fi
}

run_container() {
    echo "🚀 تشغيل Jellyfin..."

    # على Arch عادة SELinux مش مفعّل، فمش هنستخدم :Z ولا relabel

    podman run -d \
        --name "$CONTAINER_NAME" \
        --label "io.containers.autoupdate=registry" \
        --publish 8096:8096 \
        --userns keep-id \
        --volume "$CONFIG_DIR":/config:rw \
        --volume "$CACHE_DIR":/cache:rw \
        --mount type=bind,source="$ANIME_DIR",target=/anime,readonly=true \
        --mount type=bind,source="$MOVIES_DIR",target=/movies,readonly=true \
        --mount type=bind,source="$TVSHOWS_DIR",target=/tvshows,readonly=true \
        "$IMAGE"
}

generate_service() {
    echo "⚙️ توليد systemd service..."
    SERVICE_FILE="container-$CONTAINER_NAME.service"
    podman generate systemd --name "$CONTAINER_NAME" --files --restart-policy=always

    # تعديل المسارات اللى فيها مسافات (لو موجودة)
    sed -i -E 's/(source|target)=(([^" ]+)[^"]*[^" ]+)/\1="\2"/g' "$SERVICE_FILE"

    mkdir -p ~/.config/systemd/user
    mv "$SERVICE_FILE" ~/.config/systemd/user/

    systemctl --user daemon-reload
}

enable_linger_and_service() {
    # تفعيل linger علشان الخدمة تشتغل بعد الريستارت بدون login
    loginctl enable-linger "$USER"

    # تهيئة مؤقتة للـ systemd session لو مش شغالة (مفيد فى KDE)
    if ! systemctl --user is-active --quiet basic.target; then
        echo "🛠️ تهيئة مؤقتة لـ systemd user session..."
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
        systemctl --user daemon-reexec
    fi

    echo "🔄 تشغيل الخدمة..."
    if ! systemctl --user enable --now "container-$CONTAINER_NAME.service"; then
        echo "⚠️ تحذير: حصلت مشكلة أثناء تشغيل الخدمة، بنراجع الحالة..."
    fi

    sleep 3

    if systemctl --user is-active --quiet "container-$CONTAINER_NAME.service"; then
        echo "✅ الخدمة اشتغلت بنجاح!"
    else
        echo "❌ فيه مشكلة فعلًا فى تشغيل الخدمة:"
        systemctl --user status "container-$CONTAINER_NAME.service"
        exit 1
    fi
}

enable_auto_update() {
    if [[ "${ENABLE_AUTOUPDATE,,}" == "y" || "${ENABLE_AUTOUPDATE,,}" == "yes" || "${ENABLE_AUTOUPDATE,,}" == "true" ]]; then
        echo "✅ تفعيل auto-update..."
        # على Arch podman-auto-update timer شغال على مستوى المستخدم user
        systemctl --user enable --now podman-auto-update.timer
        echo "✅ auto-update شغّالة!"
    else
        echo "ℹ️ auto-update مش مفعّل."
    fi
}

# 🚦 البداية
if ! load_env_config; then
    interactive_config
    load_env_config
fi

pull_image
remove_old_container
run_container
generate_service
enable_linger_and_service
enable_auto_update

echo "🎉 Jellyfin جاهز على http://localhost:8096"
