# Build from the PROJECT ROOT (the server depends on packages/pet_core, which
# lives outside backend/):
#
#     docker build -f backend/Dockerfile -t whiskers-backend .
#     docker run --rm -p 8080:8080 --env-file backend/.env whiskers-backend
#
# NOTE: this file has not been built in the environment where it was written.

# ---- stage 1: compile to a single native executable ------------------------
FROM dart:stable AS build
WORKDIR /app
COPY packages/pet_core packages/pet_core
COPY backend backend
WORKDIR /app/backend
RUN dart pub get
RUN dart compile exe bin/server.dart -o /app/server

# ---- stage 2: a small image that only runs it ------------------------------
FROM debian:stable-slim
# CA certificates: the server makes HTTPS calls to the AI providers.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --no-create-home app
COPY --from=build /app/server /app/server
# Do not run as root.
USER app
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/server"]
