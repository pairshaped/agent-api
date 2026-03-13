# Build stage: compile the Gleam app and pre-compile deps
FROM erlang:28 AS build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git gcc make autoconf libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Gleam (detect architecture at runtime, not via TARGETARCH which
# requires buildx and isn't set by plain docker build)
ARG GLEAM_VERSION=1.14.0
RUN ARCH=$(uname -m | sed 's/x86_64/x86_64/' | sed 's/aarch64/aarch64/') && \
    curl -fsSL "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-${ARCH}-unknown-linux-musl.tar.gz" \
    | tar xz -C /usr/local/bin

# Install rebar3 (needed to compile esqlite NIF)
RUN curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o /usr/local/bin/rebar3 \
    && chmod +x /usr/local/bin/rebar3

WORKDIR /app
ENV HOME=/root

# Download and compile deps (cached unless gleam.toml/manifest.toml change).
# Uses a dummy source file so `gleam build` compiles all dependencies
# including esqlite's C NIF (~27s) without needing real app source.
COPY gleam.toml manifest.toml ./
RUN gleam deps download \
    && mkdir -p src && echo "pub fn main() { Nil }" > src/gleam_mcp_todo.gleam \
    && gleam build \
    && rm -rf src

# Copy real source and build (only app code recompiles, deps are cached)
COPY src/ src/
COPY db/migrations/ db/migrations/
COPY bin/migrate bin/migrate
RUN gleam build

# Run stage: minimal image with just Erlang + Gleam + the build
FROM erlang:28-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Install Gleam in runtime image (needed for `gleam run`)
ARG GLEAM_VERSION=1.14.0
RUN ARCH=$(uname -m | sed 's/x86_64/x86_64/' | sed 's/aarch64/aarch64/') && \
    curl -fsSL "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-${ARCH}-unknown-linux-musl.tar.gz" \
    | tar xz -C /usr/local/bin

WORKDIR /app

# Copy the compiled build, source, and supporting files
COPY --from=build /app/build/ build/
COPY --from=build /app/src/ src/
COPY --from=build /app/gleam.toml /app/manifest.toml ./
COPY --from=build /app/db/migrations/ db/migrations/
COPY --from=build /app/bin/migrate bin/migrate

EXPOSE 8080

CMD ["sh", "-c", "bin/migrate && gleam run"]
