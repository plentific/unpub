#!/bin/sh

# exec, so the server is the container's PID 1 and receives the SIGTERM
# Kubernetes sends when it stops the pod.
exec dart ./unpub/bin/unpub.dart -d "${DB_URL}" --proxy-origin "${HOST_NAME}" --tlsCAFile "${CA_PATH}"
