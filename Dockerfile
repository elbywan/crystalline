FROM alpine:edge as builder

WORKDIR /app

RUN apk add --no-cache \
  crystal \
  shards \
  musl-dev \
  libxml2-dev \
  openssl-dev \
  openssl-libs-static \
  tzdata \
  yaml-dev \
  yaml-static \
  zlib-static \
  llvm10-dev \
  llvm10-static \
  g++

COPY . /app/

RUN g++ -c /usr/lib/crystal/core/llvm/ext/llvm_ext.cc -I/usr/lib/llvm10/include -o /usr/lib/crystal/core/llvm/ext/llvm_ext.o
RUN shards build crystalline --no-debug --progress --stats --production --static --release
