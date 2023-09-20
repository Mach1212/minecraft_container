FROM docker.io/library/amazoncorretto:20-alpine3.18-full

WORKDIR /app
COPY ./server_files/ .

CMD ["java", "-jar", "server.jar"]

