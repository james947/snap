#pragma once

#include <CoreServices/CoreServices.h>

#include <filesystem>
#include <functional>

namespace snap {

// Watches one folder (non-recursively) with FSEvents and calls back on the
// main queue whenever a screenshot file appears in it.
class Watcher {
public:
    using Callback = std::function<void(const std::filesystem::path&)>;

    Watcher(std::filesystem::path dir, Callback on_screenshot);
    ~Watcher();
    Watcher(const Watcher&) = delete;
    Watcher& operator=(const Watcher&) = delete;

    bool start();

private:
    static void handle(ConstFSEventStreamRef, void* info, size_t count, void* paths,
                       const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[]);

    std::filesystem::path dir_;
    Callback on_screenshot_;
    FSEventStreamRef stream_ = nullptr;
};

}  // namespace snap
