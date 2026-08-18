#include "../libs/tinyfiledialogs.h"
#include "../libs/toml-c.h"
#include "core.h"
#include "utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <inttypes.h>

const char symbols[MAX_SIGNALS] = {'#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~', 'A', 'B'};

void print_bits(FILE* fptr, u64 value, u32 lsb, u32 msb, u32 symb) {
    assert(msb >= lsb && ((msb - lsb) < 64));

    if ((msb - lsb) == 0) {
        fprintf(fptr, "%" PRIx64 "%c\n", value, symbols[symb]);

    } else {
        fprintf(fptr, "b");
        u32 offset = msb - lsb;
        for (i32 i = (i32)msb; i >= (i32)lsb; i -= 1) {
            fprintf(fptr, "%" PRIx64, (value >> offset) & 1);
            offset -= 1;
        }
        fprintf(fptr, " %c\n", symbols[symb]);
    }
}

char* sanitize_file_name(char const* unsanitized, char const* extension) {
    i32 len = 0;
    while (unsanitized[len] != '\0') {
        len += 1;
    }

    i32 ext_len = 0;
    while (extension[ext_len] != '\0') {
        ext_len += 1;
    }

    if (len <= ext_len) {
        sprintf(str_buf, "%s%s", unsanitized, extension);
        return str_buf;
    }

    bool must_append = false;
    for (i32 i = 0; i < ext_len; i += 1) {
        if (unsanitized[len - 1 - i] != extension[ext_len - 1 - i]) {
            must_append = true;
            break;
        }
    }

    if (must_append) {
        sprintf(str_buf, "%s%s", unsanitized, extension);
    } else {
        // sprintf(str_buf, "%s", unsanitized);
        return (char*)unsanitized;
    }
    return str_buf;
}

bool write_vcd(u64 buf[512], Signal signals[], i32 nr_signals) {
    char const* file_name = tinyfd_saveFileDialog("Write VCD File", NULL, 0, NULL, NULL);
    if (file_name == NULL) {
        return false;
    }
    FILE* fptr = fopen(sanitize_file_name(file_name, ".vcd"), "w");
    if (fptr == NULL) {
        return false;
    }

    // Date
    time_t now = time(NULL);
    struct tm* t = localtime(&now);
    strftime(str_buf, 255, "%Y-%m-%d %H:%M", t);
    fprintf(fptr, "$date\n");
    fprintf(fptr, "\t%s\n", str_buf);
    fprintf(fptr, "$end\n");

    // Version
    fprintf(fptr, "$version\n");
    fprintf(fptr, "\tLogic-Analyzer-Gecko5-V1\n");
    fprintf(fptr, "$end\n");

    // Timescale
    fprintf(fptr, "$timescale 1ps $end\n");

    // Scope
    fprintf(fptr, "$scope module capture $end\n");

    // Wires
    char name_buf[32];
    for (i32 i = 0; i < nr_signals; i += 1) {
        copy_without_whitespaces(signals[i].name, name_buf);
        u32 nr_wires = signals[i].msb - signals[i].lsb + 1;
        fprintf(fptr, "$var wire %u %c %s $end\n", nr_wires, symbols[i], name_buf);
    }

    // Upscope
    fprintf(fptr, "$upscope $end\n");
    fprintf(fptr, "$enddefinitions $end\n");

    // Dumpvars
    fprintf(fptr, "$dumpvars\n");
    for (i32 signal = 0; signal < nr_signals; signal += 1) {
        u64 value = buf[0];
        value <<= (63 - signals[signal].msb);
        value >>= ((63 - signals[signal].msb) + signals[signal].lsb);
        print_bits(fptr, value, signals[signal].lsb, signals[signal].msb, signal);
    }
    fprintf(fptr, "$end\n");

    // First Cycle
    fprintf(fptr, "#0\n");
    for (i32 signal = 0; signal < nr_signals; signal += 1) {
        u64 value = buf[0];
        value <<= (63 - signals[signal].msb);
        value >>= ((63 - signals[signal].msb) + signals[signal].lsb);
        print_bits(fptr, value, signals[signal].lsb, signals[signal].msb, signal);
    }

    u64 last_vals[32] = {0};
    u64 last_val = buf[0];

    // Other Cycles
    for (i32 cycle = 0; cycle < 512; cycle += 1) {
        if (buf[cycle] == last_val) {
            continue;
        }
        last_val = buf[cycle];
        fprintf(fptr, "#%d\n", cycle);
        for (i32 signal = 0; signal < nr_signals; signal += 1) {
            u64 value = buf[cycle];
            value <<= (63 - signals[signal].msb);
            value >>= ((63 - signals[signal].msb) + signals[signal].lsb);
            if (value == last_vals[signal]) {
                continue;
            }
            last_vals[signal] = value;
            print_bits(fptr, value, signals[signal].lsb, signals[signal].msb, signal);
        }
    }

    fprintf(fptr, "\n#512\n");
    fclose(fptr);
    return true;
}

