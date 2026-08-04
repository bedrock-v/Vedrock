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

To get started with Vedrock, clone the repository and follow the installation instructions.

```bash
git clone https://github.com/bedrock-v/Vedrock.git
cd Vedrock

v install # for i18n
# VPM doesn't support organizations for now
v install --git https://github.com/bedrock-v/protocol.git
v install --git https://github.com/bedrock-v/nbt.git
v install --git https://github.com/bedrock-v/raknet.git

v run main.v # run the server (example)
```

## Development

To contribute to Vedrock, you can open an issue or submit a pull request, and join the [Discord server](https://discord.gg/cM9BQsAk9D).

You can also consider reading the [documentation](https://bedrock-v.github.io/Vedrock/main.html) to learn more about the project.

For more information, see [CONTRIBUTING.md](https://github.com/bedrock-v/Vedrock/blob/stable/CONTRIBUTING.md).
