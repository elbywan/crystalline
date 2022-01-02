FROM crystallang/crystal:1.2.2-alpine

WORKDIR /app

# Add llvm deps.
RUN apk add --update --no-cache --force-overwrite \
      llvm10-dev llvm10-static g++ make

# Build crystalline.
COPY . /app/

RUN git clone -b 1.2.2 --depth=1 https://github.com/crystal-lang/crystal \
      && make -C crystal llvm_ext \
      && CRYSTAL_PATH=crystal/src:lib shards build crystalline \
          --no-debug --progress --stats --production --static --release \
          -Dpreview_mt --ignore-crystal-version \
      && rm -rf crystal
