# WriteFreely on Railway — one-click deploy wrapper
#
# Upstream: writefreely/writefreely v0.17.3 (clean, Markdown-based
# publishing platform, AGPL-3.0). Single service, embedded SQLite
# database, no companion services needed.
#
# Pinned by manifest-list digest, digest-only FROM (Railpack 0.43.0 cannot
# plan a FROM that carries both a tag and a digest; the digest-only form
# builds under both the Dockerfile builder and Railpack planning).
#   tag: v0.17.3 (published 2026-11-09; image built by upstream's
#   docker-publish.yml workflow to ghcr.io/writefreely/writefreely)
#   manifest list: sha256:cf82aaddd1de1618c3a6c6804810b88d7799977f763671ac877b67e47502c784
#   amd64 manifest: sha256:973d6715f0f15bf527caff569c7dccc4e3977209dd5d29f736bcd9e39e08e517
#   image config (verified via registry API): USER daemon, WORKDIR /go,
#   entrypoint cmd/writefreely/writefreely, Alpine base with wget, EXPOSE 8080.
FROM ghcr.io/writefreely/writefreely@sha256:cf82aaddd1de1618c3a6c6804810b88d7799977f763671ac877b67e47502c784

# The stock image runs as USER daemon — it cannot write to Railway's
# root-owned persistent volume, so the wrapper runs as root (the config,
# SQLite database, and ActivityPub keys all live under /data).
USER root

EXPOSE 8080

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Do NOT set a Docker HEALTHCHECK: Railway's external healthcheckPath (/)
# is the probe instead. The upstream image's own healthcheck hits
# localhost:8080, which would also work, but the wrapper entrypoint replaces
# the stock entrypoint and Railway's probe is authoritative.
ENTRYPOINT ["/entrypoint.sh"]

LABEL org.opencontainers.image.source="https://github.com/INAPP-Mobile/writefreely"
