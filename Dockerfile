ARG ALPINE_VERSION=3.15
FROM alpine:${ALPINE_VERSION}

# hadolint ignore=DL3018 # we want to keep up with latest security improvements
RUN apk add --no-cache sqlite zip tini
COPY *.sh /usr/local/bin/

ENTRYPOINT [ "/sbin/tini", "-s", "--", "/usr/local/bin/backup.sh" ]