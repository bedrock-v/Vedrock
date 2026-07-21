<p align="center">
    <a href="https://github.com/bedrock-v/Vedrock/">
        <img src="https://raw.githubusercontent.com/bedrock-v/.github/master/profile/bedrock-v_gradient.png" alt="Vedrock" width="320">
    </a>
</p>

# Vedrock

A lightweight Minecraft: Bedrock Edition server software written in [V](https://vlang.io/).

> [!NOTE]
> Vedrock is currently in early development. APIs, project structure and behavior may change frequently.

Feel free to join our Discord community!

<p align="center">
    <a href="https://discord.gg/cM9BQsAk9D" target="_blank">
        <img src="https://discord.com/api/guilds/1520807994999439550/widget.png?style=banner2" alt="Discord Banner"/>
    </a>
</p>

## Building from source

### Prerequisites

* [V](https://vlang.io/)
* [leveldb](https://github.com/vlang/leveldb)
* [nbt](https://github.com/bedrock-v/nbt)
* [raknet](https://github.com/bedrock-v/raknet)
* [protocol](https://github.com/bedrock-v/protocol)
* [i18n](https://github.com/nepinhum/i18n)

Some modules aren't available through VPM yet. Until they're published, clone them manually into your V modules directory.

The V modules directory is usually:

* Linux/macOS: `~/.vmodules`
* Windows: `%USERPROFILE%\.vmodules`

```bash
git clone https://github.com/vlang/leveldb VMODULES_PATH/leveldb
git clone https://github.com/bedrock-v/nbt VMODULES_PATH/nbt
git clone https://github.com/bedrock-v/protocol VMODULES_PATH/protocol
git clone https://github.com/bedrock-v/raknet VMODULES_PATH/raknet

v install nepinhum.i18n
```

### Clone Vedrock

```bash
git clone https://github.com/bedrock-v/Vedrock.git
```

### Run or build

```bash
cd Vedrock

# Run without keeping a binary
v run .

# Build
v .
```

## Running with Docker

The Dockerfile builds everything from source - the pinned V compiler, all module dependencies and the server itself. No local V setup is required.

```bash
# Build the image
docker build -t vedrock .

# Run the server
docker run -d --name vedrock -p 19132:19132/udp vedrock
```

Or with Docker Compose:

```bash
docker compose up -d
```

The compose setup mounts `worlds/`, `players/` and `vedrock.yml` from the repository root so world data and configuration persist across container restarts.

## Contributing

Contributions are welcome.

You can contribute by opening issues, reporting bugs, suggesting improvements, improving documentation or submitting pull requests.

Before opening a pull request, please make sure your changes are focused and easy to review. If you want to work on a larger change, opening an issue first is recommended so the design can be discussed before implementation.

By participating in this project, you are expected to follow the bedrock-v Code of Conduct.

You can also read [this](https://github.com/bedrock-v/.github/blob/master/profile/README.md).
