# Elixir 1.16 is required based on systemd file: /opt/elixir-1.16/bin/mix
FROM hexpm/elixir:1.16.2-erlang-26.2.3-alpine-3.19.1 AS build

# Install build dependencies
RUN apk add --no-cache build-base npm git python3

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Copy the rest of the application
COPY lib lib
# (If there are other folders like priv, config, copy them. Based on ls, only lib exists)

# Compile the project
RUN mix compile

# Start a new stage for a leaner image
FROM hexpm/elixir:1.16.2-erlang-26.2.3-alpine-3.19.1

RUN apk add --no-cache libstdc++ ncurses-libs

WORKDIR /app

# Set runtime ENV
ENV MIX_ENV=prod
ENV PORT=4001

COPY --from=build /app/_build ./_build
COPY --from=build /app/mix.exs ./mix.exs
COPY --from=build /app/mix.lock ./mix.lock
COPY --from=build /app/deps ./deps
COPY --from=build /app/lib ./lib
COPY --from=build /root/.mix /root/.mix

# Expose the application port
EXPOSE 4001

# Run the bridge
CMD ["mix", "run", "--no-halt"]
