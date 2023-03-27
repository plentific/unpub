#!/bin/sh

dart ./unpub/bin/unpub.dart -d ${DB_URL} --proxy-origin ${HOST_NAME} --tlsCAFile ${CA_FILE} --tlsCertificateKeyFile ${CA_KEY_FILE} --tlsCertificateKeyFilePassword ${CA_KEY_PASSWORD} -e true 
