// Dear ImGui: standalone example application for SDL2 + OpenGL
// (SDL is a cross-platform general purpose library for handling windows, inputs, OpenGL/Vulkan/Metal graphics context creation, etc.)
// If you are new to Dear ImGui, read documentation from the docs/ folder + read the top of imgui.cpp.
// Read online: https://github.com/ocornut/imgui/tree/master/docs

#include "imgui.h"
#include "imgui_impl_sdl.h"
#include "imgui_impl_opengl3.h"
#include <stdio.h>
#include <SDL.h>
#if defined(IMGUI_IMPL_OPENGL_ES2)
#include <SDL_opengles2.h>
#else
#include <SDL_opengl.h>
#endif

#include <queue>
#include <thread>

#include "im_file_picker.h"

#include "verilator_controller.h"
Controller *controller;

CPUState g_cpu_state;
DSPState g_dsp_state;
MemoryState g_memory_state;
AudioQueue *g_audio_queue;

void update_state()
{
  controller->getCPUState(&g_cpu_state);
  controller->getDSPState(&g_dsp_state);
  controller->getMemoryState(&g_memory_state);
}

void draw_gui()
{
  {
    ImGui::Begin("Global State");
    ImGui::Text("Simulator Cycles: %lu", controller->getCycleCount());

    if (ImGui::Button("Step"))
      controller->singleStep();
    ImGui::SameLine();
    if (ImGui::Button("Resume"))
      controller->resume();
    ImGui::SameLine();
    if (ImGui::Button("Stop"))
      controller->stop();
    ImGui::SameLine();
    if (ImGui::Button("Reset"))
      controller->reset();

    static ImFilePicker ram_file_picker(".");
    ram_file_picker.on_file_open = [&](const char *file_path)
    {
      controller->loadMemoryFromFile(file_path);
    };
    ImGui::Separator();
    ram_file_picker.draw();

    ImGui::End();
  }

  ImGui::Begin("DSP Internals");
  ImGui::Text("Major State: %u (0..63)", g_dsp_state.major_cycle);
  ImGui::Text("DSP Voice States");
  for (u8 i = 0; i < DSPState::num_voices; ++i)
  {
    static const char *voice_fsm_state_names[] = {
        "Init",
        "ReadHeader",
        "ReadData",
        "ProcessSample",
        "OutputAndWait",
        "End",
    };
    ImGui::Text("- Voice %u: %s ", i, voice_fsm_state_names[g_dsp_state.voice[i].fsm_state]);
  }
  ImGui::End();
}

// https://wiki.libsdl.org/SDL_AudioSpec#callback
void sdl_audio_callback(void *userdata, uint8_t *out_data, int length)
{
  const u32 available = g_audio_queue->availableFrames();
  if (!g_audio_queue || available < 4096)
  {
    printf("Audio underrun\n");
    fflush(stdout);
    memset(out_data, 0, length);
    return;
  }

  g_audio_queue->consumeFrames((int16_t *)out_data, 4096);
  fflush(stdout);
}

// Main code
int main(int, char **)
{
  // Setup SDL
  // (Some versions of SDL before <2.0.10 appears to have performance/stalling issues on a minority of Windows systems,
  // depending on whether SDL_INIT_GAMECONTROLLER is enabled or disabled.. updating to latest version of SDL is recommended!)
  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER) != 0)
  {
    printf("Error: %s\n", SDL_GetError());
    return -1;
  }

  // Decide GL+GLSL versions
#if defined(IMGUI_IMPL_OPENGL_ES2)
  // GL ES 2.0 + GLSL 100
  const char *glsl_version = "#version 100";
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, 0);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
#elif defined(__APPLE__)
  // GL 3.2 Core + GLSL 150
  const char *glsl_version = "#version 150";
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG); // Always required on Mac
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2);
#else
  // GL 3.0 + GLSL 130
  const char *glsl_version = "#version 130";
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, 0);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
#endif

  // Create window with graphics context
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
  SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
  SDL_WindowFlags window_flags = (SDL_WindowFlags)(SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
  SDL_Window *window = SDL_CreateWindow("SNES APU Hardware Simulation", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 1280, 720, window_flags);
  SDL_GLContext gl_context = SDL_GL_CreateContext(window);
  SDL_GL_MakeCurrent(window, gl_context);
  SDL_GL_SetSwapInterval(1); // Enable vsync

  // Setup Dear ImGui context
  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGuiIO &io = ImGui::GetIO();
  (void)io;
  // io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  // io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls

  // Setup Dear ImGui style
  ImGui::StyleColorsDark();
  // ImGui::StyleColorsClassic();

  // Setup Platform/Renderer backends
  ImGui_ImplSDL2_InitForOpenGL(window, gl_context);
  ImGui_ImplOpenGL3_Init(glsl_version);

  // Audio Init
  SDL_AudioDeviceID sdl_audio_dev;
  {
    SDL_AudioSpec desired = {};
    desired.channels = 2;
    desired.format = AUDIO_S16;
    desired.callback = sdl_audio_callback;
    desired.freq = 32000;
    desired.samples = 4096; // Buffer size in samples, must be PoT

    SDL_AudioSpec obtained;
    if (0 == (sdl_audio_dev = SDL_OpenAudioDevice(nullptr, 0, &desired, &obtained, 0)))
    {
      printf("Failed to initialize audio: %s\n", SDL_GetError());
      return 1;
    }
    else
    {
      printf("Obtained audio: chan=%u sample_rate=%u format=0x%x\n", obtained.channels, obtained.freq, obtained.format);
      SDL_PauseAudioDevice(sdl_audio_dev, 0); // unpause
    }
  }

  // Our state
  bool show_demo_window = true;
  bool show_another_window = false;
  ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

  g_audio_queue = new AudioQueue();

  controller = new VerilatorController();
  controller->setAudioQueue(g_audio_queue);

  // Main loop
  bool done = false;
  while (!done)
  {
    // Poll and handle events (inputs, window resize, etc.)
    // You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
    // - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application.
    // - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application.
    // Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
      ImGui_ImplSDL2_ProcessEvent(&event);
      if (event.type == SDL_QUIT)
        done = true;
      if (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_CLOSE && event.window.windowID == SDL_GetWindowID(window))
        done = true;
    }

    // Start the Dear ImGui frame
    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplSDL2_NewFrame();
    ImGui::NewFrame();

    // ImGui::ShowDemoWindow(&show_demo_window);
    update_state();
    draw_gui();

    // Rendering
    ImGui::Render();
    glViewport(0, 0, (int)io.DisplaySize.x, (int)io.DisplaySize.y);
    glClearColor(clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w);
    glClear(GL_COLOR_BUFFER_BIT);
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    SDL_GL_SwapWindow(window);
  }

  // Cleanup
  ImGui_ImplOpenGL3_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  ImGui::DestroyContext();

  SDL_GL_DeleteContext(gl_context);
  SDL_DestroyWindow(window);
  SDL_Quit();

  return 0;
}
