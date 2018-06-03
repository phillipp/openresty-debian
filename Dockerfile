FROM ubuntu:trusty

# Required system packages
RUN apt-get update \
    && apt-get install -y \
        wget \
        unzip \
        build-essential \
        libreadline6-dev \
        ruby-dev \
        libncurses5-dev \
        perl \
        libpcre3-dev \
        libssl-dev \
        curl

RUN gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB && \
    curl -sSL https://get.rvm.io | bash -s stable --ruby=2.3 && \
    /usr/local/rvm/wrappers/default/gem install fpm

RUN mkdir -p /build/root
WORKDIR /build

ARG OPENSSL_VERSION

RUN cd /build && \
    wget --no-verbose https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz && \
    tar zxf openssl-$OPENSSL_VERSION.tar.gz && \
    cd openssl-* && \
    wget https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/openssl-1.0/openssl-1.0-versioned-symbols.patch && \
    patch -p1 < openssl-1.0-versioned-symbols.patch && \
    wget https://raw.githubusercontent.com/chef/omnibus-software/master/config/patches/openssl/openssl-1.0.1f-do-not-build-docs.patch && \
    patch -p1 < openssl-1.0.1f-do-not-build-docs.patch && \
    ./config --prefix=/opt/openssl-$OPENSSL_VERSION --openssldir=/opt/openssl-$OPENSSL_VERSION shared no-idea no-mdc2 no-rc5 no-zlib enable-tlsext no-ssl2 && \
    make depend && \
    make install && \
    cd .. && rm -rf openssl-*

ARG DEB_MAJOR
ARG DEB_MINOR
ARG DEB_VERSION

# Download packages
RUN wget https://openresty.org/download/openresty-$DEB_VERSION.tar.gz \
    && tar xfz openresty-$DEB_VERSION.tar.gz

ARG DEB_PACKAGE

ADD patches/* /tmp/patches/

# Compile and install openresty
RUN cd /build/openresty-$DEB_VERSION \
    && patch -p1 bundle/nginx-$DEB_MAJOR/src/http/modules/ngx_http_static_module.c < /tmp/patches/openresty-static.patch \
    && patch -p1 bundle/nginx-$DEB_MAJOR/src/http/modules/ngx_http_upstream_keepalive_module.c < /tmp/patches/nginx-upstream-ka-pooling.patch \
    && PKG_CONFIG_PATH="/opt/openssl-$OPENSSL_VERSION/lib/pkgconfig" ./configure \
        --prefix=/usr/share/nginx \
        -j6 \
        --with-cc-opt="-I/opt/openssl-$OPENSSL_VERSION/include" \
        --with-ld-opt="-L/opt/openssl-$OPENSSL_VERSION/lib -Wl,-rpath,/opt/openssl-$OPENSSL_VERSION/lib" \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-client-body-temp-path=/var/lib/nginx/body \
        --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
        --http-log-path=/var/log/nginx/access.log \
        --http-proxy-temp-path=/var/lib/nginx/proxy \
        --http-scgi-temp-path=/var/lib/nginx/scgi \
        --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
        --lock-path=/var/lock/nginx.lock \
        --pid-path=/run/nginx.pid \
        --with-pcre-jit \
        --with-debug \
        --with-http_addition_module \
        --with-http_gzip_static_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_stub_status_module \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-ipv6 \
    && make -j8 \
    && make install DESTDIR=/build/root

COPY scripts/* nginx-scripts/
COPY conf/* nginx-conf/

# Add extras to the build root
RUN cd /build/root \
    && mkdir \
        etc/init \
        etc/logrotate.d \
        var/lib \
        var/lib/nginx \
        usr/sbin \
        opt \
    && mv usr/share/nginx/nginx/sbin/nginx usr/sbin/nginx && rm -rf usr/share/nginx/nginx/sbin \
    && mv usr/share/nginx/nginx/html usr/share/nginx/html && rm -rf usr/share/nginx/nginx \
    && mv /opt/openssl-$OPENSSL_VERSION opt \
    && rm -rf etc/nginx \
    && cp /build/nginx-scripts/upstart.conf etc/init/nginx.conf \
    && cp /build/nginx-conf/logrotate etc/logrotate.d/nginx

# Build deb
RUN /usr/local/rvm/wrappers/default/fpm -s dir -t deb \
    -n openresty \
    -v $DEB_VERSION-$DEB_PACKAGE \
    -C /build/root \
    -p openresty_VERSION_ARCH.deb \
    --description 'a high performance web server and a reverse proxy server' \
    --url 'http://openresty.org/' \
    --category httpd \
    --maintainer 'Phillipp Röll <phillipp.roell@trafficplex.de>' \
    --depends wget \
    --depends unzip \
    --depends libncurses5 \
    --depends libreadline6 \
    --deb-build-depends build-essential \
    --replaces 'nginx-full' \
    --provides 'nginx-full' \
    --conflicts 'nginx-full' \
    --replaces 'nginx-common' \
    --provides 'nginx-common' \
    --conflicts 'nginx-common' \
    --after-install nginx-scripts/postinstall \
    --before-install nginx-scripts/preinstall \
    --after-remove nginx-scripts/postremove \
    --before-remove nginx-scripts/preremove \
    etc run usr var opt
