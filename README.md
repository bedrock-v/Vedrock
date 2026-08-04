<p align="center">
    <a href="https://github.com/bedrock-v/Vedrock/">
        <img src="https://raw.githubusercontent.com/bedrock-v/.github/master/profile/bedrock-v_gradient.png" alt="Vedrock" width="210">
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

## Getting Started

Clone Vedrock and install its dependencies:

```bash
git clone https://github.com/bedrock-v/Vedrock.git
cd Vedrock

v install

# VPM does not currently support organization packages.
v install --git https://github.com/bedrock-v/protocol.git
v install --git https://github.com/bedrock-v/nbt.git
v install --git https://github.com/bedrock-v/raknet.git
```

You can develop a server directly inside the cloned repository or place one or more projects beneath it:

```text
Vedrock/
├── server/
└── examplemc/
```

V resolves Vedrock modules from the parent directory in this layout.

To use Vedrock from projects located elsewhere, clone it into your V modules path:

```bash
git clone https://github.com/bedrock-v/Vedrock.git \
  "$VMODULES_PATH/bedrockv/vedrock"
```

Vedrock modules can then be imported normally from any V project. (via bedrockv.vedrock.*)

## Development

To contribute to Vedrock, you can open an issue or submit a pull request, and join the [Discord server](https://discord.gg/cM9BQsAk9D).

You can also consider reading the [documentation](https://bedrock-v.github.io/Vedrock/main.html) to learn more about the project.

For more information, see [CONTRIBUTING.md](https://github.com/bedrock-v/Vedrock/blob/stable/CONTRIBUTING.md).