Import_Result read_vcd(State* state, i32 buffer_idx) {

    // TODO: implement vcd parsing (or use some c library that works)
    // To detect if it is a vcd file produced by logic analyzer, the version should look like this:
    // 'Logic-Analyzer-Gecko5-V1' (see 'write_vcd' function)

    return Ok;
}

// TODO: (maybe future work) in ui define which clipping cycles to prevent storing all 512 cycles
bool write_wavedrom(char* wavedrom_text) {
    char const* file_name = tinyfd_saveFileDialog("Write Wavedrom File", NULL, 0, NULL, NULL);
    if (file_name == NULL) {
        return false;
    }
    FILE* fptr = fopen(sanitize_file_name(file_name, ".json"), "w");
    if (fptr == NULL) {
        return false;
    }

    fprintf(fptr, "%s", wavedrom_text);
    fclose(fptr);
    return true;
}

void write_wavedrom_buf(u64 buf[512], Signal signals[], i32 nr_signals, i32 trig, char* out_buf) {

    i32 size = 65536;
    i32 offset = 0;

    // prologue
    offset += snprintf(&out_buf[offset], size - offset, "{\n\tsignal: [\n");

    // clock
    offset += snprintf(&out_buf[offset], size - offset, "\t\t{ name: \"clk\", wave: \"p");

    for (i32 i = 0; i < 511; i += 1) {
        offset += snprintf(&out_buf[offset], size - offset, ".");
    }
    offset += snprintf(&out_buf[offset], size - offset, "\" }");

    {
        // header wave
        offset += snprintf(&out_buf[offset], size - offset, ",\n\t\t{ name: \"Trigger\", wave: \"");
        u32 last = 10;
        for (i32 i = 0; i < 512; i += 1) {
            u32 val = (i == trig);
            if (val == last) {
                offset += snprintf(&out_buf[offset], size - offset, ".");
            } else if (val == 1) {
                offset += snprintf(&out_buf[offset], size - offset, "8");
                last = val;
            } else {
                offset += snprintf(&out_buf[offset], size - offset, "0");
                last = val;
            }
        }
        offset += snprintf(&out_buf[offset], size - offset, "\", data: [\"trig\"]}");
    }

    // waves
    for (i32 w = 0; w < nr_signals; w += 1) {
        offset += snprintf(&out_buf[offset], size - offset, ",\n\t\t{ name: \"%s\", wave: \"", signals[w].name);

        if (signals[w].msb == signals[w].lsb) {
            // single bit
            u32 last = 2;
            for (i32 i = 0; i < 512; i += 1) {
                u32 val = (buf[i] >> signals[w].msb) & 1;
                if (val == last) {
                    offset += snprintf(&out_buf[offset], size - offset, ".");
                } else {
                    offset += snprintf(&out_buf[offset], size - offset, "%d", val);
                    last = val;
                }
            }

        } else {
            // multi bits
            u64 last = ~((buf[0] << (63 - signals[w].msb)) >> (63 - signals[w].msb + signals[w].lsb)); // any different value than first frame
            for (i32 i = 0; i < 512; i += 1) {
                u64 val = (buf[i] << (63 - signals[w].msb)) >> (63 - signals[w].msb + signals[w].lsb);
                if (val == last) {
                    offset += snprintf(&out_buf[offset], size - offset, ".");
                } else if (val > 0) {
                    offset += snprintf(&out_buf[offset], size - offset, "x");
                    last = val;
                } else {
                    offset += snprintf(&out_buf[offset], size - offset, "0");
                    last = val;
                }
            }
        }
        offset += snprintf(&out_buf[offset], size - offset, "\" }");
    }
    // epilogue
    offset += snprintf(&out_buf[offset], size - offset, "\n],\n");
    offset += snprintf(&out_buf[offset], size - offset, "\thead: { tock:0 }\n}\n");
}

bool write_configuration_toml(State* state) {
    char const* file_name = tinyfd_saveFileDialog("Write Configuration File", NULL, 0, NULL, NULL);
    if (file_name == NULL) {
        return false;
    }
    FILE* fptr = fopen(sanitize_file_name(file_name, ".toml"), "w");
    if (fptr == NULL) {
        return false;
    }

    fprintf(fptr, "[config]\n");
    fprintf(fptr, "pre_trigger_samples = %d\n", state->pre_trigger_samples);

    for (i32 i = 0; i < 4; i += 1) {
        fprintf(fptr, "\n[config.trigger%d]\n", i + 1);
        fprintf(fptr, "comparator = \"%s\"\n", state->comparators[i]);
    }

    for (i32 i = 0; i < state->nr_signals; i += 1) {
        fprintf(fptr, "\n[[signals]]\n");
        fprintf(fptr, "name = \"%s\"\n", state->signals[i].name);
        fprintf(fptr, "width = %d\n", state->signals[i].width);
        fprintf(fptr, "hide = %d\n", (i32)state->signals[i].hide);
        fprintf(fptr, "data_format = %d\n", (i32)state->signals[i].data_format);
        fprintf(fptr, "trig1_enabled = %d\n", state->signals[i].use_in_trigger[0]);
        fprintf(fptr, "trig1_ref = %" PRIi64 "\n", (i64)state->signals[i].trig_ref[0]);
        fprintf(fptr, "trig2_enabled = %d\n", state->signals[i].use_in_trigger[1]);
        fprintf(fptr, "trig2_ref = %" PRIi64 "\n", (i64)state->signals[i].trig_ref[1]);
        fprintf(fptr, "trig3_enabled = %d\n", state->signals[i].use_in_trigger[2]);
        fprintf(fptr, "trig3_ref = %" PRIi64 "\n", (i64)state->signals[i].trig_ref[2]);
        fprintf(fptr, "trig4_enabled = %d\n", state->signals[i].use_in_trigger[3]);
        fprintf(fptr, "trig4_ref = %" PRIi64 "\n", (i64)state->signals[i].trig_ref[3]);
    }
    fclose(fptr);

    return true;
}

