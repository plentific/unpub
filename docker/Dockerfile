FROM dart:3.12.2

COPY . /app
COPY docker/entrypoint.sh /app/entrypoint.sh

# Download app dependencies, exactly as locked
WORKDIR /app/unpub
RUN dart pub get --enforce-lockfile

# Prepare and run entrypoint
WORKDIR /app
RUN chmod +x entrypoint.sh
EXPOSE 4000
ENTRYPOINT [ "/app/entrypoint.sh" ]
