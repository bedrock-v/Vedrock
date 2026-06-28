
<p align="center">
    <a href="https://github.com/bedrock-v/Vedrock/">
        <img src="https://raw.githubusercontent.com/bedrock-v/.github/master/profile/bedrock-v_gradient.png" alt="Vedrock" width="320">
    </a>
</p>

# Vedrock

A Minecraft: Bedrock Edition server software written in V.

## Building from source

### Prerequisites

- [V](https://vlang.io/)
- [nbt](https://github.com/bedrock-v/nbt)
- [raknet](https://github.com/bedrock-v/raknet)
- [protocol](https://github.com/bedrock-v/protocol)

```bash
git clone https://github.com/bedrock-v/nbt ~/.vmodules/nbt
git clone https://github.com/bedrock-v/protocol ~/.vmodules/protocol 
git clone https://github.com/bedrock-v/raknet ~/.vmodules/raknet

HTTPS: git clone https://github.com/bedrock-v/Vedrock.git
SSH: git@github.com:bedrock-v/Vedrock.git
CLI: gh repo clone bedrock-v/Vedrock
cd Vedrock
v run . (to temp run) / v . (to build)
```

## Contributing
