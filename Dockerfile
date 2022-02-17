ARG ALPINE_VERSION=3.15
FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache sqlite zip tini
ADD *.sh /usr/local/bin/

ENTRYPOINT [ "/sbin/tini", "--", "/usr/local/bin/backup.sh" ]