FROM dart:3.12.2 AS build

COPY . /app

# Download app dependencies, exactly as locked
WORKDIR /app/unpub
RUN dart pub get --enforce-lockfile

# Compile ahead of time: the image needs no SDK, and the server starts
# without compiling itself first
RUN dart compile exe bin/unpub.dart -o /app/unpub-server

# The Debian release the dart image is built on, for the same C library
FROM debian:trixie-slim

# Root certificates for TLS to S3, STS and Google
RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/unpub-server /app/unpub-server
COPY docker/entrypoint.sh /app/entrypoint.sh

# Prepare and run entrypoint
WORKDIR /app
RUN chmod +x entrypoint.sh
EXPOSE 4000
ENTRYPOINT [ "/app/entrypoint.sh" ]
