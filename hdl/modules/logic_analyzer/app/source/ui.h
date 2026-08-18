#include "../libs/tinyfiledialogs.h"
#include "core.h"
#include "io.h"
#include "telnet.h"
#include "utils.h"
#include <inttypes.h>
#include <stdio.h>

#define SWAP_DURATION 10
#define WAVE_CLOCK_OFFSET 3

#define ROW_HEIGHT 23.0
#define MODAL_WIDTH 400.0
#define MODAL_HEIGHT 140
#define BUTTON_RADIUS 4

// const ImU32 DARK_BG = IM_COL32(40, 40, 40, 255);
const ImU32 DARK_BG = IM_COL32(30, 30, 30, 255);
const ImU32 LIGHT_BG = IM_COL32(45, 45, 45, 255);
const ImU32 LIGHT_HEADER = IM_COL32(55, 55, 55, 255);
const ImU32 HEADER = IM_COL32(75, 75, 75, 255);
const ImU32 TITLE_FG = IM_COL32(220, 220, 220, 255);
const ImU32 INACTIVE_CHECK = IM_COL32(255, 255, 255, 50);

const ImU32 MINIMAP_THUMB = IM_COL32(255, 255, 255, 55);
const ImU32 MINIMAP_THUMB_HOVER = IM_COL32(255, 255, 255, 70);
const ImU32 TRIGGER_BG2 = IM_COL32(163, 87, 210, 255);
const ImU32 TRIGGER_BG = IM_COL32(165, 24, 194, 255);
const ImU32 BUFFER_COLOR[10] = {
    IM_COL32(42, 157, 143, 255),
    IM_COL32(138, 177, 125, 255),
    IM_COL32(233, 196, 106, 255),
    IM_COL32(244, 162, 97, 255),
    IM_COL32(236, 129, 81, 255),
    IM_COL32(227, 96, 64, 255),
    IM_COL32(188, 107, 133, 255),
    IM_COL32(149, 118, 201, 255),
    IM_COL32(38, 70, 83, 255),
    IM_COL32(40, 114, 113, 255),
};
#define COLOR_ALPHA 180
const ImU32 BUFFER_COLOR_A[11] = {
    IM_COL32(42, 157, 143, COLOR_ALPHA),
    IM_COL32(138, 177, 125, COLOR_ALPHA),
    IM_COL32(233, 196, 106, COLOR_ALPHA),
    IM_COL32(244, 162, 97, COLOR_ALPHA),
    IM_COL32(236, 129, 81, COLOR_ALPHA),
    IM_COL32(227, 96, 64, COLOR_ALPHA),
    IM_COL32(188, 107, 133, COLOR_ALPHA),
    IM_COL32(149, 118, 201, COLOR_ALPHA),
    IM_COL32(38, 70, 83, COLOR_ALPHA),
    IM_COL32(40, 114, 113, COLOR_ALPHA),
    IM_COL32(180, 10, 10, COLOR_ALPHA),
};

const ImU32 WINDOW_BG = IM_COL32(38, 38, 38, 255);
const ImU32 WINDOW_BG_BUF = IM_COL32(25, 25, 25, 255);

static struct {
    sg_pass_action pass_action;
} sokol_state;

State state = {0};

void init_state() {
    memset(&state, 0, sizeof(state));
    state.y_separator = 250;
    state.x_offset = 0;
    state.width = 20000;
    state.capture_count = 0;
    state.pre_trigger_samples = 50;
    state.relative_cycle_nrs = true;
    state.comparators[0] = COMPARATOR[1];
    state.comparators[1] = COMPARATOR[0];
    state.comparators[2] = COMPARATOR[0];
    state.comparators[3] = COMPARATOR[0];

    state.nr_signals = 0;

    // state.next_buffer = 1;
    for (i32 buf = 0; buf < NR_BUFFERS; buf += 1) {
        state.buffers[buf].pre_trigger_samples = -1;
    }
    swrapInit();
}

void add_empty_signal() {
    state.signals[state.nr_signals].width = 1;
    state.signals[state.nr_signals].msb = state.acc_signal_width;
    state.signals[state.nr_signals].lsb = state.acc_signal_width;
    for (i32 i = 0; i < NR_TRIGGERS; i += 1) {
        state.signals[state.nr_signals].trig_ref[i] = 0;
        state.signals[state.nr_signals].use_in_trigger[i] = false;
    }
    state.acc_signal_width += 1;
    state.nr_signals += 1;
}

void update_signal_width(i32 s, i32 prev_width) {
    i32 diff = state.signals[s].width - prev_width;
    if (diff == 0) {
        return;
    }

    state.acc_signal_width += diff;

    state.signals[s].msb += diff;
    for (i32 i = s + 1; i < state.nr_signals; i += 1) {
        state.signals[i].lsb += diff;
        state.signals[i].msb += diff;
    }
}

void delete_signal(i32 s) {
    i32 width = state.signals[s].width;
    state.acc_signal_width -= width;
    for (u32 j = s + 1; j < state.nr_signals; j += 1) {
        state.signals[j - 1] = state.signals[j];
        state.signals[j - 1].lsb -= width;
        state.signals[j - 1].msb -= width;

        // animation
        state.signals[j - 1].remaining_swap_frames = SWAP_DURATION;
        state.signals[j - 1].y_offset = ROW_HEIGHT;
        state.signals[j - 1].dy = -ROW_HEIGHT / SWAP_DURATION;
    }
    state.nr_signals -= 1;
}

void delete_signal_next_frame(i32 s) {
    state.delete_signal = true;
    state.delete_s = s;
}

// s1 must be 1 row above s2
void swap_signals(i32 s1, i32 s2) {
    i32 s1_width = state.signals[s1].width;
    i32 s2_width = state.signals[s2].width;

    // swap data
    Signal tmp = state.signals[s1];
    state.signals[s1] = state.signals[s2];
    state.signals[s2] = tmp;

    // adjust signal range
    state.signals[s1].lsb = state.signals[s2].lsb;
    state.signals[s1].msb = state.signals[s1].lsb + s2_width - 1;
    state.signals[s2].lsb = state.signals[s1].msb + 1;
    state.signals[s2].msb = state.signals[s2].lsb + s1_width - 1;

    // animation
    state.signals[s1].remaining_swap_frames = SWAP_DURATION;
    state.signals[s1].y_offset = ROW_HEIGHT;
    state.signals[s1].dy = -ROW_HEIGHT / SWAP_DURATION;
    state.signals[s2].remaining_swap_frames = SWAP_DURATION;
    state.signals[s2].y_offset = -ROW_HEIGHT;
    state.signals[s2].dy = ROW_HEIGHT / SWAP_DURATION;
}

void swap_signals_next_frame(i32 s1, i32 s2) {
    state.swap_signals = true;
    state.swap_s1 = s1;
    state.swap_s2 = s2;
}

// -----------------------------------------------------------------------------
// Custom Widgets
// -----------------------------------------------------------------------------

bool data_format_combo_box(char* label, Signal* signal) {
    igSetNextItemWidth(49);
    if (igBeginCombo(label, DATA_FORMAT[signal->data_format], ImGuiComboFlags_None)) {
        state.combobox_open = true;
        for (i32 i = 0; i < NR_DATA_FORMATS; i += 1) {
            bool is_selected = signal->data_format == i;
            if (igSelectable(DATA_FORMAT[i])) {
                signal->data_format = (Data_Format)i;
            }
            if (is_selected) {
                igSetItemDefaultFocus();
            }
        }
        igEndCombo();
        return true;
    }
    return false;
}

bool comparator_combo_box(char* label, u32 index, i32 from, i32 to) {
    igSetNextItemWidth(43);
    if (igBeginCombo(label, state.comparators[index], ImGuiComboFlags_None)) {

        for (int n = from; n < to; n++) {
            bool is_selected = (state.comparators[index] == COMPARATOR[n]);
            if (igSelectable(COMPARATOR[n])) {
                state.comparators[index] = COMPARATOR[n];
            }
            if (is_selected) {
                igSetItemDefaultFocus();
            }
        }
        if ((state.comparators[index] == COMPARATOR[0]) ||
            (state.comparators[index] == COMPARATOR[1])) {
            igEndCombo();
            return true;
        }

        // set max 1 selection if new selected comparator is >, <
        i32 selected_count = 0;
        for (i32 i = 0; i < state.nr_signals; i += 1) {
            selected_count += (i32)state.signals[i].use_in_trigger[index];
            if (selected_count > 1) {
                state.signals[i].use_in_trigger[index] = false;
            }
        }
        igEndCombo();
        return true;
    }
    return false;
}

