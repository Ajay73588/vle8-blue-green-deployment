#!/bin/sh
set -eu

APP_NAME="${APP_NAME:-VLE-8 Blue-Green Deployment}"
APP_COLOR_RAW="${APP_COLOR:-BLUE}"
APP_COLOR="$(printf '%s' "$APP_COLOR_RAW" | tr '[:lower:]' '[:upper:]')"
APP_COLOR_LOWER="$(printf '%s' "$APP_COLOR" | tr '[:upper:]' '[:lower:]')"
APP_VERSION="${APP_VERSION:-v1}"
BUILD_TAG="${BUILD_TAG:-$APP_COLOR_LOWER-$APP_VERSION}"
POD_NAME="$(hostname)"
STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [ "$APP_COLOR" = "GREEN" ]; then
  BG_START="#065f46"
  BG_END="#022c22"
  ACCENT="#10b981"
  ACCENT_SOFT="#6ee7b7"
  BADGE_BG="#16a34a"
  RELEASE_NOTE="${RELEASE_NOTE:-Green environment ($APP_VERSION) is active. This release introduces the updated Green theme and verified rollout candidate.}"
else
  APP_COLOR="BLUE"
  APP_COLOR_LOWER="blue"
  BG_START="#1e40af"
  BG_END="#0f172a"
  ACCENT="#3b82f6"
  ACCENT_SOFT="#93c5fd"
  BADGE_BG="#2563eb"
  RELEASE_NOTE="${RELEASE_NOTE:-Blue environment ($APP_VERSION) is serving stable baseline traffic routed by Kubernetes Service myapp-service.}"
fi

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

render_file() {
  src="$1"
  dst="$2"
  sed \
    -e "s|__APP_NAME__|$(escape_sed "$APP_NAME")|g" \
    -e "s|__APP_COLOR_LOWER__|$(escape_sed "$APP_COLOR_LOWER")|g" \
    -e "s|__APP_COLOR__|$(escape_sed "$APP_COLOR")|g" \
    -e "s|__APP_VERSION__|$(escape_sed "$APP_VERSION")|g" \
    -e "s|__BUILD_TAG__|$(escape_sed "$BUILD_TAG")|g" \
    -e "s|__POD_NAME__|$(escape_sed "$POD_NAME")|g" \
    -e "s|__STARTED_AT__|$(escape_sed "$STARTED_AT")|g" \
    -e "s|__BG_START__|$(escape_sed "$BG_START")|g" \
    -e "s|__BG_END__|$(escape_sed "$BG_END")|g" \
    -e "s|__ACCENT_SOFT__|$(escape_sed "$ACCENT_SOFT")|g" \
    -e "s|__ACCENT__|$(escape_sed "$ACCENT")|g" \
    -e "s|__BADGE_BG__|$(escape_sed "$BADGE_BG")|g" \
    -e "s|__RELEASE_NOTE__|$(escape_sed "$RELEASE_NOTE")|g" \
    "$src" > "$dst"
}

render_file /opt/vle8-templates/index.html.template /usr/share/nginx/html/index.html
render_file /opt/vle8-templates/nginx.conf.template /etc/nginx/conf.d/default.conf

cat > /usr/share/nginx/html/health.json <<EOF
{"status":"healthy","app":"$APP_NAME","color":"$APP_COLOR","version":"$APP_VERSION","pod":"$POD_NAME","build":"$BUILD_TAG","started_at":"$STARTED_AT"}
EOF

cat > /usr/share/nginx/html/info.json <<EOF
{"app":"$APP_NAME","color":"$APP_COLOR","selector":{"app":"myapp","color":"$APP_COLOR_LOWER"},"version":"$APP_VERSION","pod":"$POD_NAME","build":"$BUILD_TAG","started_at":"$STARTED_AT","release_note":"$RELEASE_NOTE"}
EOF
