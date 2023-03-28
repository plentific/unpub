FROM dart:2.19

COPY . /app
COPY docker/entrypoint.sh /app/entrypoint.sh

# Download CA for DocumentDB
RUN curl -LJO https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
COPY global-bundle.pem /app/ca.pem
ARG CA_FILE=/app/ca.pem

# Download app dependencies 
WORKDIR /app/unpub
RUN dart pub get 

# Prepare and run entrypoint
WORKDIR /app
RUN chmod +x entrypoint.sh
EXPOSE 4000
ENTRYPOINT [ "/app/entrypoint.sh" ]