bool button_centered_on_line(const char* label) {
    float alignment = 0.5;
    ImGuiStyle* style = igGetStyle();

    float size = igCalcTextSize(label).x + style->FramePadding.x * 2.0f;
    float avail = igGetContentRegionAvail().x;

    float off = (avail - size) * alignment;
    if (off > 0.0f)
        igSetCursorPosX(igGetCursorPosX() + off);

    return igButton(label);
}

void text_centered_on_line(const char* text) {
    float alignment = 0.5;
    ImGuiStyle* style = igGetStyle();

    float size = igCalcTextSize(text).x;
    float avail = igGetContentRegionAvail().x;

    float off = (avail - size) * alignment;
    if (off > 0.0f)
        igSetCursorPosX(igGetCursorPosX() + off);

    igText("%s", text);
}

void input_int_range(char* label, i32* val, i32 min, i32 max) {
    if (igInputInt(label, val)) {
        if (*val > max) {
            *val = max;
        } else if (*val < min) {
            *val = min;
        }
    }
}

void input_u32_range(char* label, u32* val, u32 min, u32 max) {
    if (igInputScalar(label, ImGuiDataType_U32, val)) {
        if (*val > max) {
            *val = max;
        } else if (*val < min) {
            *val = min;
        }
    }
}

void input_u32_hex(char* label, char* val) {
    char last[9];
    strcpy(last, val);
    if (igInputText(label, val, 9, ImGuiInputTextFlags_None)) {
        u64 res;
        bool ok = parse_hex(val, &res, 8);
        if (!ok) {
            strcpy(val, last);
        }
    }
}

// -----------------------------------------------------------------------------
// Info Modal
// -----------------------------------------------------------------------------

void init_info_modal(char* message) {
    assert(!state.info_modal.open);
    state.info_modal.msg = message;
    state.info_modal.open = true;
}

void close_info_modal() {
    state.info_modal.open = false;
    igCloseCurrentPopup();
}

void draw_info_modal() {
    if (!state.info_modal.open) {
        return;
    }
    igOpenPopup("##Warning", 0);
    ImVec2 center = ImGuiViewport_GetCenter(igGetMainViewport());
    igSetNextWindowSize((ImVec2){MODAL_WIDTH, MODAL_HEIGHT}, ImGuiCond_None);
    igSetNextWindowPos((ImVec2){center.x - 200, center.y - 70}, ImGuiCond_Always);
    if (igBeginPopupModal("##Warning", NULL, 0b111110)) {

        igDummy((ImVec2){0, 20});

        text_centered_on_line(state.info_modal.msg);

        igDummy((ImVec2){0, 20});

        igPushStyleVar(ImGuiStyleVar_FrameRounding, BUTTON_RADIUS);
        if (button_centered_on_line("Close")) {
            close_info_modal();
        }
        igPopStyleVar();
        igDummy((ImVec2){0, 20});
        igEndPopup();
    }
}

// -----------------------------------------------------------------------------
// Capture Modal
// -----------------------------------------------------------------------------

void init_capture_modal(i32 buffer_idx) {
    assert(!state.capture_modal.open);
    state.capture_modal.open = true;
    state.capture_modal.stop = false;
    state.capture_modal.finished = false;
    state.capture_modal.active_buffer = buffer_idx;
    state.capture_modal.progress = 0;
}

void close_capture_modal() {
    state.capture_modal.open = false;
    state.capture_modal.progress = 0;
    igCloseCurrentPopup();
}

char progress_text[30];
void draw_capture_modal() {
    if (!state.capture_modal.open) {
        return;
    }
    if (state.capture_modal.finished) {
        state.capture_modal.finished = false;
        close_capture_modal();
    }
    igOpenPopup("##CaptureModal", 0);
    ImVec2 center = ImGuiViewport_GetCenter(igGetMainViewport());
    igSetNextWindowSize((ImVec2){MODAL_WIDTH, MODAL_HEIGHT}, ImGuiCond_None);
    igSetNextWindowPos((ImVec2){center.x - 200, center.y - 70}, ImGuiCond_Always);
    if (igBeginPopupModal("##CaptureModal", NULL, 0b111110)) {

        igDummy((ImVec2){0, 20});

        sprintf(progress_text, "Capturing Data... [%3d / %d]", state.capture_modal.progress, NR_SAMPLES);
        text_centered_on_line(progress_text);

        igDummy((ImVec2){0, 20});

        if (button_centered_on_line("Cancel")) {
            state.capture_modal.stop = true;
            close_capture_modal();
        }
        igDummy((ImVec2){0, 20});
        igEndPopup();
    }
}

// -----------------------------------------------------------------------------
// Export Modal
// -----------------------------------------------------------------------------

void init_export_modal(i32 buffer_i) {
    assert(!state.export_modal.open);
    Buffer* buffer = &state.buffers[buffer_i];
    write_wavedrom_buf(buffer->data, state.signals, (i32)state.nr_signals,
                       state.export_modal.pre_trig, state.export_modal.wavedrom_text);
    state.export_modal.open = true;
}

void close_export_modal() {
    state.export_modal.open = false;
    igCloseCurrentPopup();
}

void draw_export_modal() {
    if (!state.export_modal.open) {
        return;
    }
    f32 button_width = 200;
    f32 avail = igGetContentRegionAvail().x;
    f32 x = igGetCursorPosX() + (avail - button_width) / 2;

    igOpenPopup("##Export", 0);
    ImVec2 center = ImGuiViewport_GetCenter(igGetMainViewport());
    igSetNextWindowSize((ImVec2){MODAL_WIDTH, 340}, ImGuiCond_None);
    igSetNextWindowPos((ImVec2){center.x - MODAL_WIDTH / 2, center.y - 170}, ImGuiCond_Always);
    if (igBeginPopupModal("##Export", NULL, 0b111110)) {
        Buffer* buffer = &state.buffers[state.export_modal.active_buffer];

        igDummy((ImVec2){0, 20});
        igPushStyleVar(ImGuiStyleVar_FrameRounding, BUTTON_RADIUS);
        igSetCursorPosX(x);
        if (igButtonEx("Export as VCD file...", (ImVec2){button_width, 0})) {
            write_vcd(buffer->data, state.signals, (i32)state.nr_signals);
        }
        igSetCursorPosX(x);
        if (igButtonEx("Export as WaveDrom file...", (ImVec2){button_width, 0})) {
            write_wavedrom(state.export_modal.wavedrom_text);
        }

        igDummy((ImVec2){0, 20});
        igSetNextItemWidth(igGetContentRegionAvail().x);

        igBeginChild("scroll", (ImVec2){igGetContentRegionAvail().x, 120}, true,
                     ImGuiWindowFlags_NoScrollbar);
        igText("%s", state.export_modal.wavedrom_text);

        igEndChild();

        igSetCursorPosX(x);
        if (igButtonEx("Copy WaveDrom to Clipboard", (ImVec2){button_width, 0})) {
            igSetClipboardText(state.export_modal.wavedrom_text);
        }
        igDummy((ImVec2){0, 20});
        if (button_centered_on_line("Cancel")) {
            close_export_modal();
        }
        igPopStyleVar();
        igEndPopup();
    }
}

void end_capture_success() {
    state.capture_modal.finished = true;
    thrd_exit(0);
}

void end_capture_fail(char* msg) {
    init_info_modal(msg);
    state.capture_modal.finished = true;
    thrd_exit(0);
}

