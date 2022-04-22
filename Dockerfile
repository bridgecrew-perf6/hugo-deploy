FROM ubuntu:20.04

RUN apt-get update && apt-get install -y git curl && rm -rf /var/apt/* && rm -rf /var/cache/apt/*

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
