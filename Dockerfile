# Builds the Cake image: the bot and everything it needs (Ruby, Node, ffmpeg, yt-dlp).
# No secrets and no data in it: see .dockerignore and compose.yaml.

# --- the web UI, built into plain files ---
FROM node:22-bookworm-slim AS web
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

# --- the Node packages of the music player ---
FROM node:22-bookworm-slim AS music
WORKDIR /music
COPY music/package.json music/package-lock.json ./
RUN npm ci --omit=dev

# --- the Ruby gems (some need a compiler, which the final image does not need) ---
FROM ruby:3.3-slim-bookworm AS gems
RUN apt-get update && apt-get install -y --no-install-recommends build-essential
ENV BUNDLE_WITHOUT=test BUNDLE_FROZEN=true
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install

# --- the final image ---
FROM ruby:3.3-slim-bookworm
# tzdata: without it, the TZ setting is ignored and the bot's clock is UTC
RUN apt-get update \
  && apt-get install -y --no-install-recommends ffmpeg python3 python3-pip tzdata ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=music /usr/local/bin/node /usr/local/bin/node

# A new value (GitHub Actions gives one per run) makes Docker install the newest yt-dlp again.
# From pip: the standalone program is only a launcher, which is harder to stop.
ARG YT_DLP_REFRESH=none
RUN echo "yt-dlp refresh: $YT_DLP_REFRESH" \
  && pip install --break-system-packages --no-cache-dir "yt-dlp[default]"

COPY --from=gems /usr/local/bundle /usr/local/bundle
WORKDIR /app
COPY . .
COPY --from=web /web/dist ./web/dist
COPY --from=music /music/node_modules ./music/node_modules

ENV BUNDLE_WITHOUT=test BUNDLE_FROZEN=true \
    CAKE_DATA_DIR=/data WEB_UI_HOST=0.0.0.0 HOME=/tmp
RUN mkdir /data && chown 1000:1000 /data
USER 1000:1000
CMD ["bundle", "exec", "ruby", "cakee.rb"]
