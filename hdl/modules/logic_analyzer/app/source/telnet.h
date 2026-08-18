// sources of this minimal telnet implementation (2025 10 10):
// https://gist.github.com/legnaleurc/7638738
// http://l3net.wordpress.com/2012/12/09/a-simple-telnet-client/

#include <stdio.h>
#include <stdlib.h>

#include "core.h"
#include "utils.h"
 
#define DO 0xfd
#define WONT 0xfc
#define WILL 0xfb
#define DONT 0xfe
#define CMD 0xff
#define CMD_ECHO 1
#define CMD_WINDOW_SIZE 31

#define BUFLEN 64

// match the localparams of the logic analyzer verilog module
#define LOW_BASE          0x00
#define HIGH_BASE         0x01
#define DONE              0x02
#define START_ADDRESS     0x03
#define SEQ_LEN           0x04
#define POST_TRIG_SAMPLES 0x05
#define MASK_0_LO         0x10
#define MASK_0_HI         0x11
#define MASK_1_LO         0x12
#define MASK_1_HI         0x13
#define MASK_2_LO         0x14
#define MASK_2_HI         0x15
#define MASK_3_LO         0x16
#define MASK_3_HI         0x17
#define REFERENCE_0_LO    0x18
#define REFERENCE_0_HI    0x19
#define REFERENCE_1_LO    0x1a
#define REFERENCE_1_HI    0x1b
#define REFERENCE_2_LO    0x1c
#define REFERENCE_2_HI    0x1d
#define REFERENCE_3_LO    0x1e
#define REFERENCE_3_HI    0x1f
#define COMPARATOR_0      0x06
#define COMPARATOR_1      0x07
#define COMPARATOR_2      0x08
#define COMPARATOR_3      0x09
#define RESET             0x0f

#define RES_OK            0
#define RES_REMOTE_CLOSED 1
#define RES_ERR           2


i32 sock;
u8 buf[BUFLEN];

// ----------------------------------------------------------------------------
// Telnet Connection
// ----------------------------------------------------------------------------

typedef struct {
    bool open;
} Telnet_Connection;
Telnet_Connection connection = {0};

i32 connect_to_telnet_server() {
    assert(!connection.open);
    sock = swrapSocket(SWRAP_TCP, SWRAP_CONNECT, 0, "127.0.0.1", "4444");
    if (sock == -1) {
        connection.open = false;
        return -1;
    }
    connection.open = true;
    return 0;
}
 
void _telnet_negotiate(int sock, unsigned char *buf, int len) {
    int i;
     
    if (buf[1] == DO && buf[2] == CMD_WINDOW_SIZE) {
        unsigned char tmp1[10] = {255, 251, 31};
        if (swrapSend(sock, (const char*)tmp1, 3) < 0) {
            exit(1);
        }
         
        unsigned char tmp2[10] = {255, 250, 31, 0, 80, 0, 24, 255, 240};
        if (swrapSend(sock, (const char*)tmp2, 9) < 0) {
            exit(1);
        }
        return;
    }
     
    for (i = 0; i < len; i++) {
        if (buf[i] == DO)
            buf[i] = WONT;
        else if (buf[i] == WILL)
            buf[i] = DO;
    }
 
    if (swrapSend(sock, (const char*)buf, len) < 0) {
        exit(1);
    }
}
 
char output_buf[128] = {'\0'};
i32 output_size = 0;

char result_buf[128] = {'\0'};
i32 result_size = 0;
bool result_write = false;

