# Fixture image that crashes on start. Never pushed.
FROM node:22-alpine
RUN apk upgrade --no-cache
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION PORT=3000
WORKDIR /app
COPY index.js ./
USER node
EXPOSE 3000
CMD ["node", "index.js"]
