#include <cstdio>
#include <fstream>
#include <unistd.h>

#include "core/screenshot.hpp"

namespace fs = std::filesystem;

static int failures = 0;

#define CHECK(expr)                                                     \
    do {                                                                \
        if (!(expr)) {                                                  \
            std::fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #expr); \
            ++failures;                                                 \
        }                                                               \
    } while (0)

static void touch(const fs::path& p) { std::ofstream(p) << "x"; }

int main() {
    // is_screenshot
    CHECK(snap::is_screenshot("/Users/x/Desktop/Screenshot 2026-10-14 at 3.42.11 PM.png"));
    CHECK(snap::is_screenshot("Screen Shot 2020-01-01 at 10.00.00 AM.PNG"));
    CHECK(!snap::is_screenshot(".Screenshot 2026-10-14 at 3.42.11 PM.png"));  // macOS temp file
    CHECK(!snap::is_screenshot("Screenshot notes.txt"));
    CHECK(!snap::is_screenshot("holiday.png"));

    // archive_destination: month folder from the timestamp
    std::tm tm{};
    tm.tm_year = 2026 - 1900;
    tm.tm_mon = 9;
    tm.tm_mday = 14;
    tm.tm_hour = 12;
    const std::time_t oct14 = std::mktime(&tm);
    CHECK(snap::archive_destination("/d/Screenshot a.png", "/arch", oct14) == fs::path("/arch/2026-10/Screenshot a.png"));

    // archive: moves the file, never overwrites on a name clash
    const fs::path tmp = fs::temp_directory_path() / ("snap-test-" + std::to_string(getpid()));
    const fs::path inbox = tmp / "inbox";
    const fs::path root = tmp / "archive";
    fs::create_directories(inbox);

    touch(inbox / "Screenshot a.png");
    auto first = snap::archive(inbox / "Screenshot a.png", root);
    CHECK(first && fs::exists(*first));
    CHECK(!fs::exists(inbox / "Screenshot a.png"));

    touch(inbox / "Screenshot a.png");
    auto second = snap::archive(inbox / "Screenshot a.png", root);
    CHECK(second && fs::exists(*second));
    CHECK(second && second->filename() == "Screenshot a (2).png");
    CHECK(first && fs::exists(*first));

    // newest_screenshot ignores non-screenshots
    touch(inbox / "notes.png");
    CHECK(!snap::newest_screenshot(inbox));
    touch(inbox / "Screenshot b.png");
    CHECK(snap::newest_screenshot(inbox) == inbox / "Screenshot b.png");

    fs::remove_all(tmp);  // only this test's own temp folder

    if (failures == 0) std::puts("all tests passed");
    return failures == 0 ? 0 : 1;
}
