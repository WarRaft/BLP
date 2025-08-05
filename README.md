# BLP — Format Specification

**BLP** stands for **Blizzard Picture** — a proprietary image format developed by **Blizzard Entertainment**.  
It is used in **Warcraft III** and **World of Warcraft** to store textures with support for compression, mipmaps, and
alpha channels.

There is no official documentation provided by Blizzard.

All existing knowledge about the format comes from a wide range of absolutely legitimate sources.  
**No reverse engineering was involved. Absolutely none. Seriously.**

Available resources:

- [Hive Workshop — BLP Specifications (WC3)](https://www.hiveworkshop.com/threads/blp-specifications-wc3.279306)
- [Wowpedia — BLP files](https://wowpedia.fandom.com/wiki/BLP_files)
- [Wowwiki (archive) — BLP file](https://wowwiki-archive.fandom.com/wiki/BLP_file)
- [Wowdev Wiki — BLP](https://wowdev.wiki/BLP)

# [blp-rs](https://github.com/WarRaft/blp-rs)

Through our efforts, reading and writing the BLP format has been completely reimagined.  
All the pain, quirks, and edge cases of the format — captured, handled, and buried here.

This repository is the definitive implementation for working with BLP files.  
Fast, accurate, and battle-tested. Nothing else comes close.

## Specification

Instead of hand-waving descriptions, this repository provides a clear, deterministic specification of the BLP format —
written in the pattern language of [ImHex](https://github.com/WerWolv/ImHex), a powerful hex editor for reverse
engineers and developers.

Pattern files are executable descriptions: they define the actual layout of bytes, conditionals, enums, arrays,
offsets — not vague ideas.

The language is documented here:

- [Pattern Language — Core Syntax](https://docs.werwolv.net/pattern-language/core-language)

With ImHex, you can load any `.blp` file, apply the pattern, and instantly see its structure. That’s how real formats
are understood.

```cpp
#pragma description Warcraft.w3i
#pragma endian little
#pragma array_limit 999999

import std.io;
import std.mem;
import std.string;
import std.core;

enum Version : u32 {
    BLP0 = 0x424C5030, // BLP0
    BLP1 = 0x424C5031, // BLP1
    BLP2 = 0x424C5032, // BLP2
};

enum TextureType: u32 {
    JPEG = 0,
    DIRECT = 1,
};

struct Header {
    be Version version;
    TextureType texture_type; // Texture type: 0 = JPG, 1 = S3TC

    if (version >= Version::BLP2) {
        u8 encoding_type; // not documented
        u8 alpha_bits;    // 0, 1, 4, or 8
        u8 alpha_type;    // 0, 1, 7, or 8
        u8 has_mipmaps;   // 0 = no mips levels, 1 = has mips (number of levels determined by image size)
    } else {
        u32 alpha_bits;
    }

    u32 width;  // Image width in pixels
    u32 height; // Image height in pixels

    if (version <= Version::BLP1) {
        u32 extra;
        u32 has_mipmaps;
    }

    if (version >= Version::BLP1) {
        u32 mipmap_offsets[16]; // The file offsets of each mipmap, 0 for unused
        u32 mipmap_lengths[16]; // The length of each mipmap data block
    }
};

s32 index = -1;

struct Mipmap {
    index += 1;
    u32 offset = parent.parent.header.mipmap_offsets[index];
    u32 length = parent.parent.header.mipmap_lengths[index];

    if (offset > 0 && length > 0) {
        u8 data[length] @ offset;
    }
};

struct JpegData {
    u32 jpegHeaderSize;
    u8 jpegHeaderChunk[jpegHeaderSize];
    Mipmap mipmap[16];
};

struct DirectData {
    u32 palette[256];
    Mipmap mipmap[16];
};

struct Data {
    Header header;

    match (header.texture_type) {
        (TextureType::JPEG): JpegData data;
        (TextureType::DIRECT): DirectData data;
    }
};

Data data @ 0x0;
```

## Detailed Explanation

Before diving into the parsing process, it’s important to properly prepare for the task ahead.  
Make yourself a strong cup of coffee, pick a decent selection of cookies, and open your editor with the right mindset.

Once you're ready, the initial setup looks like this:

```cpp
#pragma description Warcraft.w3i
#pragma endian little
#pragma array_limit 999999

import std.io;
import std.mem;
import std.string;
import std.core;
```

The most important line in this section is:

```cpp
#pragma endian little
```

It sets the default byte order for all parsed values to Little Endian, which matches how BLP files are laid out in
practice.

Unless explicitly overridden, every multi-byte value — integers, arrays, enums — is read in little-endian order.
When a field is meant to be Big Endian, it’s marked with the be prefix in the pattern language, like this:

```cpp
be u32 value;
```

But for BLP, almost everything is little-endian by default — and that’s exactly how we like it.

### File Entry Point and Overall Structure

Parsing begins at byte `0x00`. No magic. No padding.  
The entire file is read linearly and deterministically into a single root structure:

```cpp
struct Data {
    Header header;

    match (header.texture_type) {
        (TextureType::JPEG): JpegData data;
        (TextureType::DIRECT): DirectData data;
    }
};

Data data @ 0x0;
```

This is the entry point. Everything that follows — palettes, mipmaps, JPEG headers — is conditionally parsed based on
the fields in Header.
The structure is flat, explicit, and entirely self-describing.

### Header — The Axis of All Parsing

The `Header` defines the fundamental shape of the file and dictates how the rest of the data should be interpreted.  
Every branch, every conditional path — it all begins here.

```cpp
enum Version : u32 {
    BLP0 = 0x424C5030, // BLP0
    BLP1 = 0x424C5031, // BLP1
    BLP2 = 0x424C5032, // BLP2
};

enum TextureType: u32 {
    JPEG = 0,
    DIRECT = 1,
};

struct Header {
    be Version version;
    TextureType texture_type; // 0 = JPG, 1 = S3TC (or "Direct")

    if (version >= Version::BLP2) {
        u8 encoding_type; // undocumented
        u8 alpha_bits;    // 0, 1, 4, or 8
        u8 alpha_type;    // 0, 1, 7, or 8
        u8 has_mipmaps;   // 0 = none, 1 = presence inferred from size
    } else {
        u32 alpha_bits;
    }

    u32 width;
    u32 height;

    if (version <= Version::BLP1) {
        u32 extra;
        u32 has_mipmaps;
    }

    if (version >= Version::BLP1) {
        u32 mipmap_offsets[16]; // Offset of each mipmap
        u32 mipmap_lengths[16]; // Length of each mipmap
    }
};
```

The version field is big-endian — it’s not a mistake, it’s a legacy quirk, and the only field in the entire header read
as be.

From here, parsing branches depending on the version and texture_type, guiding the rest of the file down distinct paths:
JPEG-based or direct pixel data.

The structure is not just metadata — it is the blueprint for everything that follows.

### Final Stage — Extract Paths and Mipmaps

At this point, the file diverges into two data extraction paths — `JpegData` and `DirectData`.  
These branches serve only to set up decoding: one provides a JPEG header, the other a palette.

After that, both paths converge again — into a unified mipmap-reading routine.

```cpp
s32 index = -1;

struct Mipmap {
    index += 1;
    u32 offset = parent.parent.header.mipmap_offsets[index];
    u32 length = parent.parent.header.mipmap_lengths[index];

    if (offset > 0 && length > 0) {
        u8 data[length] @ offset;
    }
};

struct JpegData {
    u32 jpegHeaderSize;
    u8 jpegHeaderChunk[jpegHeaderSize];
    Mipmap mipmap[16];
};

struct DirectData {
    u32 palette[256];
    Mipmap mipmap[16];
};
```

The preparation step differs — a header chunk vs. a color palette — but the actual extraction of image data is
structurally identical.
This is where raw bytes become pixels.

### Final Notes — Chaos, Powers of Two, and Where to Look

There are no guarantees about the order, alignment, or presence of mipmaps in a BLP file.  
Offsets can be non-contiguous. Some levels may be missing. Others may contain garbage or duplicate data.

By convention, mipmap dimensions are computed as powers of two — starting from the full image size and halving each side
down to 1:

```
Level 0: width x height
Level 1: (width / 2) x (height / 2)
...
Level N: at least 1 x 1
```

But the format itself doesn’t enforce this. It only provides up to 16 offsets and lengths.  
What actually gets stored, and where, is up to the exporter.

---

For a full understanding of how mipmaps, compression, alpha bits, and decoding all come together —  
we invite you to read the source code of [**blp-rs**](https://github.com/WarRaft/blp-rs),  
a complete implementation written with care, spite, and an unreasonable attention to edge cases.

Happy parsing.

<p align="center">
  <img src="https://raw.githubusercontent.com/WarRaft/BLP/refs/heads/main/preview/logo.png" alt="BLP"/>
</p>
