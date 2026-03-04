# zigmcdata

zigmcdata is a code generation tool written in Zig that extracts and converts
Minecraft server data into Zig source files.

Given a Minecraft version, it downloads, extracts, and parses
the relevant server data and generates Zig code. It also supports:
- Language constants
- Tag definitions

The generated files can be used directly in Zig projects.
---

## Requirements

- Zig 0.15.2
- Internet connection (for first-time version download)

---

## Usage

`zig run src/main.zig -- <version> <output_dir> <tmp_dir>`


Arguments:


`<version>` Minecraft version (e.g. 1.20.4)
`<output_dir>` Directory where Zig files will be generated
`<tmp_dir>` Temporary directory used for downloaded and extracted data


Example:


`zig run src/main.zig -- 1.20.4 ./generated ./tmp`


After that, you can use it as a build dependency like so:
```
        .mcgen = .{
            .url = "./mcgen",
            .hash = "...",
        },
```

Or...

TODO



---

## How It Works

1. Creates or opens a temporary `json` directory.
2. If empty:
   - Downloads and extracts the Minecraft server for the requested version.
3. Reads:
   - `assets/minecraft/lang/en_us.json`
   - `data/minecraft/*`
4. Generates Zig source files in the output directory.

---

## License

MIT see LICENSE