static int capture_proc_gdb(void *arg) {
    // HERE WE UPLOAD THE CONFIGURATION TO THE GECKO BOARD
    // AND THEN FETCH THE CAPTURE

    // create masks and references
    u64 masks[4] = {0};
    u64 ref[4] = {0};
    for (i32 i = 0; i < NR_TRIGGERS; i += 1) {
        if (state.comparators[i] == COMPARATOR[0]) {
            masks[i] = 0;
            ref[i] = 0;
        } else {
            for (i32 w = 0; w < state.nr_signals; w += 1) {
                if (state.signals[w].use_in_trigger[i]) {
                    u64 mask = ~0;
                    mask <<= (63 - state.signals[w].msb);
                    mask >>= ((63 - state.signals[w].msb) + state.signals[w].lsb);
                    mask <<= state.signals[w].lsb;
                    masks[i] |= mask;

                    u64 ref_val = state.signals[w].trig_ref[i];
                    ref[i] |= mask & (ref_val << state.signals[w].lsb);
                }
            }
        }
    }

    char buf[17];
    i32 res = upload_post_trigger(state.pre_trigger_samples);
    if (res != RES_OK) {
        end_capture_fail("Could not connect to telnet server");
    }
    to_hex_string_thread_safe(state.trigger_len, 1, buf);
    upload_seq_len(buf);
    for (int i = 0; i < state.trigger_len + 1; i += 1) {
        upload_comparator(state.comparators[i], i);

        to_hex_string_thread_safe((u32)masks[i], 8, buf);
        upload_mask(buf, i, true);
        to_hex_string_thread_safe((u32)(masks[i] >> 32), 8, buf);
        upload_mask(buf, i, false);

        to_hex_string_thread_safe((u32)ref[i], 8, buf);
        upload_reference(buf, i, true);
        to_hex_string_thread_safe((u32)(ref[i] >> 32), 8, buf);
        upload_reference(buf, i, false);
    }
    reset_logic_analyzer();

    u32 result;
    do {
       #ifdef _WIN32
        Sleep(100000);
       #else
        usleep(100000);
       #endif
        // poll 10 times per second
        res = fetch_done_signal(&result); 

    } while (res == RES_OK && result != 1 && !state.capture_modal.stop);

    if (state.capture_modal.stop) {
        end_capture_success();
    } else if (res != RES_OK) {
        end_capture_fail("telnet server closed");
    }

    u64 response_low;
    u64 response_high;
    Buffer* buffer = &state.buffers[state.capture_modal.active_buffer];

    u32 ring_address;
    res = fetch_start_address(&ring_address);
    if (res == RES_REMOTE_CLOSED) {
        end_capture_fail("telnet server closed");
    }
    bool done = true;
    char ring_address_hex[17];
    for (i32 i = 0; i < NR_SAMPLES; i += 1) {
        if (state.capture_modal.stop) {
            done = false;
            break;
        }

        state.capture_modal.progress = i;
        res = fetch_capture(&buffer->data[i], ring_address);
        if (res == RES_REMOTE_CLOSED) {
            end_capture_fail("telnet server closed");
        }
        ring_address = (ring_address + 1) % 0x200;
    }
    if (done) {
        buffer->pre_trigger_samples = state.pre_trigger_samples;
        buffer->in_use = true;
    }

    end_capture_success();
    return 0;
}

thrd_t capture() {
    thrd_t thread;
    thrd_create(&thread, capture_proc_gdb, NULL);
    return thread;
}

// -----------------------------------------------------------------------------
// Custom "UI-Components"
// -----------------------------------------------------------------------------

f32 buffer_tabs(i32* buffer_idx, ImDrawList* draw_list) {
    ImGuiIO* io = igGetIO();

    ImVec2 pos = igGetCursorScreenPos();
    ImVec2 avail = igGetContentRegionAvail();
    f32 space = 5;
    f32 buf_width = (avail.x - (NR_BUFFERS - 1) * space) / NR_BUFFERS;

    pos.y += 2;
    for (i32 i = 0; i < NR_BUFFERS; i += 1) {
        ImU32 col = BUFFER_COLOR[i];
        ImU32 text_col = IM_COL32(255, 255, 255, 255);
        f32 rect_border_thickness = 1;
        bool is_hovering = igIsMouseHoveringRect(pos, (ImVec2){pos.x + buf_width, pos.y + 20});
        is_hovering &= !state.export_modal.open & !state.info_modal.open && !state.combobox_open;

        if (is_hovering) {
            if (i != *buffer_idx) {
                igSetMouseCursor(ImGuiMouseCursor_Hand);
            }
            if (io->MouseClicked[0]) {
                *buffer_idx = i;
            }
        }
        if (is_hovering || i == *buffer_idx) {
            pos.y -= 2;
        }
        if (i == *buffer_idx) {
            rect_border_thickness = 1;
        } else {
            col <<= 8;
            col = (col >> 8) | ((u8)100 << 24);
            text_col = IM_COL32(255, 255, 255, 120);
        }
        if (state.buffers[i].in_use) {
            ImDrawList_AddRectFilled(draw_list, pos,
                                     (ImVec2){pos.x + buf_width, pos.y + 20}, col);
        } else {
            ImDrawList_AddRectEx(draw_list, pos,
                                 (ImVec2){pos.x + buf_width, pos.y + 20}, col, 0,
                                 ImDrawFlags_None, rect_border_thickness);
        }
        sprintf(str_buf, "Buf %d", i);
        ImDrawList_AddText(draw_list, (ImVec2){pos.x + 4, pos.y + 3}, text_col,
                           str_buf);
        pos.x += space + buf_width;
        if (is_hovering || i == *buffer_idx) {
            pos.y += 2;
        }
    }
    return pos.y;
}

f32 buffer_button_menu(i32* buffer_idx) {
    Buffer* buffer = &state.buffers[*buffer_idx];
    f32 button_width = 94;
    f32 button_height = 20;
    f32 spacing = 8;
    f32 left = igGetWindowPos().x + spacing;
    f32 top = igGetWindowHeight() + igGetWindowPos().y - button_height - spacing;

    // button menu
    ImVec2 menu_pos = igGetCursorPos();
    igSetCursorScreenPos((ImVec2){left, top});
    igPushStyleVar(ImGuiStyleVar_FrameRounding, BUTTON_RADIUS);
    if (igButtonEx("Capture", (ImVec2){button_width, button_height})) {

        if (!has_trigger(&state, 0)) {
            init_info_modal("Trigger 1 has no signal selected.");

        } else if (state.comparators[1] != COMPARATOR[0] && !has_trigger(&state, 1)) {
            init_info_modal("Trigger 2 has no signal selected.");

        } else if (state.comparators[2] != COMPARATOR[0] && !has_trigger(&state, 2)) {
            init_info_modal("Trigger 3 has no signal selected.");

        } else if (state.comparators[3] != COMPARATOR[0] && !has_trigger(&state, 3)) {
            init_info_modal("Trigger 4 has no signal selected.");

        } else {

            memset(&state.buffers[*buffer_idx].data, 0, sizeof(u64) * NR_SAMPLES);
            init_capture_modal(*buffer_idx);
            state.capture_modal.thread = capture();
        }
    }

    igSameLine();
    if (igButtonEx("Reset", (ImVec2){button_width, button_height})) {
        buffer->pre_trigger_samples = -1;
        buffer->in_use = false;
        for (i32 i = 0; i < NR_SAMPLES; i += 1) {
            buffer->data[i] = 0;
        }
    }
    igSameLine();
    if (igButtonEx("Export...", (ImVec2){button_width, button_height})) {
        state.export_modal.pre_trig = state.buffers[*buffer_idx].pre_trigger_samples;
        init_export_modal(*buffer_idx);
    }
    igPopStyleVar();

    // TODO: implement
    // igSameLine();
    // if (igButtonEx("Import", (ImVec2){button_width, button_height})) {
    // }
    return 0;
}

// -----------------------------------------------------------------------------
// Configuration View
// -----------------------------------------------------------------------------

