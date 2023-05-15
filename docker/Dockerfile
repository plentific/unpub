FROM dart:2.19

COPY . /app
COPY docker/entrypoint.sh /app/entrypoint.sh

# Download app dependencies 
WORKDIR /app/unpub
RUN dart pub get 

# Prepare and run entrypoint
WORKDIR /app
RUN chmod +x entrypoint.sh
EXPOSE 4000
ENTRYPOINT [ "/app/entrypoint.sh" ]
