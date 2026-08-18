#pragma once

#include <stdint.h>

#define SWRAP_STATIC
#include "../libs/swrap.h"
#include "../libs/tinycthread.h"

#define NR_TRIGGERS 4 // max number of triggers frames available in lac
#define NR_BUFFERS 10
#define NR_SAMPLES 512
#define MAX_SIGNALS 32

#define DEBUG_PRINTS
#define SEQ_ITEM_SIZE 100
#define NR_SEQ_ITEMS 5
#define ZOOM_SENSITIVITY 15000
#define SCROLL_SENSITIVITY 6
#define SCROLL_SENSITIVITY_V 2
#define SIGNAL_NAME_LEN 22

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef int32_t i32;
typedef int64_t i64;
typedef float f32;


const char SEPARATOR = ',';
#define NR_COMPARATORS 3
char* COMPARATOR[] = { "*", "==", "<", ">" };

#define NR_DATA_FORMATS 3
typedef enum {
    Hex = 0,
    Dec = 1,
    Bin = 2,
} Data_Format;
char* DATA_FORMAT[] = { "hex", "dec", "bin" };

typedef struct {
    bool  open;
    char* msg;
} Info_Modal;

typedef struct {
    bool open;
    i32  active_buffer;
    i32  pre_trig;
    char wavedrom_text[65536];
} Export_Modal;

typedef struct {
    bool      open;
    i32       active_buffer;
    thrd_t    thread;
    u32       stop;
    u32       finished;
    u32       progress;
} Capture_Modal;

typedef struct {
    bool in_use;
    u64  data[NR_SAMPLES];
    i32  pre_trigger_samples;
} Buffer;

// defines a slice of the captured buffer
typedef struct {
    i32         lsb;
    i32         msb;
    i32         width;
    char        name[SIGNAL_NAME_LEN + 1];
    bool        use_in_trigger[NR_TRIGGERS];
    u64         trig_ref[NR_TRIGGERS];
    f32         y_offset;
    f32         dy;
    u32         remaining_swap_frames;
    Data_Format data_format;
    bool        hide;
} Signal;

typedef struct {
    // state of modals should be set before the modal opens
    Info_Modal    info_modal;
    Export_Modal  export_modal;
    Capture_Modal capture_modal;

    // ui
    f32           y_separator;
    bool          separator_drag;
    f32           x_offset;
    f32           width;
    f32           wave_table_width;
    f32           wave_table_y_offset;
    u32           capture_count;
    bool          relative_cycle_nrs; // TODO: add button in ui
    bool          minimap_drag_active;
    bool          combobox_open;
    bool          diff_view_open;

    // configuration
    i32           pre_trigger_samples;
    Signal        signals[MAX_SIGNALS];
    u32           nr_signals;
    char*         comparators[NR_TRIGGERS];
    i32           acc_signal_width;
    i32           trigger_len;

    // signal update
    bool          swap_signals;
    i32           swap_s1;
    i32           swap_s2;
    bool          delete_signal;
    i32           delete_s;

    // buffers
    Buffer        buffers[10];
    i32           active_buffer;
    i32           active_diff_buffer;
} State;

typedef enum {
    Ok,
    Cancel,
    Error,
} Import_Result;