void draw_config_menu(ImVec2 origin) {
    f32 offset  = 26;

    f32 add_x   = 1;
    f32 hide_x  = 34;
    f32 name_x  = 32 + offset;
    f32 width_x = 207 + offset;
    f32 msb_x   = 198 + offset;
    f32 lsb_x   = 227 + offset;
    f32 fmt_x   = 303 + offset;
    f32 trig1_x = 268 + 98 + offset;
    f32 trig2_x = 378 + 98 + offset;
    f32 trig3_x = 488 + 98 + offset;
    f32 trig4_x = 598 + 98 + offset;

    igSetCursorScreenPos(origin);

    // Column Titles
    igSetCursorScreenPos((ImVec2){origin.x + hide_x, origin.y});
    igText("H");

    igSetCursorScreenPos((ImVec2){origin.x + name_x, origin.y});
    igText("Signal Name");

    igSetCursorScreenPos((ImVec2){origin.x + width_x, origin.y});
    igText("width");

    igSetCursorScreenPos((ImVec2){origin.x + fmt_x, origin.y});
    igText("format");

    for (i32 i = 3; i >= 0; i -= 1) {
        if (state.comparators[i] != COMPARATOR[0]) {
            state.trigger_len = i;
            break;
        }
    }

    igSetCursorScreenPos((ImVec2){origin.x + trig1_x, origin.y});
    igText("Trig 1");
    igSetCursorScreenPos((ImVec2){origin.x + trig1_x + 50, origin.y - 3});
    comparator_combo_box("##combo1", 0, 1, NR_COMPARATORS + 1);

    if (state.trigger_len == 0) {
        igPushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 50));
    }
    igSetCursorScreenPos((ImVec2){origin.x + trig2_x, origin.y});
    igText("Trig 2");
    igSetCursorScreenPos((ImVec2){origin.x + trig2_x + 50, origin.y - 3});
    comparator_combo_box("##combo2", 1, 0, NR_COMPARATORS + 1);

    if (state.trigger_len == 1) {
        igPushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 50));
    }
    igSetCursorScreenPos((ImVec2){origin.x + trig3_x, origin.y});
    igText("Trig 3");
    igSetCursorScreenPos((ImVec2){origin.x + trig3_x + 50, origin.y - 3});
    comparator_combo_box("##combo3", 2, 0, NR_COMPARATORS + 1);

    if (state.trigger_len == 2) {
        igPushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 50));
    }
    igSetCursorScreenPos((ImVec2){origin.x + trig4_x, origin.y});
    igText("Trig 4");
    igSetCursorScreenPos((ImVec2){origin.x + trig4_x + 50, origin.y - 3});
    comparator_combo_box("##combo4", 3, 0, NR_COMPARATORS + 1);

    if (state.trigger_len != 3) {
        igPopStyleColor();
    }

    // + button
    igPushStyleColor(ImGuiCol_Button, IM_COL32(120, 180, 120, 255));
    igPushStyleColor(ImGuiCol_ButtonHovered, IM_COL32(140, 240, 140, 255));
    igPushStyleColor(ImGuiCol_ButtonActive, IM_COL32(180, 240, 180, 255));
    igPushStyleVar(ImGuiStyleVar_FrameRounding, BUTTON_RADIUS);

    igSetCursorScreenPos((ImVec2){origin.x + add_x, origin.y - 3});

    bool button_disabled = false;
    if (state.acc_signal_width >= 64 || state.nr_signals >= MAX_SIGNALS) {
        button_disabled = true;
        igBeginDisabled(true);
        igPushStyleVar(ImGuiStyleVar_Alpha, 0.2);
    }

    if (igButtonEx("+", (ImVec2){19, 19})) {
        sprintf(str_buf, "Signal %d", state.nr_signals);
        strcpy(state.signals[state.nr_signals].name, str_buf);
        add_empty_signal();
    }

    if (button_disabled) {
        igPopStyleVar();
        igEndDisabled();
    }

    igPopStyleVar();
    igPopStyleColor();
    igPopStyleColor();
    igPopStyleColor();
}

void draw_trigger_frame_config(i32 nr, ImVec2 pos) {
    for (u32 w = 0; w < state.nr_signals; w += 1) {
        pos.y += state.signals[w].y_offset;
        igSetCursorScreenPos(pos);

        sprintf(str_buf, "##checkbox%d%d", nr, w);

        // if comparator is '==': use checkboxes
        if (state.comparators[nr] == COMPARATOR[0]) {
            state.signals[w].use_in_trigger[nr] = false;
            igDummy((ImVec2){19, 19});

        } else if (state.comparators[nr] == COMPARATOR[1]) {
            igCheckbox(str_buf, &state.signals[w].use_in_trigger[nr]);

        } else {
            if (igRadioButton(str_buf, state.signals[w].use_in_trigger[nr])) {
                state.signals[w].use_in_trigger[nr] = !state.signals[w].use_in_trigger[nr];
                for (i32 i = 0; i < state.nr_signals; i += 1) {
                    if (w == i) {
                        continue;
                    }
                    state.signals[i].use_in_trigger[nr] = false;
                }
            }
        }
        igSameLine();

        if (!state.signals[w].use_in_trigger[nr]) {
            igPushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 50));
        }
        igSetNextItemWidth(66);
        sprintf(str_buf, "##ref%d%d", nr, w);

        if (state.signals[w].data_format == Hex) {
            // Hex Input Field
            sprintf(str_buf2, "%" PRIx64, state.signals[w].trig_ref[nr]);
            if (igInputText(str_buf, str_buf2, 17, ImGuiInputTextFlags_CharsHexadecimal)) {
                hex_upper_bound(state.signals[w].msb - state.signals[w].lsb + 1, str_buf2);
                hex_remove_leading_zeroes(str_buf2);
                u64 res;
                parse_hex_len_unknown(str_buf2, &res);
                state.signals[w].trig_ref[nr] = res;
            }
        } else if (state.signals[w].data_format == Dec) {
            // Dec Input Field
            sprintf(str_buf2, "%" PRId64, state.signals[w].trig_ref[nr]);
            if (igInputText(str_buf, str_buf2, 21, ImGuiInputTextFlags_CharsDecimal)) {
                u64 res = dec_upper_bound(state.signals[w].msb - state.signals[w].lsb + 1, str_buf2);
                state.signals[w].trig_ref[nr] = res;
            }
        } else if (state.signals[w].data_format == Bin) {
            // Bin Input Field
            char* str_val = binary_print(state.signals[w].trig_ref[nr]);
            if (igInputTextEx(str_buf, str_val, 65, ImGuiInputTextFlags_CallbackCharFilter, binary_filter, NULL)) {
                u64 res = bin_upper_bound(state.signals[w].msb - state.signals[w].lsb + 1, str_val);
                state.signals[w].trig_ref[nr] = res;
            }
        } else {
            assert(2 == 1);
        }

        if (!state.signals[w].use_in_trigger[nr]) {
            igPopStyleColor();
        }
        pos.y -= state.signals[w].y_offset;

        pos.y += ROW_HEIGHT;
    }
}

void draw_delete_controls(ImVec2 pos) {
    // delete button style
    igPushStyleVar(ImGuiStyleVar_FrameRounding, BUTTON_RADIUS);
    igPushStyleColor(ImGuiCol_Button, IM_COL32(240, 100, 100, 255));
    igPushStyleColor(ImGuiCol_ButtonHovered, IM_COL32(240, 140, 140, 255));
    igPushStyleColor(ImGuiCol_ButtonActive, IM_COL32(240, 180, 180, 255));

    for (u32 w = 0; w < state.nr_signals; w += 1) {
        pos.y += state.signals[w].y_offset;
        igSetCursorScreenPos(pos);
        sprintf(str_buf, "-##%d", w);
        if (igButtonEx(str_buf, (ImVec2){19, 19})) {
            delete_signal_next_frame(w);
        }
        pos.y -= state.signals[w].y_offset;

        pos.y += ROW_HEIGHT;
    }

    // A dummy is used as padding at the scrollpane bottom.
    // This keeps the scrollpane stable when swapping the lowest two rows
    if (state.nr_signals > 0) {
        pos.y -= ROW_HEIGHT;
        igSetCursorScreenPos(pos);
        igDummy((ImVec2){0, 20});
    }

    igPopStyleColor();
    igPopStyleColor();
    igPopStyleColor();
    igPopStyleVar();
}

void draw_hide_controls(ImVec2 pos) {
    for (u32 w = 0; w < state.nr_signals; w += 1) {
        pos.y += state.signals[w].y_offset;
        igSetCursorScreenPos(pos);
        sprintf(str_buf, "##hide%d", w);
        igCheckbox(str_buf, &state.signals[w].hide);
        pos.y -= state.signals[w].y_offset;
        pos.y += ROW_HEIGHT;
    }
}

