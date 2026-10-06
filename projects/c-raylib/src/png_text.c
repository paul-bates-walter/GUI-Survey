#include "png_text.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const unsigned char PNG_SIG[8] = {137, 80, 78, 71, 13, 10, 26, 10};

static unsigned long crc32_bytes(const unsigned char *data, size_t len) {
    unsigned long crc = 0xffffffffUL;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; bit++) {
            unsigned long mask = (crc & 1UL) ? 0xedb88320UL : 0UL;
            crc = (crc >> 1) ^ mask;
        }
    }
    return (crc ^ 0xffffffffUL) & 0xffffffffUL;
}

static unsigned long read_u32be(const unsigned char *bytes) {
    return ((unsigned long)bytes[0] << 24) | ((unsigned long)bytes[1] << 16) |
           ((unsigned long)bytes[2] << 8) | (unsigned long)bytes[3];
}

static void write_u32be(unsigned char *bytes, unsigned long value) {
    bytes[0] = (unsigned char)((value >> 24) & 0xff);
    bytes[1] = (unsigned char)((value >> 16) & 0xff);
    bytes[2] = (unsigned char)((value >> 8) & 0xff);
    bytes[3] = (unsigned char)(value & 0xff);
}

static unsigned char *read_file(const char *path, size_t *out_size) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return NULL;
    }
    if (fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    unsigned char *data = malloc((size_t)size);
    if (data == NULL) {
        fclose(file);
        return NULL;
    }
    if (fread(data, 1, (size_t)size, file) != (size_t)size) {
        free(data);
        fclose(file);
        return NULL;
    }
    fclose(file);
    *out_size = (size_t)size;
    return data;
}

static bool is_png(const unsigned char *data, size_t size) {
    return size >= 8 && memcmp(data, PNG_SIG, 8) == 0;
}

int png_text_read(const char *path, PngTextEntry *entries, int max_entries) {
    size_t size = 0;
    unsigned char *data = read_file(path, &size);
    if (data == NULL || !is_png(data, size)) {
        free(data);
        return 0;
    }

    int count = 0;
    size_t offset = 8;
    while (offset + 12 <= size && count < max_entries) {
        size_t data_len = (size_t)read_u32be(data + offset);
        if (offset + 12 + data_len > size) {
            break;
        }
        const unsigned char *kind = data + offset + 4;
        const unsigned char *body = data + offset + 8;
        if (memcmp(kind, "tEXt", 4) == 0) {
            const unsigned char *split = memchr(body, 0, data_len);
            if (split != NULL) {
                size_t key_len = (size_t)(split - body);
                size_t value_len = data_len - key_len - 1;
                if (key_len >= PNG_TEXT_KEY_MAX) {
                    key_len = PNG_TEXT_KEY_MAX - 1;
                }
                if (value_len >= PNG_TEXT_VALUE_MAX) {
                    value_len = PNG_TEXT_VALUE_MAX - 1;
                }
                memcpy(entries[count].key, body, key_len);
                entries[count].key[key_len] = '\0';
                memcpy(entries[count].value, split + 1, value_len);
                entries[count].value[value_len] = '\0';
                count++;
            }
        }
        if (memcmp(kind, "IEND", 4) == 0) {
            break;
        }
        offset += 12 + data_len;
    }

    free(data);
    return count;
}

static size_t bounded_len(const char *text, size_t cap) {
    size_t len = 0;
    while (len < cap && text[len] != '\0') {
        len++;
    }
    return len;
}

static size_t append_text_chunk(unsigned char *out, const PngTextEntry *entry) {
    size_t key_len = bounded_len(entry->key, 79);
    size_t value_len = bounded_len(entry->value, PNG_TEXT_VALUE_MAX - 1);
    size_t body_len = 4 + key_len + 1 + value_len;
    write_u32be(out, (unsigned long)(body_len - 4));
    memcpy(out + 4, "tEXt", 4);
    memcpy(out + 8, entry->key, key_len);
    out[8 + key_len] = 0;
    memcpy(out + 8 + key_len + 1, entry->value, value_len);
    write_u32be(out + 4 + body_len, crc32_bytes(out + 4, body_len));
    return body_len + 8;
}

bool png_text_write(const char *path, const PngTextEntry *entries, int count) {
    size_t size = 0;
    unsigned char *data = read_file(path, &size);
    if (data == NULL || !is_png(data, size)) {
        free(data);
        return false;
    }

    size_t extra = (size_t)count * (12 + PNG_TEXT_KEY_MAX + PNG_TEXT_VALUE_MAX);
    unsigned char *out = malloc(size + extra);
    if (out == NULL) {
        free(data);
        return false;
    }

    memcpy(out, PNG_SIG, 8);
    size_t out_len = 8;
    size_t offset = 8;
    bool wrote_end = false;
    while (offset + 12 <= size) {
        size_t data_len = (size_t)read_u32be(data + offset);
        size_t total = 12 + data_len;
        if (offset + total > size) {
            break;
        }
        const unsigned char *kind = data + offset + 4;
        if (memcmp(kind, "tEXt", 4) == 0) {
            offset += total;
            continue;
        }
        if (memcmp(kind, "IEND", 4) == 0) {
            for (int i = 0; i < count; i++) {
                if (entries[i].key[0] == '\0') {
                    continue;
                }
                out_len += append_text_chunk(out + out_len, &entries[i]);
            }
        }
        memcpy(out + out_len, data + offset, total);
        out_len += total;
        if (memcmp(kind, "IEND", 4) == 0) {
            wrote_end = true;
            break;
        }
        offset += total;
    }
    free(data);

    if (!wrote_end) {
        free(out);
        return false;
    }

    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        free(out);
        return false;
    }
    bool ok = fwrite(out, 1, out_len, file) == out_len;
    fclose(file);
    free(out);
    return ok;
}
