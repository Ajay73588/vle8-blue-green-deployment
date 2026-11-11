FROM nginx:1.27-alpine

ARG APP_COLOR=BLUE
ARG APP_VERSION=v1
ARG BUILD_TAG=local
ARG RELEASE_NOTE=""

ENV APP_NAME="VLE-8 Blue-Green Deployment" \
    APP_COLOR="${APP_COLOR}" \
    APP_VERSION="${APP_VERSION}" \
    BUILD_TAG="${BUILD_TAG}" \
    RELEASE_NOTE="${RELEASE_NOTE}"

RUN mkdir -p /opt/vle8-templates

COPY app/index.html.template /opt/vle8-templates/index.html.template
COPY app/nginx.conf.template /opt/vle8-templates/nginx.conf.template
COPY app/docker-entrypoint-render.sh /docker-entrypoint.d/40-vle8-render.sh

RUN chmod +x /docker-entrypoint.d/40-vle8-render.sh

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/health | grep -q '"status":"healthy"' || exit 1