void draw_swap_controls(ImVec2 pos) {

    // up / down button style
    igPushStyleVar(ImGuiStyleVar_FrameRounding, BUTTON_RADIUS);
    igPushStyleColor(ImGuiCol_Button, IM_COL32(160, 160, 160, 255));
    igPushStyleColor(ImGuiCol_ButtonHovered, IM_COL32(180, 180, 180, 255));
    igPushStyleColor(ImGuiCol_ButtonActive, IM_COL32(220, 220, 220, 255));

    ImVec2 tmp_pos = pos;
    for (u32 w = 0; w < state.nr_signals; w += 1) {
        tmp_pos.y += state.signals[w].y_offset;
        if (w == 0) {
            igBeginDisabled(true);
            igPushStyleVar(ImGuiStyleVar_Alpha, 0.2);
            igSetCursorScreenPos(tmp_pos);
            sprintf(str_buf, "up##%d", w);
            igArrowButton(str_buf, ImGuiDir_Up);
            igPopStyleVar();
            igEndDisabled();
        } else {
            igSetCursorScreenPos(tmp_pos);
            sprintf(str_buf, "up##%d", w);
            if (igArrowButton(str_buf, ImGuiDir_Up)) {
                swap_signals_next_frame(w - 1, w);
            }
        }
        tmp_pos.y -= state.signals[w].y_offset;

        tmp_pos.y += ROW_HEIGHT;
    }

    igSameLine();
    tmp_pos = igGetCursorScreenPos();
    tmp_pos.y = pos.y;

    for (u32 w = 0; w < state.nr_signals; w += 1) {
        tmp_pos.y += state.signals[w].y_offset;
        if (w == state.nr_signals - 1) {
            igBeginDisabled(true);
            igPushStyleVar(ImGuiStyleVar_Alpha, 0.2);
            igSetCursorScreenPos(tmp_pos);
            sprintf(str_buf, "down##%d", w);
            igArrowButton(str_buf, ImGuiDir_Down);
            igPopStyleVar();
            igEndDisabled();
        } else {
            igSetCursorScreenPos(tmp_pos);
            sprintf(str_buf, "down##%d", w);
            if (igArrowButton(str_buf, ImGuiDir_Down)) {
                swap_signals_next_frame(w, w + 1);
            }
        }
        tmp_pos.y -= state.signals[w].y_offset;

        tmp_pos.y += ROW_HEIGHT;
    }

    igPopStyleColor();
    igPopStyleColor();
    igPopStyleColor();
    igPopStyleVar();
}

f32 draw_configuration_window() {
    ImGuiIO* io = igGetIO();
    igPushStyleColor(ImGuiCol_ScrollbarBg, IM_COL32(0, 0, 0, 0));
    igPushStyleColor(ImGuiCol_WindowBg, WINDOW_BG);

    i32 window_flags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoTitleBar;
    igBegin("Trigger Configuration", 0, window_flags);
    igPopStyleColor();

    ImVec2 origin = igGetCursorScreenPos();
    f32 x_avail = igGetContentRegionAvail().x;

    // import / export --------------------------------------------------------
    f32 button_w = 120;
    f32 button_h = 19;
    igPushStyleVar(ImGuiStyleVar_FrameRounding, BUTTON_RADIUS);

    if (igButtonEx("Import Config", (ImVec2){button_w, button_h})) {
        Import_Result res = read_configuration_toml(&state);
        if (res == Error) {
            init_info_modal("Not a valid configuration file.");
        }
    }
    igSameLine();
    if (igButtonEx("Export Config", (ImVec2){button_w, button_h})) {
        write_configuration_toml(&state);
    }
    igPopStyleVar();

    // pre-trigger menu -------------------------------------------------------
    igSameLine();
    igText("Pre-Trigger Samples");
    igSameLine();
    igSetNextItemWidth(100);

    sprintf(str_buf, "%u", (u32)state.pre_trigger_samples);
    if (igInputInt("##pre-trig-val", &state.pre_trigger_samples)) {
        state.pre_trigger_samples = _min(511, state.pre_trigger_samples);
        state.pre_trigger_samples = _max(0, state.pre_trigger_samples);
    }

    igSameLine();

    f32 min_x = igGetCursorPosX();

    // toggle diff button
    char* label = "toggle diff-view";
    ImVec2 buttonSize = igCalcTextSize(label);
    buttonSize.x += igGetStyle()->FramePadding.x * 2.0f;
    buttonSize.y += igGetFrameHeight() - igGetStyle()->FramePadding.y * 2.0f;
    f32 avail = igGetContentRegionAvail().x;
    f32 x = _max(min_x, min_x + avail - buttonSize.x);
    igSetCursorPosX(x);
    igPushStyleVar(ImGuiStyleVar_FrameRounding, BUTTON_RADIUS);
    if (igButton("toggle diff-view")) {
        state.diff_view_open = !state.diff_view_open;
    }
    igPopStyleVar();

    igSpacing();
    igSeparator();
    igSpacing();

    igPushStyleVarImVec2(ImGuiStyleVar_WindowPadding, (ImVec2){0, 0});
    igPushStyleVar(ImGuiStyleVar_ChildBorderSize, 1);

    // config menu ------------------------------------------------------------
    ImVec2 config_pos = igGetCursorScreenPos();
    draw_config_menu(config_pos);

    // wire scrolltable -------------------------------------------------------
    if (igBeginChild("wire_scroll", (ImVec2){igGetContentRegionAvail().x, igGetContentRegionAvail().y/* - ROW_HEIGHT - 4*/}, 1, ImGuiWindowFlags_None)) {
        ImVec2 wire_pos = igGetCursorScreenPos();
        wire_pos.x += 1;

        draw_delete_controls(wire_pos);

        wire_pos.x += 27;
        draw_hide_controls(wire_pos);

        wire_pos.x += 26;
        ImVec2 trig1_pos = (ImVec2){wire_pos.x + 240 + 98, wire_pos.y};
        ImVec2 trig2_pos = (ImVec2){wire_pos.x + 240 + 110 + 98, wire_pos.y};
        ImVec2 trig3_pos = (ImVec2){wire_pos.x + 240 + 220 + 98, wire_pos.y};
        ImVec2 trig4_pos = (ImVec2){wire_pos.x + 240 + 330 + 98, wire_pos.y};

        // signal configuration
        for (u32 s = 0; s < state.nr_signals; s += 1) {

            wire_pos.y += state.signals[s].y_offset;
            igSetCursorScreenPos(wire_pos);

            bool must_pop_style = false;

            igPushItemWidth(160);
            sprintf(str_buf, "##interpretation_label%d", s);
            igInputText(str_buf, state.signals[s].name, SIGNAL_NAME_LEN, ImGuiInputTextFlags_None);

            igPushItemWidth(24);

            igSameLine();
            igSetCursorPosX(igGetCursorPosX() + 8);
            sprintf(str_buf, "##width%d", s);
            i32 prev_width = state.signals[s].width;
            if (igInputScalar(str_buf, ImGuiDataType_U8, &state.signals[s].width)) {
                i32 max_width = 64 - (state.acc_signal_width - prev_width);
                state.signals[s].width = _min(max_width, state.signals[s].width);
                state.signals[s].width = _max(1, state.signals[s].width);
                for (i32 t = 0; t < NR_TRIGGERS; t += 1) {
                    u64 max_val = 1 << state.signals[s].width;
                    state.signals[s].trig_ref[t] = _min(max_val, state.signals[s].trig_ref[t]);
                }
                update_signal_width(s, prev_width);
            }

            igSameLine();
            igText("[%2d:%2d]", state.signals[s].msb, state.signals[s].lsb);

            igSameLine();
            f32 x_pos = igGetCursorPosX();
            igSetCursorPosX(x_pos + 7);
            sprintf(str_buf, "##data_fmt%d", s);
            data_format_combo_box(str_buf, &state.signals[s]);


            wire_pos.y = wire_pos.y - state.signals[s].y_offset + ROW_HEIGHT;

            if (must_pop_style) {
                igPopStyleColor();
            }
        }

        draw_trigger_frame_config(0, trig1_pos);

        if (state.trigger_len == 0) {
            igPushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 50));
        }
        draw_trigger_frame_config(1, trig2_pos);
        if (state.trigger_len == 1) {
            igPushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 50));
        }
        draw_trigger_frame_config(2, trig3_pos);
        if (state.trigger_len == 2) {
            igPushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 50));
        }
        draw_trigger_frame_config(3, trig4_pos);
        if (state.trigger_len != 3) {
            igPopStyleColor();
        }

        draw_swap_controls((ImVec2){trig4_pos.x + 110, trig4_pos.y});

    }
    igPopStyleVar();
    igPopStyleVar();
    igEndChild();

    igPopStyleColor(); // Scrollbar_Bg

    f32 height = igGetWindowHeight();
    igEnd();

    return height;
}

// -----------------------------------------------------------------------------
// Main View
// -----------------------------------------------------------------------------

void clip_x_pos() {
    state.x_offset = _min(0, state.x_offset);
    state.x_offset = _max(-state.width + state.wave_table_width, state.x_offset);
}

void scroll_zoom(ImVec2 pos_waves) {
    ImGuiIO* io = igGetIO();
    ImVec2 avail = igGetContentRegionAvail();
    if (io->KeyShift) {
        f32 old_width = state.width;
        f32 inset = igGetMousePos().x - pos_waves.x;
        f32 zoom_center = -state.x_offset + inset;
        state.width += ((state.width * ZOOM_SENSITIVITY) / avail.x) * io->MouseWheel / (avail.x * 2);
        state.width = _max(state.width, 20000);
        state.x_offset = -(zoom_center / old_width * state.width - inset);

    } else {
        state.x_offset += io->MouseWheelH * SCROLL_SENSITIVITY;
    }
    clip_x_pos();
}

