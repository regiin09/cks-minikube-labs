# SOLUTION: fixed /opt/course/02/Dockerfile
FROM ubuntu:22.04
# 1. pinned tag instead of :latest

# 2. secret removed from ENV (pass at runtime via a K8s Secret instead)

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
# 3. only what the app needs: no ssh server, sudo, wget, netcat

COPY app.sh /app/app.sh
RUN chmod 755 /app/app.sh
# 4. 755, not 777

# 5. EXPOSE 22 removed (no ssh in the image)

USER nobody
# 6. run as nobody, never root

CMD ["/app/app.sh"]
