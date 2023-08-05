FROM elixir:1.15 AS build
ARG ARCH
ARG DDQ2_VERSION
ARG MIX_ENV=prod
RUN apt-get update && \
    apt-get install -y erlang-dev && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /ffmpeg
RUN wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-$ARCH-static.tar.xz && \
    tar xf ffmpeg-release-$ARCH-static.tar.xz
WORKDIR /app
ADD . .
RUN git checkout v$DDQ2_VERSION && \
    mix local.rebar --force && \
    mix local.hex --force && \
    mix deps.get && \
    mix release
WORKDIR /daidoquer2
RUN tar -xf /app/_build/prod/daidoquer2-${DDQ2_VERSION}.tar.gz && \
    rm releases/$DDQ2_VERSION/runtime.exs && \
    ln -s /app-config/runtime.exs releases/$DDQ2_VERSION/runtime.exs

FROM debian:bullseye-slim
ARG UID=1000
RUN useradd -u ${UID} ddq2
USER ${UID}
COPY --from=build /daidoquer2 /app
COPY --from=build /ffmpeg/ffmpeg-*/ffmpeg /

CMD ["bash", "-c", "env $(grep -v \"#\" /app-config/env | xargs) SHELL=/bin/bash FFMPEG_PATH=/ffmpeg /app/bin/daidoquer2 start"]
