#ifndef UTILS
#define UTILS

#include "../cimgui/cimgui.h"
#include "../sokol/sokol_app.h"
#include "../sokol/sokol_gfx.h"
#include "../sokol/sokol_glue.h"
#include "../sokol/sokol_imgui.h"
#include "../sokol/sokol_log.h"
#include <float.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "core.h"

#define BASE_ADDRESS     0x70000000
#define ADDRESS_HEX_LEN    8
#define COMMAND_LEN       16

#define _max(a, b) ((a) > (b) ? (a) : (b))
#define _min(a, b) ((a) < (b) ? (a) : (b))

_Thread_local char str_buf[256]      = {'\0'};
_Thread_local char str_buf2[256]      = {'\0'};
_Thread_local char read_cmd_buf[17]  = "mdw 0x........\r\n";

void assert_true(bool assertion, char *msg) {
    if (!assertion) {
        printf("%s\n", msg);
        exit(EXIT_FAILURE);
    }
}

static int binary_filter(ImGuiInputTextCallbackData* data)
{
    if (data->EventChar == '0' || data->EventChar == '1') {
        return 0; // accept
    }
    return 1; // reject
}

char bin_buf[65] = {};
char* binary_print(u64 val)
{
    bin_buf[64] = '\0';
    i32 pos = 63;
    while (val != 0 || pos == 63) {
        bin_buf[pos] = (val & 1) ? '1' : '0';
        pos -= 1;
        val >>= 1;
    }
    return &bin_buf[pos + 1];
}

u64 parse_hex_unsafe(char* hex, u32 len) {
    u64 res = 0;
    u64 shift = 0;
    for (i32 i = len; i >= 0; i -= 1) {

        // convert A-F to a-f
        if (hex[i] >= 65 && hex[i] < 71 ) {
            hex[i] += 32;
        }

        // look at that beauty
        u64 val = (u64)_min(((u32)hex[i]) - 48, ((u32)hex[i]) - 87);
        res += val << shift;
        shift += 4;
    }
    return res;
}

bool parse_hex(char* hex, u64* res, u32 len) {
    assert_true(hex[len] == '\0', "length of hex string not correct");
    *res = 0;
    u64 shift = 0;

    for (i32 i = 0; i < len; i += 1) {
        if ((u32)hex[i] == '\0') {
            return true;
        }
        bool is_number = ((u32)hex[i] >= 48) && ((u32)hex[i] <= 57);
        bool is_letter = (u32)hex[i] >= 87 && (u32)hex[i] <= 102;
        if (!is_number && !is_letter) {
            return false;
        }
    }
    *res = parse_hex_unsafe(hex, len);
    return true;
}

void parse_hex_len_unknown(char* hex, u64* res) {
    *res = 0;

    for (i32 i = 0; i < 17; i += 1) {
        if ((u32)hex[i] == '\0') {
            *res = parse_hex_unsafe(hex, i - 1);
            return;
        }
    }
}

void to_hex_string_thread_safe(u32 val, u32 out_size, char* buf) {
    assert_true(out_size <= 16, "can only convert hex strings up to size 16");
    for (i32 i = 0; i < out_size; i += 1) {
        if ((val & 0b1111) > 9) {
            buf[out_size - i - 1] = (val & 0b1111) + 87;
        } else {
            buf[out_size - i - 1] = (val & 0b1111) + 48;
        }
        val >>= 4;
    }
    buf[out_size] = '\0';
}

u64 parse_dec_unsafe(char* dec, u32 len) {
    u64 res = 0;
    u64 pot = 1;
    for (i32 i = len; i >= 0; i -= 1) {
        res += (dec[i] - 48) * pot;
        pot *= 10;
    }
    return res;

}
void parse_dec_len_unknown(char* dec, u64* res) {
    *res = 0;

    for (i32 i = 0; i < 21; i += 1) {
        if ((u32)dec[i] == '\0') {
            *res = parse_dec_unsafe(dec, i - 1);
            return;
        }
    }
}

u64 parse_bin_unsafe(char* bin, u32 len) {
    u64 res = 0;
    u64 shift = 0;
    for (i32 i = len; i >= 0; i -= 1) {
        res += (bin[i] - 48) << shift;
        shift += 1;
    }
    return res;
}

void parse_bin_len_unknown(char* bin, u64* res) {
    *res = 0;

    for (i32 i = 0; i < 65; i += 1) {
        if ((u32)bin[i] == '\0') {
            *res = parse_bin_unsafe(bin, i - 1);
            return;
        }
    }
}


// this function computes a hex address for the logic analyzer
// and inserts exactly 8 address-chars into the given buffer
// [16 bits base_addr | 5 bits ctrl_sel | 9 bits ring_addr | 2 bits padding]
void insert_char_address(char* buf, u32 ctrl_sel, u32 ring_addr, bool read) {
    u32 mapped_addr = BASE_ADDRESS;
    if (read) {
        mapped_addr |= ctrl_sel << 11;
        mapped_addr |= ring_addr << 2;
    } else {
        mapped_addr |= ctrl_sel << 2;
    }
    for (i32 i = 0; i < ADDRESS_HEX_LEN; i += 1) {
        if ((mapped_addr & 0b1111) > 9) {
            buf[ADDRESS_HEX_LEN - i - 1] = (mapped_addr & 0b1111) + 87;
        } else {
            buf[ADDRESS_HEX_LEN - i - 1] = (mapped_addr & 0b1111) + 48;
        }
        mapped_addr >>= 4;
    }
}

