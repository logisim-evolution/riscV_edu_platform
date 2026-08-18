// source for sokol-cimgui starter-kit: https://github.com/floooh/cimgui-sokol-starterkit

//------------------------------------------------------------------------------
//  Simple C99 cimgui+sokol starter project for Win32, Linux and macOS.
//------------------------------------------------------------------------------
#include "cimgui/cimgui.h"
#include "source/utils.h"
#include "source/ui.h"

#define MINIMAP_HEIGHT 50

static void init(void) {

    sg_setup(&(sg_desc){
        .environment = sglue_environment(),
        .logger.func = slog_func,
    });
    simgui_setup(&(simgui_desc_t){ 0 });

    sokol_state.pass_action = (sg_pass_action) {
        .colors[0] = { .load_action = SG_LOADACTION_CLEAR, .clear_value = { 0.3f, 0.3f, 0.3f, 1.0 } }
    };
    init_state();
}

f32 buffer_window_height = 169;
f32 waves_window_height = 169;
f32 waves_window_diff_height = 169;

i32 redraw_counter = 10;

static void frame(void) {


    simgui_new_frame(&(simgui_frame_desc_t){
        .width = sapp_width(),
        .height = sapp_height(),
        .delta_time = sapp_frame_duration(),
        .dpi_scale = sapp_dpi_scale(),
    });

    /*=== UI CODE STARTS HERE ===*/

    // animations
    state.combobox_open = false;
    if (state.swap_signals) {
        state.swap_signals = false;
        swap_signals(state.swap_s1, state.swap_s2);
    }
    if (state.delete_signal) {
        state.delete_signal = false;
        delete_signal(state.delete_s);
    }
    for (i32 i = 0; i < state.nr_signals; i += 1) {
        if (state.signals[i].remaining_swap_frames > 0) {
            state.signals[i].remaining_swap_frames -= 1;
            state.signals[i].y_offset += state.signals[i].dy;
        } else {
            state.signals[i].y_offset = 0;
        }
    }

    // only allow one scroll direction at a time
    ImGuiIO* io = igGetIO();
    if (fabsf(io->MouseWheelH) > fabsf(io->MouseWheel)) {
        io->MouseWheel = 0;
    } else {
        io->MouseWheelH = 0;
    }

    if (!io->MouseDown[0]) {
        state.minimap_drag_active = false;
    } else {
        igSetMouseCursor(ImGuiMouseCursor_Hand);
    }
    ImVec2 mouse = igGetMousePos();
    ImGuiViewport* vp = igGetMainViewport();

    for (int i = 0; i < io->InputQueueCharacters.Size; i++) {
        ImWchar c = io->InputQueueCharacters.Data[i];
        if (c == '=') {
            state.diff_view_open = !state.diff_view_open;
        }
    }

    // separator drag
    bool hover_drag = fabsf(igGetMousePos().y - state.y_separator) < 4;
    if (hover_drag && igIsMouseDown(ImGuiMouseButton_Left)) {
        state.separator_drag = true;
        igSetMouseCursor(ImGuiMouseCursor_ResizeNS);
    }
    if (state.separator_drag) {
        state.y_separator = igGetMousePos().y;
    }
    if (!igIsMouseDown(ImGuiMouseButton_Left)) {
        state.separator_drag = false;
    }

    // spacing between windows
    f32 spacing = 0;
    state.y_separator = _min(state.y_separator, vp->Size.y / 3 * 2);
    state.y_separator = _max(state.y_separator, vp->Size.y / 6);


    // configuration window
    igSetNextWindowSize((ImVec2){vp->Size.x - 2 * spacing, state.y_separator}, 0);
    igSetNextWindowPos((ImVec2){spacing, spacing}, 0);
    f32 prev_height = draw_configuration_window() + 2 * spacing;

    // positioning and hovering checks
    f32 right = (vp->Size.x - spacing);
    f32 top = prev_height;
    f32 bottom = vp->Size.y;
    bool inside = (mouse.x > spacing) && (mouse.x < (vp->Size.x - spacing)) && (mouse.y > top) && (mouse.y < bottom);
    f32 minimap_y = vp->Size.y - spacing - MINIMAP_HEIGHT;
    f32 max_wave_height = ((minimap_y - prev_height - spacing) - spacing) / 2;
    f32 wave2_x = prev_height + max_wave_height + spacing;

    // minimap
    igSetNextWindowSize((ImVec2){vp->Size.x - 2 * spacing, MINIMAP_HEIGHT}, 0);
    igSetNextWindowPos((ImVec2){spacing, minimap_y}, 0);
    draw_minimap_window();

    if (!state.diff_view_open) {
        max_wave_height = max_wave_height * 2 + spacing;
    }

    // top buffer window
    igSetNextWindowSize((ImVec2){vp->Size.x - 2 * spacing, max_wave_height}, 0);
    igSetNextWindowPos((ImVec2){spacing, prev_height}, 0);
    draw_buffer_window("Main View", &state.active_buffer, inside, true, state.diff_view_open);
    prev_height += waves_window_height + spacing;

    // bottom buffer window

    if (state.diff_view_open) {
        igSetNextWindowSize((ImVec2){vp->Size.x - 2 * spacing, max_wave_height + 0.5}, 0);
        igSetNextWindowPos((ImVec2){spacing, wave2_x}, 0);
        draw_buffer_window("Diff View", &state.active_diff_buffer, false, false, state.diff_view_open);
        prev_height += waves_window_diff_height + spacing;
    }

    draw_info_modal();
    draw_export_modal();
    draw_capture_modal();

    if (hover_drag || state.separator_drag) {
        igSetMouseCursor(ImGuiMouseCursor_ResizeNS);
    }


    /*=== UI CODE ENDS HERE ===*/

    sg_begin_pass(&(sg_pass){
        .action = sokol_state.pass_action,
        .swapchain = sglue_swapchain()
    });
    simgui_render();
    sg_end_pass();
    sg_commit();
}

static void cleanup(void) {
    swrapTerminate();
    simgui_shutdown();
    sg_shutdown();
}

static void event(const sapp_event* ev) {
    simgui_handle_event(ev);
}

sapp_desc sokol_main(int argc, char* argv[]) {
    (void)argc;
    (void)argv;
    return (sapp_desc){
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .window_title = "Logic Analyzer",
        .width = 800,
        .height = 600,
        .icon.sokol_default = true,
        .logger.func = slog_func,
        .enable_clipboard = true,
        .clipboard_size = 65536,
    };
}
