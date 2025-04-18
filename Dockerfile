FROM crystallang/crystal:1.16.1-alpine

WORKDIR /app

# Add llvm deps.
RUN apk add --update --no-cache --force-overwrite \
      llvm18-dev llvm18-static g++ libxml2-static zstd-static make

# Build crystalline.
COPY . /app/

RUN git clone -b 1.16.1 --depth=1 https://github.com/crystal-lang/crystal \
      && make -C crystal llvm_ext \
      && CRYSTAL_PATH=crystal/src:lib shards build crystalline \
      --no-debug --progress --stats --production --static --release \
      -Dpreview_mt --ignore-crystal-version \
      && rm -rf crystal
