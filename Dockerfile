FROM alpine:3.13 as crystal-builder

RUN \
  apk add --update --no-cache --force-overwrite \
  # core dependencies
  gcc gmp-dev libevent-static musl-dev pcre-dev \
  # stdlib dependencies
  libxml2-dev openssl-dev openssl-libs-static tzdata yaml-dev yaml-static zlib-static \
  # dev tools
  make git patch autoconf automake libtool wget

# Download gc patch
RUN wget \
  -O /tmp/feature-thread-stackbottom-upstream.patch \
  https://cdn.jsdelivr.net/gh/crystal-lang/distribution-scripts/linux/files/feature-thread-stackbottom-upstream.patch

# Clone and build bdgwc
ARG gc_version
ARG libatomic_ops_version
RUN git clone https://github.com/ivmai/bdwgc \
  && cd bdwgc \
  && git checkout ${gc_version} \
  && git clone https://github.com/ivmai/libatomic_ops \
  && (cd libatomic_ops && git checkout ${libatomic_ops_version}) \
  \
  && patch -p1 < /tmp/feature-thread-stackbottom-upstream.patch \
  \
  && ./autogen.sh \
  && ./configure --disable-debug --disable-shared --enable-large-config \
  && make -j$(nproc) CFLAGS=-DNO_GETCONTEXT \
  && make install

# Remove build tools from image now that libgc is built
RUN apk del -r --purge autoconf automake libtool

# Download and install crystal.
RUN \
  wget -O /tmp/crystal.tar.gz https://github.com/crystal-lang/crystal/releases/download/1.0.0/crystal-1.0.0-1-linux-x86_64.tar.gz &&\
  tar -xz -C /usr --strip-component=1  -f /tmp/crystal.tar.gz \
  --exclude */lib/crystal/lib \
  --exclude */share/crystal/src/llvm/ext/llvm_ext.o \
  --exclude */share/crystal/src/ext/libcrystal.a && \
  rm /tmp/crystal.tar.gz

# Build libcrystal
RUN \
  cd /usr/share/crystal && \
  cc -fPIC -c -o src/ext/sigfault.o src/ext/sigfault.c && \
  ar -rcs src/ext/libcrystal.a src/ext/sigfault.o

WORKDIR /app

# Add llvm deps.
RUN apk add --update --no-cache --force-overwrite \
  llvm10-dev llvm10-static g++

# Compile llvm extension.
RUN g++ -c /usr/share/crystal/src/llvm/ext/llvm_ext.cc -I/usr/lib/llvm10/include -o /usr/share/crystal/src/llvm/ext/llvm_ext.o

# Build crystalline.
COPY . /app/
RUN shards build crystalline --no-debug --progress --stats --production --static --release -Dpreview_mt --ignore-crystal-version
