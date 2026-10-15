#pragma once

#include <ctime>
#include <filesystem>
#include <optional>

namespace snap {

namespace fs = std::filesystem;

// True for macOS screenshot files ("Screenshot ....png"), false for the
// hidden temp files macOS writes before the final rename.
bool is_screenshot(const fs::path& p);

// Where `file` would land in the archive: <root>/YYYY-MM/<name>, with a
// " (2)", " (3)" ... suffix if that name is already taken. Never overwrites.
fs::path archive_destination(const fs::path& file, const fs::path& root, std::time_t when);

// Moves `file` into the archive. Returns the new path, or nullopt on failure.
std::optional<fs::path> archive(const fs::path& file, const fs::path& root);

// Most recently created screenshot directly inside `dir`, if any.
std::optional<fs::path> newest_screenshot(const fs::path& dir);

}  // namespace snap
