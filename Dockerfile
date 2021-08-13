FROM crystallang/crystal:1.1.1-alpine

WORKDIR /app

# Add llvm deps.
RUN apk add --update --no-cache --force-overwrite \
  llvm10-dev llvm10-static g++

# Build crystalline.
COPY . /app/
RUN shards build crystalline --no-debug --progress --stats --production --static --release -Dpreview_mt --ignore-crystal-version
