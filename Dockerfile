FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    git make gcc libc6-dev libssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG V_COMMIT=0c3183c
ARG VC_COMMIT=f461dfeb

RUN git clone https://github.com/vlang/v /opt/v \
    && git -C /opt/v checkout ${V_COMMIT} \
    && git clone https://github.com/vlang/vc /opt/v/vc \
    && git -C /opt/v/vc checkout ${VC_COMMIT} \
    && git clone --depth 1 --branch thirdparty-linux-amd64 https://github.com/vlang/tccbin /opt/v/thirdparty/tcc \
    && make -C /opt/v local=1 \
    && ln -s /opt/v/v /usr/local/bin/v

ARG NBT_COMMIT=48ba491
ARG RAKNET_COMMIT=10901e3
ARG PROTOCOL_COMMIT=9d54e57
ARG LEVELDB_COMMIT=38c6dfc

RUN mkdir -p /opt/deps /root/.vmodules \
    && git clone https://github.com/bedrock-v/nbt /opt/deps/nbt \
    && git -C /opt/deps/nbt checkout ${NBT_COMMIT} \
    && git clone https://github.com/bedrock-v/raknet /opt/deps/raknet \
    && git -C /opt/deps/raknet checkout ${RAKNET_COMMIT} \
    && git clone https://github.com/bedrock-v/protocol /opt/deps/protocol \
    && git -C /opt/deps/protocol checkout ${PROTOCOL_COMMIT} \
    && git clone https://github.com/vlang/leveldb /opt/deps/leveldb \
    && git -C /opt/deps/leveldb checkout ${LEVELDB_COMMIT} \
    && ln -s /opt/deps/nbt /root/.vmodules/nbt \
    && ln -s /opt/deps/raknet /root/.vmodules/raknet \
    && ln -s /opt/deps/raknet/message /root/.vmodules/message \
    && ln -s /opt/deps/protocol/src /root/.vmodules/protocol \
    && ln -s /opt/deps/leveldb /root/.vmodules/leveldb \
    && v install nepinhum.i18n

WORKDIR /build
COPY . .
RUN v -prod . -o vedrock

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /build/vedrock ./vedrock
COPY --from=build /build/data ./data
COPY --from=build /build/lang ./lang

EXPOSE 19132/udp
VOLUME ["/app/worlds", "/app/players"]

CMD ["./vedrock"]