// ----------------------------------------------------------------------------
// waves are drawn here (wires are single bit waves, busses are multi bit waves)

void wire_low(ImDrawList* draw_list, f32 left, f32 right, f32 bottom, i32 buf_idx) {
    left = round(left) + WAVE_CLOCK_OFFSET;
    right = round(right) + WAVE_CLOCK_OFFSET;
    ImDrawList_AddRectFilled(draw_list, (ImVec2){left, bottom - 2}, (ImVec2){right, bottom}, BUFFER_COLOR_A[buf_idx]);
}

void wire_high(ImDrawList* draw_list, f32 left, f32 right, f32 top, i32 buf_idx) {
    left = round(left) + WAVE_CLOCK_OFFSET;
    right = round(right) + WAVE_CLOCK_OFFSET;
    ImDrawList_AddRectFilled(draw_list, (ImVec2){left, top}, (ImVec2){right, top + 2}, BUFFER_COLOR_A[buf_idx]);
}

void wire_up(ImDrawList* draw_list, f32 left, f32 right, f32 top, f32 bottom, i32 buf_idx) {
    left = round(left) + WAVE_CLOCK_OFFSET;
    right = round(right) + WAVE_CLOCK_OFFSET;

    ImVec2 points[4] = {{(f32)(i32)left - 1, bottom}, {left + 6, top}, {left + 8, top}, {left + 1, bottom}};
    ImDrawList_AddConvexPolyFilled(draw_list, &points[0], 4, BUFFER_COLOR_A[buf_idx]);

    ImDrawList_AddRectFilled(draw_list, (ImVec2){left + 7, top}, (ImVec2){right, top + 2}, BUFFER_COLOR_A[buf_idx]);
}

void wire_down(ImDrawList* draw_list, f32 left, f32 right, f32 top, f32 bottom, i32 buf_idx, i32 prev_buf_idx) {
    left = round(left) + WAVE_CLOCK_OFFSET;
    right = round(right) + WAVE_CLOCK_OFFSET;

    ImDrawList_AddQuadFilled(draw_list, (ImVec2){left - 1, top}, (ImVec2){left + 1, top}, (ImVec2){left + 8, bottom}, (ImVec2){left + 6, bottom}, BUFFER_COLOR_A[prev_buf_idx]);
    ImDrawList_AddRectFilled(draw_list, (ImVec2){left + 6, bottom - 2}, (ImVec2){right, bottom}, BUFFER_COLOR_A[buf_idx]);
}

void single_wire(ImDrawList* draw_list, u64 val, u64 val_prev, i32 buf_idx, i32 buf_idx_prev, f32 left, f32 right, f32 top, f32 bottom) {
    if (val_prev == 0) {
        if (val == 0) {
            wire_low(draw_list, left, right, bottom, buf_idx);
        } else {
            wire_up(draw_list, left, right, top, bottom, buf_idx);
        }
    } else {
        if (val == 0) {
            wire_down(draw_list, left, right, top, bottom, buf_idx, buf_idx_prev);
        } else {
            wire_high(draw_list, left, right, top, buf_idx);
        }
    }
}

void bus_high(ImDrawList* draw_list, f32 left, f32 right, f32 top, f32 bottom, i32 buf_idx) {
    left = round(left) + WAVE_CLOCK_OFFSET;
    right = round(right) + WAVE_CLOCK_OFFSET;
    ImDrawList_AddRectFilled(draw_list, (ImVec2){left, top}, (ImVec2){right, bottom}, BUFFER_COLOR_A[buf_idx]);
}

void bus_up(ImDrawList* draw_list, f32 left, f32 right, f32 top, f32 bottom, i32 buf_idx) {
    left = round(left) + WAVE_CLOCK_OFFSET;
    right = round(right) + WAVE_CLOCK_OFFSET;
    ImDrawList_AddQuadFilled(draw_list, (ImVec2){left - 1, bottom}, (ImVec2){left + 6, top}, (ImVec2){right, top}, (ImVec2){right, bottom}, BUFFER_COLOR_A[buf_idx]);
}

void bus_down(ImDrawList* draw_list, f32 left, f32 right, f32 top, f32 bottom, i32 buf_idx, i32 prev_buf_idx) {
    left = round(left) + WAVE_CLOCK_OFFSET;
    right = round(right) + WAVE_CLOCK_OFFSET;
    ImDrawList_AddQuadFilled(draw_list, (ImVec2){left, top}, (ImVec2){left + 6, bottom - 2}, (ImVec2){left + 6, bottom}, (ImVec2){left, bottom}, BUFFER_COLOR_A[prev_buf_idx]);
    ImDrawList_AddRectFilled(draw_list, (ImVec2){left + 6, bottom - 2}, (ImVec2){right, bottom}, BUFFER_COLOR_A[buf_idx]);
}

void bus_change(ImDrawList* draw_list, f32 left, f32 right, f32 top, f32 bottom, i32 buf_idx, i32 prev_buf_idx) {
    left = round(left) + WAVE_CLOCK_OFFSET;
    right = round(right) + WAVE_CLOCK_OFFSET;
    ImVec2 points[6] = {
        {left, bottom},
        {left, top},
        {left + 4, top + (bottom - top) / 2},
        {left + 8, top},
        {left + 8, bottom},
    };
    ImDrawList_AddConvexPolyFilled(draw_list, &points[0], 3, BUFFER_COLOR_A[prev_buf_idx]);
    ImDrawList_AddConvexPolyFilled(draw_list, &points[2], 3, BUFFER_COLOR_A[buf_idx]);
    ImDrawList_AddRectFilled(draw_list, (ImVec2){left + 8, top}, (ImVec2){right, bottom}, BUFFER_COLOR_A[buf_idx]);
}

void multi_wire(ImDrawList* draw_list, u64 val, u64 val_prev, i32 buf_idx, i32 buf_idx_prev, f32 left, f32 right, f32 top, f32 bottom) {
    if (val_prev == 0) {
        if (val == 0) {
            wire_low(draw_list, left, right, bottom, buf_idx);
        } else {
            bus_up(draw_list, left, right, top, bottom, buf_idx);
        }
    } else {
        if (val == 0) {
            bus_down(draw_list, left, right, top, bottom, buf_idx, buf_idx_prev);
        } else if (val_prev == val) {
            bus_high(draw_list, left, right, top, bottom, buf_idx);
        } else {
            bus_change(draw_list, left, right, top, bottom, buf_idx, buf_idx_prev);
        }
    }
}

