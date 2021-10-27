FROM --platform=$TARGETPLATFORM alpinelinux/docker-cli as prepare
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG MAXMIND_LICENSE_KEY

RUN mkdir /GeoLite2/
WORKDIR /GeoLite2/

ENV MAXMIND_BASE_URL "https://download.maxmind.com/app/geoip_download?license_key=$MAXMIND_LICENSE_KEY&"

RUN wget "${MAXMIND_BASE_URL}edition_id=GeoLite2-ASN&suffix=tar.gz" -O GeoLite2-ASN.tar.gz
RUN wget "${MAXMIND_BASE_URL}edition_id=GeoLite2-ASN&suffix=tar.gz.sha256" -O GeoLite2-ASN.tar.gz.sha256
RUN sed 's/GeoLite2-ASN_[0-9]*.tar.gz/GeoLite2-ASN.tar.gz/g' -i GeoLite2-ASN.tar.gz.sha256
RUN sha256sum -c GeoLite2-ASN.tar.gz.sha256
RUN tar xvf GeoLite2-ASN.tar.gz --strip 1

RUN wget "${MAXMIND_BASE_URL}edition_id=GeoLite2-Country&suffix=tar.gz" -O GeoLite2-Country.tar.gz
RUN wget "${MAXMIND_BASE_URL}edition_id=GeoLite2-Country&suffix=tar.gz.sha256" -O GeoLite2-Country.tar.gz.sha256
RUN sed 's/GeoLite2-Country_[0-9]*.tar.gz/GeoLite2-Country.tar.gz/g' -i GeoLite2-Country.tar.gz.sha256
RUN sha256sum -c GeoLite2-Country.tar.gz.sha256
RUN tar xvf GeoLite2-Country.tar.gz --strip 1


FROM --platform=$TARGETPLATFORM alpinelinux/docker-cli as release
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG PACKAGE_MIRROR
ARG build_deps="build-base ncurses-dev autoconf automake git gettext-dev"
ARG runtime_deps="tini ncurses libintl gettext musl-utils libmaxminddb libmaxminddb-dev "
ARG geolib_path="/usr/local/share/GeoIP"
ARG geolib_filename="GeoCity.dat"

ENV CONTAINER_NAME=

RUN if [[ -n "$PACKAGE_MIRROR" ]]; then sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories; fi
WORKDIR $geolib_path
COPY --from=prepare /GeoLite2/*.mmdb $geolib_path

RUN ls -l $geolib_path

RUN set -eux; \
    \
    mv $geolib_path/GeoLite2-Country.mmdb $geolib_path/$geolib_filename; \
    apk upgrade --no-cache; \
    apk add -u --no-cache --virtual .build-deps \
        $build_deps \
        $runtime_deps \
    ;\
    git clone https://github.com/allinurl/goaccess /goaccess; \
    cd /goaccess; \
    autoreconf -fiv; \
    ./configure --enable-utf8 --enable-geoip=mmdb; \
    make; \
    make install; \
    apk add --no-cache --no-network --virtual .run-deps\
        $runtime_deps \
    ; \
    apk del --no-network .build-deps; \
    rm -rf /var/cache/apk/* /tmp/goaccess/* /goaccess; \
    ldconfig /


VOLUME /srv/data
VOLUME /srv/report
VOLUME /srv/log

EXPOSE 7890

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["docker", "logs", "-f", "$CONTAINER_NAME", "|", "goaccess", "--no-global-config", "--real-time-html" "--log-format=COMBINED", "-"]