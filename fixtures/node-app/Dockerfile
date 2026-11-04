# Fixture image. Deliberately small: no npm, patched OS packages, so Trivy's
# HIGH/CRITICAL gate stays quiet on a fixture nobody maintains.
FROM node:22-alpine
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION PORT=3000
WORKDIR /app
COPY server.js ./
USER node
EXPOSE 3000
CMD ["node", "server.js"]