void draw_waves_table(ImDrawList* draw_list, i32* buffer_idx, ImVec2 pos_waves,
                      bool do_scroll, bool show_diff) {

    i32 visible_signals = state.nr_signals;
    for (i32 i = 0; i < state.nr_signals; i += 1) {
        if (state.signals[i].hide) {
            visible_signals -= 1;
        }
    }
    Buffer* buffer = &state.buffers[*buffer_idx];
    Buffer* other_buffer = &state.buffers[1 - *buffer_idx];

    ImVec2 wind_avail = igGetContentRegionAvail();
    ImVec2 top_left = pos_waves;
    ImVec2 bottom_right = (ImVec2){pos_waves.x + wind_avail.x, pos_waves.y + wind_avail.y};
    f32 pos_x = igGetCursorPos().x;


    // Scrolling & Zooming
    igSetCursorScreenPos(pos_waves);
    if (!state.export_modal.open && !state.info_modal.open && do_scroll) {
        scroll_zoom(pos_waves);
    }
    ImGuiIO* io = igGetIO();
    if (igIsMouseHoveringRect(top_left, bottom_right) && !io->KeyShift) {
        bool can_scroll = !state.capture_modal.open && !state.export_modal.open && !state.info_modal.open;
        if (can_scroll && fabsf(io->MouseWheel) > fabsf(io->MouseWheelH)) {
            state.wave_table_y_offset += io->MouseWheel * SCROLL_SENSITIVITY_V;
        }
    }
    ImVec2 avail = igGetContentRegionAvail();

    f32 content_height = avail.y - 28 - 19;
    state.wave_table_y_offset = _max(content_height - visible_signals * ROW_HEIGHT, state.wave_table_y_offset);
    state.wave_table_y_offset = _min(0, state.wave_table_y_offset);
    ImVec2 signal_name_pos = (ImVec2){pos_x, pos_waves.y + ROW_HEIGHT + state.wave_table_y_offset};


    state.wave_table_width = avail.x;
    f32 left_clip = pos_waves.x;
    f32 right_clip = pos_waves.x + avail.x;
    f32 bottom_clip = pos_waves.y + avail.y - 28;

    // table border
    ImDrawList_AddRectFilled(draw_list, (ImVec2){pos_waves.x - 1, pos_waves.y - 1}, (ImVec2){right_clip + 1, bottom_clip + 1}, IM_COL32(255, 255, 255, 80));
    igPushClipRect(pos_waves, (ImVec2){right_clip, bottom_clip}, true);
    ImDrawList_AddRectFilled(draw_list, pos_waves, (ImVec2){right_clip, bottom_clip}, DARK_BG);
    ImDrawList_AddRectFilled(draw_list, pos_waves, (ImVec2){pos_waves.x + avail.x, pos_waves.y + 19}, HEADER);
    ImDrawList_AddRectFilled(draw_list, (ImVec2){pos_waves.x, pos_waves.y + 18}, (ImVec2){pos_waves.x + avail.x, pos_waves.y + 19}, IM_COL32(255, 255, 255, 30));
    f32 cycle_width = state.width / NR_SAMPLES;
    f32 header_top = pos_waves.y;
    f32 header_bottom = header_top + 19;
    f32 left = pos_waves.x + state.x_offset;
    f32 right;

    f32 top = pos_waves.y;
    f32 bottom = pos_waves.y + 19;
    top += state.wave_table_y_offset;
    bottom += state.wave_table_y_offset;

    for (u32 i = 0; i < NR_SAMPLES; i += 1) {
        right = left + cycle_width;

        // clip
        if (left > right_clip) { break; }
        if (right < 0) {
            left = right;
            continue;
        }

        // trigger indicator
        if (i == state.pre_trigger_samples - state.trigger_len) {
            ImDrawList_AddRectFilled(draw_list, (ImVec2){left, header_top}, (ImVec2){right + (right - left) * state.trigger_len, header_bottom - 1}, TRIGGER_BG);
            ImDrawList_AddRectFilled(draw_list, (ImVec2){left + cycle_width * state.trigger_len, header_top}, (ImVec2){right + cycle_width * state.trigger_len, header_bottom - 1}, TRIGGER_BG2);
        }

        // table header
        if (state.relative_cycle_nrs) {
            i32 cycle = i - state.pre_trigger_samples;

            if (cycle >= 0) {
                sprintf(str_buf, "%d", cycle);
                ImDrawList_AddText(draw_list, (ImVec2){right + nr_right_align(cycle, Dec), header_top + 2}, IM_COL32(255, 255, 255, 195), str_buf);
            } else {
                sprintf(str_buf, "-%d", -cycle);
                ImDrawList_AddText(draw_list, (ImVec2){right + nr_right_align(-cycle << 4, Dec), header_top + 2}, IM_COL32(255, 255, 255, 195), str_buf);
            }

        } else {
            sprintf(str_buf, "%x", i);
            ImDrawList_AddText(draw_list, (ImVec2){right + nr_right_align(i, Hex), header_top + 2}, IM_COL32(255, 255, 255, 155), str_buf);
        }

        // cycle background
        if (i % 2 == 0) {
            ImDrawList_AddRectFilled(draw_list, (ImVec2){left, top + 19}, (ImVec2){right, bottom + visible_signals * ROW_HEIGHT}, LIGHT_BG);
        }

        left = right;
    }

    f32 row_top = pos_waves.y + state.wave_table_y_offset + ROW_HEIGHT;
    f32 row_bottom = row_top + 19;
    for (i32 i = 0; i < state.nr_signals; i += 1) {
        if (state.signals[i].hide) {
            continue;
        }
        ImDrawList_AddRectFilled(draw_list, (ImVec2){pos_waves.x, row_top}, (ImVec2){right_clip, row_bottom}, IM_COL32(255, 255, 255, 10));
        ImDrawList_AddRectFilled(draw_list, (ImVec2){pos_waves.x, row_top - 4}, (ImVec2){right_clip, row_top}, DARK_BG);
        row_top += ROW_HEIGHT;
        row_bottom += ROW_HEIGHT;
    }

    igPopClipRect();

    left = pos_waves.x + state.x_offset;

    igPushClipRect((ImVec2){pos_waves.x, pos_waves.y + 19}, (ImVec2){right_clip, bottom_clip}, true);

    u64 prev_sample = buffer->data[0];
    u8 prev_buf_idx[MAX_SIGNALS] = {*buffer_idx};
    for (u32 i = 0; i < NR_SAMPLES; i += 1) {
        right = left + cycle_width;

        // clip
        if (left > right_clip) {
            break;
        }
        if (right < 0) {
            left = right;
            continue;
        }

        f32 t = top;
        f32 b = bottom;
        f32 txt_top = t + 3;

        // waves
        u64 curr_sample = buffer->data[i];
        for (u32 w = 0; w < state.nr_signals; w += 1) {
            if (state.signals[w].hide) {
                continue;
            }

            igDummy((ImVec2){cycle_width, 0});
            t += ROW_HEIGHT;
            b += ROW_HEIGHT;
            txt_top += ROW_HEIGHT;

            u64 val = curr_sample << (63 - state.signals[w].msb);
            val >>= (63 - state.signals[w].msb + state.signals[w].lsb);
            u64 prev_val = prev_sample << (63 - state.signals[w].msb);
            prev_val >>= (63 - state.signals[w].msb + state.signals[w].lsb);

            // diff color index
            u64 val_main = state.buffers[state.active_buffer].data[i];
            val_main <<= (63 - state.signals[w].msb);
            val_main >>= (63 - state.signals[w].msb + state.signals[w].lsb);
            u64 val_diff = state.buffers[state.active_diff_buffer].data[i];
            val_diff <<= (63 - state.signals[w].msb);
            val_diff >>= (63 - state.signals[w].msb + state.signals[w].lsb);
            u8 curr_buf_idx;
            if (val_main != val_diff && show_diff) {
                curr_buf_idx = 10;
            } else {
                curr_buf_idx = *buffer_idx;
            }

            char* nr_str = &str_buf[0];

            if (state.signals[w].width == 1) {
                single_wire(draw_list, val, prev_val, curr_buf_idx, prev_buf_idx[w], left, right, t, b);

            } else {
                multi_wire(draw_list, val, prev_val, curr_buf_idx, prev_buf_idx[w], left, right, t, b);
                if (val > 0) {
                    if (state.signals[w].data_format == Dec) {
                        sprintf(str_buf, "%" PRIu64, val);
                    } else if (state.signals[w].data_format == Hex) {
                        sprintf(str_buf, "%" PRIx64, val);
                    } else {
                        nr_str = binary_print(val);
                    }
                } else {
                    sprintf(nr_str, "%" PRIx64, val);
                }

                if (val > 0) {
                    ImDrawList_AddText(draw_list, (ImVec2){2 + right + nr_right_align(val, state.signals[w].data_format), txt_top}, IM_COL32(255, 255, 255, 255), nr_str);
                }
            }
            prev_buf_idx[w] = curr_buf_idx;
        }

        prev_sample = curr_sample;
        left = right;
    }
    igPopClipRect();

    // signal names
    igSetCursorScreenPos(signal_name_pos);
    ImVec2 clip_names_tl = (ImVec2){0, header_bottom};
    ImVec2 clip_names_br = (ImVec2){pos_waves.x, bottom_clip};
    igPushClipRect(clip_names_tl, clip_names_br, true);
    for (u32 w = 0; w < state.nr_signals; w += 1) {
        if (state.signals[w].hide) {
            continue;
        }
        igPushItemWidth(160);
        sprintf(str_buf, "##interpretation_label%d", w);
        igLabelText(str_buf, state.signals[w].name, 32, ImGuiInputTextFlags_ReadOnly);
        igPushItemWidth(22);
    }
    igPopClipRect();
}


