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
