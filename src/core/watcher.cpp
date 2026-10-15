#include "core/watcher.hpp"

#include <dispatch/dispatch.h>

#include "core/screenshot.hpp"

namespace snap {

Watcher::Watcher(std::filesystem::path dir, Callback on_screenshot)
    : dir_(std::filesystem::weakly_canonical(dir)), on_screenshot_(std::move(on_screenshot)) {}

Watcher::~Watcher() {
    if (!stream_) return;
    FSEventStreamStop(stream_);
    FSEventStreamInvalidate(stream_);
    FSEventStreamRelease(stream_);
}

bool Watcher::start() {
    CFStringRef path = CFStringCreateWithCString(nullptr, dir_.c_str(), kCFStringEncodingUTF8);
    CFArrayRef paths = CFArrayCreate(nullptr, reinterpret_cast<const void**>(&path), 1, &kCFTypeArrayCallBacks);
    FSEventStreamContext ctx{0, this, nullptr, nullptr, nullptr};

    stream_ = FSEventStreamCreate(nullptr, &Watcher::handle, &ctx, paths, kFSEventStreamEventIdSinceNow, 0.2,
                                  kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
    CFRelease(paths);
    CFRelease(path);
    if (!stream_) return false;

    FSEventStreamSetDispatchQueue(stream_, dispatch_get_main_queue());
    return FSEventStreamStart(stream_);
}

void Watcher::handle(ConstFSEventStreamRef, void* info, size_t count, void* paths,
                     const FSEventStreamEventFlags flags[], const FSEventStreamEventId[]) {
    auto* self = static_cast<Watcher*>(info);
    auto** list = static_cast<char**>(paths);

    for (size_t i = 0; i < count; ++i) {
        if (!(flags[i] & kFSEventStreamEventFlagItemIsFile)) continue;

        const std::filesystem::path p(list[i]);
        std::error_code ec;
        // Moves out of the folder also fire here, so only report files that still exist.
        if (p.parent_path() != self->dir_ || !is_screenshot(p) || !std::filesystem::exists(p, ec)) continue;

        self->on_screenshot_(p);
    }
}

}  // namespace snap
