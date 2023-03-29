FROM dart:2.19

COPY . /app
COPY docker/entrypoint.sh /app/entrypoint.sh

# Download CA for DocumentDB
RUN curl -LJ https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /app/ca.pem

# Download app dependencies 
WORKDIR /app/unpub
RUN dart pub get 

# Prepare and run entrypoint
WORKDIR /app
RUN chmod +x entrypoint.sh
EXPOSE 4000
ENTRYPOINT [ "/app/entrypoint.sh" ]
