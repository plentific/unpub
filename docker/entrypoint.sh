#!/bin/sh

# exec, so the server is the container's PID 1 and receives the SIGTERM
# Kubernetes sends when it stops the pod.
exec /app/unpub-server -d "${DB_URL}" --proxy-origin "${HOST_NAME}" --tlsCAFile "${CA_PATH}"
