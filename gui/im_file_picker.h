#pragma once

#include "imgui.h"

#include <filesystem>
#include <functional>
#include <vector>

struct ImFilePicker
{
  ImFilePicker(const std::filesystem::path &start_folder) : m_current_folder(start_folder)
  {
    recompute();
  }

  void draw()
  {
    ImGui::BeginChild("FilePicker");
    ImGui::Text("Current Path: %s", m_current_folder.c_str());
    ImGui::SameLine();
    if (ImGui::Button("Refresh"))
      recompute();

    if (m_current_folder.has_parent_path())
    {
      ImGui::Text("[dir] ..");
      if (ImGui::IsItemClicked()) {
        m_current_folder = m_current_folder.parent_path();
        recompute();
      }
    }

    for (auto &entry : m_current_folder_directories)
    {
      ImGui::Text("[dir] %s", entry.filename().string().c_str());
      if (ImGui::IsItemClicked())
      {
        m_current_folder = entry;
        recompute();
        break;
      }
    }
    for (auto &entry : m_current_folder_files)
    {
      ImGui::Text("%s", entry.filename().string().c_str());
      if (ImGui::IsItemClicked() && on_file_open)
      {
        on_file_open(entry.string().c_str());
      }
    }
    ImGui::EndChild();
  }

  void recompute()
  {
    assert(std::filesystem::is_directory(m_current_folder));
    m_current_folder_files.clear();
    m_current_folder_directories.clear();

    for (const auto &entry : std::filesystem::directory_iterator{m_current_folder})
    {
      if (entry.is_regular_file())
        m_current_folder_files.push_back(entry);
      if (entry.is_directory())
        m_current_folder_directories.push_back(entry);
    }
  }

  std::function<void(const char *)> on_file_open;

  std::filesystem::path m_current_folder;
  std::vector<std::filesystem::path> m_current_folder_directories;
  std::vector<std::filesystem::path> m_current_folder_files;
};
