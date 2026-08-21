<img src="https://raw.githubusercontent.com/bedrock-v/.github/master/profile/bedrock-v_transparent.png" alt="The Vedrock logo" height="310" align="right">

# Vedrock

![CI](https://img.shields.io/github/actions/workflow/status/bedrock-v/Vedrock/docs.yml?branch=stable&label=CI&style=flat-square)
![Crowdin](https://img.shields.io/github/actions/workflow/status/bedrock-v/Vedrock/crowdin-download.yml?branch=stable&label=Crowdin&style=flat-square)
[![Release](https://img.shields.io/github/v/release/bedrock-v/Vedrock?include_prereleases&style=flat-square)](https://github.com/bedrock-v/Vedrock/releases)
[![License](https://img.shields.io/badge/license-GNU_Lesser_v3.0-blue?style=flat-square)](LICENSE)

A lightweight Minecraft: Bedrock Edition server software in [V](https://vlang.io/).

> [!NOTE]
> Vedrock is currently in early development. APIs, project structure and behavior may change frequently.

<br>

<a href="https://discord.gg/cM9BQsAk9D" target="_blank">
    <img src="https://discord.com/api/guilds/1520807994999439550/widget.png?style=banner2" alt="Discord Banner" align="left">
</a>

<br clear="left">

---

## Getting Started

Clone Vedrock and install its dependencies:

```bash
git clone https://github.com/bedrock-v/Vedrock.git
cd Vedrock

v install

# VPM does not currently support organization packages.
v install --git https://github.com/bedrock-v/protocol.git
v install --git https://github.com/bedrock-v/nbt.git
v install --git https://github.com/bedrock-v/nethernet.git
v install --git https://github.com/bedrock-v/webrtc-v.git
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

## Contributing

To contribute to Vedrock, you can open an issue or submit a pull request, and join the [Discord server](https://discord.gg/cM9BQsAk9D).

You can also consider reading the [documentation](https://bedrock-v.github.io/Vedrock/main.html) to learn more about the project.

For more information, see [CONTRIBUTING.md](https://github.com/bedrock-v/Vedrock/blob/stable/CONTRIBUTING.md).

## License
[GNU Lesser v3.0](./LICENSE)
