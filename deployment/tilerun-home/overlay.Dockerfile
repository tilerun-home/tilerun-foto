ARG BASE_IMAGE=ghcr.io/tilerun-home/tilerun-foto-server:bootstrap
FROM ${BASE_IMAGE}

ADD server-dist.tar.gz /usr/src/app/server/dist/
ADD web-build.tar.gz /build/www/

ENV IMMICH_BUILD=local-validation \
    IMMICH_BUILD_IMAGE=tilerun-foto-server:local-validation \
    IMMICH_SOURCE_REF=local-validation \
    IMMICH_SOURCE_COMMIT=unpublished