i32 _run_command(char *msg, i32 in_size) {
    if (!connection.open) {
        connect_to_telnet_server();
    }
    output_size = 0;
    output_buf[0] = '\0';
    result_size = 0;
    result_buf[0] = '\0';
    int len;
    struct timeval ts;
    ts.tv_sec = 0;
    ts.tv_usec = 100;

    // send
    memcpy(&buf, msg, in_size);
    if (swrapSend(sock, (const char*)buf, in_size) < 0) {
        return RES_ERR;
    }

    if (buf[0] == '\n') { // with the terminal in raw mode we need to force a LF
        putchar('\r');
    }

    while (true) {
        i32 nready = swrapSelect(sock, 0, 1000);
        if (nready < 0) {
            perror("select. Error");
            connection.open = false;
            return RES_ERR;

        } else if (nready == 0) {
            if (output_buf[output_size - 1] == '>' || output_buf[output_size - 2] == '>') {
                output_buf[output_size] = '\0';
                result_buf[result_size] = '\0';
                result_write = false;
                return RES_OK;
            }
        } else if (sock != 0) {
            // start by reading a single byte
            int rv;


            i32 res = swrapReceive(sock, (char*)buf, 1);
            if (res < 0) {
                connection.open = false;
                return RES_ERR;
            } else if (res == 0) {
                printf("Connection closed by the remote end\n\r");
                connection.open = false;
                return RES_REMOTE_CLOSED;
            }

            if (buf[0] == CMD) {
                // read 2 more bytes
                i32 res = swrapReceive(sock, (char*)(buf + 1), 2);
                if (res < 0) {
                    connection.open = false;
                    return RES_ERR;
                } else if (res == 0) {
                    printf("Connection closed by the remote end\n\r");
                    connection.open = false;
                    return RES_REMOTE_CLOSED;
                }
                _telnet_negotiate(sock, buf, 3);

            } else {
                if (buf[0] == '>') {
                    result_write = false;
                }
                if (buf[0] == '\n') {
                    output_buf[output_size] = 'n';
                } else if (buf[0] == '\r') {
                    output_buf[output_size] = 'r';
                } else if (buf[0] == '\0') {
                    output_buf[output_size] = SEPARATOR; // this character is put before result string
                    result_write = true;
                } else {
                    output_buf[output_size] = buf[0];
                    if (result_write) {
                        result_buf[result_size] = buf[0];
                        result_size += 1;
                    }
                }
                output_size += 1;
                fflush(0);
            }
        }
    }
    return RES_OK;
}

i32 _write_command(char *msg, u32 size) {
    return _run_command(msg, size);
}

i32 _read_command(u32* dest, char *msg, u32 size) {
    i32 res = _run_command(msg, size);
    if (res != RES_OK) {
        return res;
    }

    assert_true(output_size < 128, "output_size is bigger than output_buf");

    // parse response
    i32 out_start;
    i32 out_end;
    for (i32 i = 0; i < output_size; i += 1) {
        if (output_buf[i] == ':') {

            // start found
            out_start = i + 1;
            out_end = out_start;

            while (output_buf[out_end] != ' ' && out_end < output_size - 1) {
                out_end += 1;
            }
            output_buf[out_end] = '\0';
            *dest = (u32)parse_hex_unsafe(&output_buf[out_start], 8);
            return RES_OK;
        }
    }
    return RES_OK;
}

// gdb remote interface -------------------------------------------------------

i32 fetch_done_signal(u32* dest) {
    insert_char_address(&read_cmd_buf[6], DONE, 0, true);
    return _read_command(dest, read_cmd_buf, COMMAND_LEN);
}

i32 fetch_start_address(u32* dest) {
    insert_char_address(&read_cmd_buf[6], START_ADDRESS, 0, true);
    return _read_command(dest, read_cmd_buf, COMMAND_LEN);
}

i32 fetch_capture(u64* dest, u32 address) {
    u64 result = 0;

    // low
    insert_char_address(&read_cmd_buf[6], LOW_BASE, address, true);
    u32 low, high;
    u32 res = _read_command(&low, read_cmd_buf, COMMAND_LEN);
    if (res != RES_OK) { return res; }

    // high
    insert_char_address(&read_cmd_buf[6], HIGH_BASE, address, true);
    res = _read_command(&high, read_cmd_buf, COMMAND_LEN);
    *dest = (((u64)high) << 32) | (u64)low;
    return res;
}