void draw_buffer_window(char* window_title, i32* buffer_idx, bool do_scroll,
                     bool is_main, bool show_diff) {
    ImGuiIO* io = igGetIO();
    // Window init
    i32 window_flags = ImGuiWindowFlags_NoScrollbar |
                       ImGuiWindowFlags_NoScrollWithMouse |
                       ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoTitleBar;
    igPushStyleColor(ImGuiCol_WindowBg, WINDOW_BG_BUF);

    igBegin(window_title, 0, window_flags);
    if (igIsWindowCollapsed()) {
        igPopStyleColor();
        igEnd();
        return;
    }

    ImVec2 screen_pos = igGetCursorScreenPos();
    ImVec2 pos_waves = {screen_pos.x + 158 + 8/* + 70*/, screen_pos.y + 30};
    ImDrawList* draw_list = igGetWindowDrawList();
    buffer_tabs(buffer_idx, draw_list);

    // table
    draw_waves_table(draw_list, buffer_idx, pos_waves, do_scroll, show_diff);

    // buttons
    igPushStyleColor(ImGuiCol_ButtonHovered, BUFFER_COLOR[*buffer_idx]);
    igPushStyleColor(ImGuiCol_Button, BUFFER_COLOR_A[*buffer_idx]);
    igPushStyleColor(ImGuiCol_ButtonActive, BUFFER_COLOR_A[*buffer_idx]);
    buffer_button_menu(buffer_idx);
    igPopStyleColor();
    igPopStyleColor();
    igPopStyleColor();

    igPopStyleColor();

    igEnd();
}

// -----------------------------------------------------------------------------
// Sliding Minimap Window
// -----------------------------------------------------------------------------

void draw_minimap_window() {
    i32 window_flags = ImGuiWindowFlags_NoScrollbar |
                       ImGuiWindowFlags_NoScrollWithMouse |
                       ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize;
    igPushStyleColor(ImGuiCol_WindowBg, WINDOW_BG);
    igBegin("Minimap", 0, window_flags);
    igPopStyleColor();

    ImVec2 pos = igGetCursorScreenPos();

    ImVec2 avail = igGetContentRegionAvail();

    ImDrawList* draw_list = igGetWindowDrawList();

    // backgrounds & triggers
    f32 spacing = 4;
    f32 trig_width = avail.x / NR_SAMPLES;
    f32 trig_height = (avail.y - spacing) / 2;
    f32 trig_left = pos.x + state.pre_trigger_samples * trig_width;
    f32 trig_right = trig_left + trig_width;

    f32 top = pos.y;
    f32 bottom = top + trig_height;
    for (i32 i = 0; i < 2; i += 1) {
        ImDrawList_AddRectFilled(draw_list, (ImVec2){pos.x, top}, (ImVec2){pos.x + avail.x, bottom}, WINDOW_BG_BUF);
        top += trig_height + spacing;
        bottom += trig_height + spacing;
    }

    top = pos.y;
    bottom = pos.y + trig_height;

    Buffer* top_buf = &state.buffers[state.active_buffer];

    // upper minimap row
    u64 positive = top_buf->data[0] > 0;
    f32 left = pos.x;
    f32 right;
    f32 minimap_left = pos.x;
    f32 minimap_right = pos.x + avail.x;
    f32 minimap_top = top;
    f32 minimap_bottom = pos.y + avail.y;
    f32 minimap_width = minimap_right - minimap_left;
    ImVec2 minimap_top_left = (ImVec2){minimap_left, minimap_top};
    ImVec2 minimap_bottom_right = (ImVec2){minimap_right, minimap_bottom};

    for (i32 i = 0; i < NR_SAMPLES; i += 1) {
        if (positive != top_buf->data[i] > 0) {
            right = pos.x + i * trig_width;
            if (positive) {
                // end same segment
                ImDrawList_AddRectFilled(draw_list, (ImVec2){left, top}, (ImVec2){right, bottom}, BUFFER_COLOR_A[state.active_buffer]);
            }
            positive = !positive;
            left = right;
        }
    }
    if (positive) {
        // end same segment
        right = pos.x + NR_SAMPLES * trig_width;
        ImDrawList_AddRectFilled(draw_list, (ImVec2){left, top}, (ImVec2){right, bottom}, BUFFER_COLOR_A[state.active_buffer]);
    }

    // lower minimap row
    top += trig_height + spacing;
    bottom = top + trig_height;
    Buffer* bot_buf = &state.buffers[state.active_diff_buffer];
    positive = bot_buf->data[0] > 0;
    left = pos.x;

    for (i32 i = 0; i < NR_SAMPLES; i += 1) {
        if (positive != bot_buf->data[i] > 0) {
            right = pos.x + i * trig_width;
            if (positive) {
                // end same segment
                ImDrawList_AddRectFilled(draw_list, (ImVec2){left, top}, (ImVec2){right, bottom}, BUFFER_COLOR_A[state.active_diff_buffer]);
            }
            positive = !positive;
            left = right;
        }
    }
    if (positive) {
        // end same segment
        right = pos.x + NR_SAMPLES * trig_width;
        ImDrawList_AddRectFilled(draw_list, (ImVec2){left, top}, (ImVec2){right, bottom}, BUFFER_COLOR_A[state.active_diff_buffer]);
    }

    // config trigger rect
    if (state.pre_trigger_samples >= 0) {
        left = pos.x + state.pre_trigger_samples * trig_width;
        right = left + trig_width;
        ImDrawList_AddRectFilled(draw_list, (ImVec2){left, minimap_top}, (ImVec2){right, minimap_top + spacing + 2 * trig_height}, TRIGGER_BG2);
    }

    // edit trigger rect
    if (state.buffers[state.active_buffer].pre_trigger_samples >= 0) {
        left = pos.x +
               state.buffers[state.active_buffer].pre_trigger_samples * trig_width;
        right = left + trig_width;
        ImDrawList_AddRectFilled(draw_list, (ImVec2){left, minimap_top}, (ImVec2){right, minimap_top + trig_height}, TRIGGER_BG);
    }

    // diff trigger rect
    if (state.buffers[state.active_diff_buffer].pre_trigger_samples >= 0 &&
        state.active_buffer != state.active_diff_buffer) {
        top = minimap_top + trig_height + spacing;
        bottom = top + trig_height;
        left = pos.x + state.buffers[state.active_diff_buffer].pre_trigger_samples * trig_width;
        right = left + trig_width;
        ImDrawList_AddRectFilled(draw_list, (ImVec2){left, top}, (ImVec2){right, bottom}, TRIGGER_BG);
    }

    // thumb
    ImGuiIO* io = igGetIO();
    ImU32 thumb_color = MINIMAP_THUMB;
    left = -state.x_offset / state.width * avail.x + pos.x;
    right = (-state.x_offset + state.wave_table_width) / state.width * avail.x + pos.x;
    ImVec2 thumb_top_left = (ImVec2){left, pos.y - 3};
    ImVec2 thumb_bottom_right = (ImVec2){right, pos.y + avail.y + 3};
    ImVec2 thumb_text_top_center = (ImVec2){left + (right - left) / 2 - 9, pos.y};
    ImVec2 thumb_line_top_left = (ImVec2){left + (right - left) / 2 - 1, pos.y + avail.y / 2};
    ImVec2 thumb_line_bottom_right = (ImVec2){left + (right - left) / 2 + 1, pos.y + avail.y};
    if (state.minimap_drag_active) {
        state.x_offset -= io->MouseDelta.x / (minimap_right - pos.x) * state.width;
    } else if (igIsMouseHoveringRect(minimap_top_left, minimap_bottom_right) && io->MouseClicked[0]) {
        // jump directly to mouse cursor position
        state.x_offset = -(igGetMousePos().x - 8) / minimap_width * state.width + state.wave_table_width / 2;
    }
    clip_x_pos();
    char buf[17];
    if (state.minimap_drag_active) {
        thumb_color = MINIMAP_THUMB_HOVER;
        u32 center_sample = (-state.x_offset + state.wave_table_width / 2) / state.width * NR_SAMPLES;
        to_hex_string_thread_safe(center_sample, 3, buf);
        ImDrawList_AddText(draw_list, thumb_text_top_center, TITLE_FG, buf);
        ImDrawList_AddRect(draw_list, thumb_line_top_left, thumb_line_bottom_right, TITLE_FG);
    }
    if (igIsMouseHoveringRect(thumb_top_left, thumb_bottom_right)) {
        igSetMouseCursor(ImGuiMouseCursor_Hand);
        thumb_color = MINIMAP_THUMB_HOVER;
        if (io->MouseDown[0] && !state.minimap_drag_active) {
            // start drag
            state.minimap_drag_active = true;
        }
    }
    ImDrawList_AddRectFilled(draw_list, thumb_top_left, thumb_bottom_right, thumb_color);

    igEnd();
}
