FROM 84codes/crystal:1.10.0-alpine

WORKDIR /app

# Add llvm deps.
RUN apk add --update --no-cache --force-overwrite \
      llvm15-dev llvm15-static g++ libxml2-static

# Build crystalline.
COPY . /app/

RUN shards build crystalline \
      --no-debug --progress --stats --production --static --release \
      -Dpreview_mt --ignore-crystal-version