i32 upload_post_trigger(i32 pre_trigger_samples) {
    i32 size = sprintf(str_buf, "mww 0x........ 0x%x\r\n", 511 - pre_trigger_samples);
    insert_char_address(&str_buf[6], POST_TRIG_SAMPLES, 0, false);
    return _write_command(str_buf, size);
}

i32 upload_seq_len(char* len) {
    i32 size = sprintf(str_buf, "mww 0x........ 0x%s\r\n", len);
    insert_char_address(&str_buf[6], SEQ_LEN, 0, false);
    return _write_command(str_buf, size);
}

i32 upload_comparator(char* comparator, i32 trig) {
    assert_true(trig < 4 && trig >= 0, "trigger must be between 0 and 4\n");

    u32 comparator_id = 0;
    for (int i = 0; i < 6; i += 1) {
        if (COMPARATOR[i] == comparator) {
            comparator_id = i;
            break;
        }
    }

    i32 size = sprintf(str_buf, "mww 0x........ 0x%d\r\n", comparator_id);
    switch (trig) {
    case 0: insert_char_address(&str_buf[6], COMPARATOR_0, 0, false); break;
    case 1: insert_char_address(&str_buf[6], COMPARATOR_1, 0, false); break;
    case 2: insert_char_address(&str_buf[6], COMPARATOR_2, 0, false); break;
    case 3: insert_char_address(&str_buf[6], COMPARATOR_3, 0, false); break;
    }
    return _write_command(str_buf, size);
}

i32 upload_mask(char* mask, i32 trig, bool low) {
    i32 size = sprintf(str_buf, "mww 0x........ 0x%s\r\n", mask);
    if (low) {
        switch (trig) {
        case 0: insert_char_address(&str_buf[6], MASK_0_LO, 0, false); break;
        case 1: insert_char_address(&str_buf[6], MASK_1_LO, 0, false); break;
        case 2: insert_char_address(&str_buf[6], MASK_2_LO, 0, false); break;
        case 3: insert_char_address(&str_buf[6], MASK_3_LO, 0, false); break;
        }
    } else {
        switch (trig) {
        case 0: insert_char_address(&str_buf[6], MASK_0_HI, 0, false); break;
        case 1: insert_char_address(&str_buf[6], MASK_1_HI, 0, false); break;
        case 2: insert_char_address(&str_buf[6], MASK_2_HI, 0, false); break;
        case 3: insert_char_address(&str_buf[6], MASK_3_HI, 0, false); break;
        }
    }
    return _write_command(str_buf, size);
}

i32 upload_reference(char* reference, i32 trig, bool low) {
    i32 size = sprintf(str_buf, "mww 0x........ 0x%s\r\n", reference);
    if (low) {
        switch (trig) {
        case 0: insert_char_address(&str_buf[6], REFERENCE_0_LO, 0, false); break;
        case 1: insert_char_address(&str_buf[6], REFERENCE_1_LO, 0, false); break;
        case 2: insert_char_address(&str_buf[6], REFERENCE_2_LO, 0, false); break;
        case 3: insert_char_address(&str_buf[6], REFERENCE_3_LO, 0, false); break;
        }
    } else {
        switch (trig) {
        case 0: insert_char_address(&str_buf[6], REFERENCE_0_HI, 0, false); break;
        case 1: insert_char_address(&str_buf[6], REFERENCE_1_HI, 0, false); break;
        case 2: insert_char_address(&str_buf[6], REFERENCE_2_HI, 0, false); break;
        case 3: insert_char_address(&str_buf[6], REFERENCE_3_HI, 0, false); break;
        }
    }
    return _write_command(str_buf, size);
}

i32 reset_logic_analyzer() {
    i32 size = sprintf(str_buf, "mww 0x........ 0x0\r\n");
    insert_char_address(&str_buf[6], RESET, 0, false);
    return _write_command(str_buf, size);
}
