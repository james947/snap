#include "core/screenshot.hpp"

#include <sys/stat.h>

#include <algorithm>
#include <cctype>
#include <string>
#include <string_view>

namespace snap {

namespace {

std::time_t created_at(const fs::path& p) {
    struct stat st {};
    if (stat(p.c_str(), &st) != 0) return std::time(nullptr);
    return st.st_birthtimespec.tv_sec;
}

}  // namespace

bool is_screenshot(const fs::path& p) {
    const std::string name = p.filename().string();
    if (name.empty() || name[0] == '.') return false;

    auto starts_with = [&](std::string_view prefix) { return name.rfind(prefix, 0) == 0; };
    if (!starts_with("Screenshot ") && !starts_with("Screen Shot ")) return false;

    std::string ext = p.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) { return std::tolower(c); });
    return ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".heic";
}

fs::path archive_destination(const fs::path& file, const fs::path& root, std::time_t when) {
    std::tm tm{};
    localtime_r(&when, &tm);
    char month[8];
    std::strftime(month, sizeof month, "%Y-%m", &tm);

    const fs::path dir = root / month;
    fs::path dest = dir / file.filename();
    for (int n = 2; fs::exists(dest); ++n) {
        dest = dir / (file.stem().string() + " (" + std::to_string(n) + ")" + file.extension().string());
    }
    return dest;
}

std::optional<fs::path> archive(const fs::path& file, const fs::path& root) {
    std::error_code ec;
    const fs::path dest = archive_destination(file, root, created_at(file));
    fs::create_directories(dest.parent_path(), ec);
    if (ec) return std::nullopt;
    fs::rename(file, dest, ec);
    if (ec) return std::nullopt;
    return dest;
}

std::optional<fs::path> newest_screenshot(const fs::path& dir) {
    std::optional<fs::path> best;
    std::time_t best_time = 0;
    std::error_code ec;
    for (const auto& entry : fs::directory_iterator(dir, ec)) {
        if (!entry.is_regular_file(ec) || !is_screenshot(entry.path())) continue;
        const std::time_t t = created_at(entry.path());
        if (!best || t > best_time) {
            best = entry.path();
            best_time = t;
        }
    }
    return best;
}

}  // namespace snap
