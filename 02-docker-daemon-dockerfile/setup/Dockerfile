FROM ubuntu:latest

ENV DB_PASSWORD=SuperSecret123

RUN apt-get update && apt-get install -y curl wget netcat-openbsd openssh-server sudo

COPY app.sh /app/app.sh
RUN chmod 777 /app/app.sh

EXPOSE 22

USER root

CMD ["/app/app.sh"]