Import_Result read_configuration_toml(State* state) {
    char const* file_name = tinyfd_openFileDialog("Read Configuration File", NULL, 0, NULL, NULL, 0);
    if (file_name == NULL) {
        return Cancel;
    }
    sanitize_file_name(file_name, ".toml");

    char* buf;
    i32 bytes = read_entire_file((char*)file_name, &buf);
    if (bytes < 0) {
        return Error;
    }

    char errbuf[200];
    toml_table_t* tbl = toml_parse(buf, errbuf, sizeof(errbuf));
    if (!tbl) {
        fprintf(stderr, "ERROR: %s\n", errbuf);
        return Error;
    }

    // config
    toml_table_t* config = toml_table_table(tbl, "config");
    i32 config_len = toml_table_len(config);
    u32 pretrigger_samples;
    u32 trigger_len;

    toml_value_t val = toml_table_int(config, "pre_trigger_samples");
    if (!val.ok) {
        free(buf);
        return Error;
    }
    state->pre_trigger_samples = (u32)val.u.i;

    // config.trigger
    for (i32 i = 0; i < 4; i += 1) {

        sprintf(str_buf, "trigger%d", i + 1);
        toml_table_t* trig_tbl = toml_table_table(config, str_buf);

        val = toml_table_string(trig_tbl, "comparator");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        for (i32 cmp = 0; cmp < 6; cmp += 1) {
            if (!strcmp(val.u.s, COMPARATOR[cmp])) {
                memcpy(&state->comparators[i], val.u.s, val.u.sl);
                state->comparators[i] = COMPARATOR[cmp];
                break;
            }
        }
    }

    // waves
    toml_array_t* arr = toml_table_array(tbl, "signals");
    i32 arr_len = toml_array_len(arr);
    i32 lsb = 0;
    for (i32 i = 0; i < arr_len; i += 1) {
        toml_table_t* item = toml_array_table(arr, i);

        // width
        val = toml_table_int(item, "width");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].width = val.u.i;
        state->signals[i].lsb = lsb;
        state->signals[i].msb = lsb + val.u.i - 1;
        lsb += val.u.i;
        state->acc_signal_width = lsb;

        // hide
        val = toml_table_int(item, "hide");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].hide = (bool)val.u.i;

        // data_format
        val = toml_table_int(item, "data_format");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].data_format = (Data_Format)val.u.i;

        // name
        val = toml_table_string(item, "name");
        if (!val.ok || val.u.sl > SIGNAL_NAME_LEN) {
            free(buf);
            return Error;
        }
        memcpy(state->signals[i].name, val.u.s, val.u.sl);
        state->signals[i].name[val.u.sl] = '\0';

        // trig1_enabled
        val = toml_table_int(item, "trig1_enabled");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].use_in_trigger[0] = (bool)val.u.i;

        // trig1_ref
        val = toml_table_int(item, "trig1_ref");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].trig_ref[0] = (u64)val.u.i;

        // trig2_enabled
        val = toml_table_int(item, "trig2_enabled");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].use_in_trigger[1] = (bool)val.u.i;

        // trig2_ref
        val = toml_table_int(item, "trig2_ref");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].trig_ref[1] = (u64)val.u.i;

        // trig3_enabled
        val = toml_table_int(item, "trig3_enabled");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].use_in_trigger[2] = (bool)val.u.i;

        // trig3_ref
        val = toml_table_int(item, "trig3_ref");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].trig_ref[2] = (u64)val.u.i;

        // trig4_enabled
        val = toml_table_int(item, "trig4_enabled");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].use_in_trigger[3] = (bool)val.u.i;

        // trig4_ref
        val = toml_table_int(item, "trig4_ref");
        if (!val.ok) {
            free(buf);
            return Error;
        }
        state->signals[i].trig_ref[3] = (u64)val.u.i;
    }
    state->nr_signals = arr_len;

    free(buf);
    return Ok;
}