f32 nr_right_align(u64 nr, Data_Format fmt) {
    f32 spacing = 2;
    f32 nr_chars = 0;
    if (fmt == Hex) {
        while (nr > 0) {
            nr_chars += 1;
            nr >>= 4;
        }
    }
    if (fmt == Dec) {
        while (nr > 0) {
            nr_chars += 1;
            nr /= 10;
        }
    }
    if (fmt == Bin) {
        while (nr > 0) {
            nr_chars += 1;
            nr >>= 1;
        }
    }
    nr_chars = _max(1, nr_chars);
    return - nr_chars * 7 - spacing;
    assert(1 == 2);
}

i32 read_entire_file(char* file_name, char** buf_ptr) {
    FILE* file = fopen(file_name, "rb");
    if (file == NULL) {
        return -1;
    }

    if (fseek(file, 0L, SEEK_END) != 0) {
        printf("could not seek end of file\n");
        return -1;
    }
    i32 numbytes = ftell(file);
    if (numbytes < 0) {
        return -1;
    }
    fseek(file, 0L, SEEK_SET);  
     
    *buf_ptr = (char*)malloc(numbytes + 1); 
     
    if(*buf_ptr == NULL) {
        return -1;
    }
     
    i32 read_size = fread(*buf_ptr, sizeof(char), numbytes, file);
    if (read_size != numbytes) {
        printf("error reading file\n");
        return -1;
    }
    (*buf_ptr)[numbytes] = '\0';

    fclose(file);
    return numbytes;
}

bool has_trigger(State* state, i32 trig) {
    for (i32 s = 0; s < state->nr_signals; s += 1) {
        if (state->signals[s].use_in_trigger[trig]) {
            return true;
        }
    }
    return false;
}

bool trigger_signals_overlap(i32 s, State* state) {

    // skip if signal not used in trigger
    bool* use = state->signals[s].use_in_trigger;
    if (!use[0] && !use[1] && !use[2] && !use[3]) {
        return false;
    }

    for (i32 i = 0; i < state->nr_signals; i += 1) {
        if (i == s) { continue; }

        // skip if signal not used in trigger
        bool* use_other = state->signals[i].use_in_trigger;
        if (!(use[0] & use_other[0]) && !(use[1] & use_other[1]) &&
            !(use[2] & use_other[2]) && !(use[3] & use_other[3])) {
            continue;
        }

        // overlap check
        if (state->signals[s].lsb <= state->signals[i].msb && state->signals[s].msb >= state->signals[i].lsb) {
            return true;
        }
    }
    return false;
}

bool signals_overlap(i32 s, State* state) {
    for (i32 i = 0; i < state->nr_signals; i += 1) {
        if (i == s) { continue; }
        if (state->signals[s].lsb <= state->signals[i].msb && state->signals[s].msb >= state->signals[i].lsb) {
            return true;
        }
    }
    return false;
}

void hex_upper_bound(u64 bit_width, char* val) {
    char dest[17];
    u64 upper_bound = bit_width == 64 ? UINT64_MAX : ((u64)1 << bit_width) - 1;
    u64 input_ref;
    parse_hex_len_unknown(val, &input_ref);
    if (input_ref > upper_bound) {
        to_hex_string_thread_safe(upper_bound, 16, dest);
        memcpy(val, dest, 17);
    }
}

void hex_remove_leading_zeroes(char* buf) {
    i32 pos = 0;
    while (buf[pos] == '0') {
        pos += 1;
    }
    if (pos != 0) {
        i32 i;
        for (i = 0; buf[pos] != '\0'; i += 1) {
            buf[i] = buf[pos];
            pos += 1;
        }
        buf[i] = buf[pos];
    }
}

u64 dec_upper_bound(u64 bit_width, char* val) {
    char dest[21];
    u64 upper_bound = bit_width == 64 ? UINT64_MAX : ((u64)1 << bit_width) - 1;
    u64 input_ref;
    parse_dec_len_unknown(val, &input_ref);
    if (input_ref > upper_bound) {
        sprintf(dest, "%" PRIu64, upper_bound);
        memcpy(val, dest, 21);
        return upper_bound;
    }
    return input_ref;
}

u64 bin_upper_bound(u64 bit_width, char* val) {
    char dest[65];
    u64 upper_bound = bit_width == 64 ? UINT64_MAX : ((u64)1 << bit_width) - 1;
    u64 input_ref;
    parse_bin_len_unknown(val, &input_ref);
    if (input_ref > upper_bound) {
        val = binary_print(upper_bound);
        return upper_bound;
    }
    return input_ref;
}

void copy_without_whitespaces(char* src, char* dest) {
    i32 pos = 0;
    while (src[pos] != '\0') {
        if (src[pos] == ' ') {
            dest[pos] = '_';
        } else {
            dest[pos] = src[pos];
        }
        pos += 1;
    }
    dest[pos] = '\0';
}


#endif