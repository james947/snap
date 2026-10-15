// snap: a one-screenshot shelf. The latest screenshot sits at the screen edge
// and can be dragged into any number of apps; when a new one arrives the old
// one is moved to ~/Screenshots/archive/YYYY-MM/.

#import <Cocoa/Cocoa.h>

#include <memory>

#include "core/screenshot.hpp"
#include "core/watcher.hpp"

namespace fs = std::filesystem;

static const CGFloat kShelfWidth = 180;
static const CGFloat kShelfHeight = 120;
static const CGFloat kScreenMargin = 16;
static const NSTimeInterval kAutoHideSeconds = 30;

static fs::path screenshot_dir() {
    id loc = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("location"), CFSTR("com.apple.screencapture")));
    if ([loc isKindOfClass:[NSString class]] && [loc length] > 0) {
        return fs::path([[loc stringByExpandingTildeInPath] fileSystemRepresentation]);
    }
    return fs::path([[NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"] fileSystemRepresentation]);
}

static NSRect aspect_fit(NSSize content, NSRect box) {
    if (content.width <= 0 || content.height <= 0) return box;
    const CGFloat scale = MIN(box.size.width / content.width, box.size.height / content.height);
    const NSSize size = NSMakeSize(content.width * scale, content.height * scale);
    return NSMakeRect(NSMidX(box) - size.width / 2, NSMidY(box) - size.height / 2, size.width, size.height);
}

// MARK: - Shelf view

@interface ShelfView : NSView <NSDraggingSource>
@property(nonatomic, strong) NSURL* fileURL;
@property(nonatomic, strong) NSImage* image;
@end

@implementation ShelfView {
    NSEvent* _mouseDownEvent;
    NSButton* _closeButton;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        // White × on a dark circle, so it stays visible over any screenshot.
        NSImageSymbolConfiguration* config = [[NSImageSymbolConfiguration configurationWithPointSize:16
                                                                                              weight:NSFontWeightBold]
            configurationByApplyingConfiguration:[NSImageSymbolConfiguration
                                                     configurationWithPaletteColors:@[
                                                         [NSColor whiteColor], [NSColor colorWithWhite:0 alpha:0.75]
                                                     ]]];
        NSImage* x = [[NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Hide"]
            imageWithSymbolConfiguration:config];

        _closeButton = [NSButton buttonWithImage:x target:self action:@selector(hideShelf:)];
        _closeButton.bordered = NO;
        _closeButton.frame = NSMakeRect(4, frame.size.height - 26, 22, 22);
        [self addSubview:_closeButton];
    }
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }

- (NSRect)imageRect {
    return aspect_fit(self.image.size, NSInsetRect(self.bounds, 8, 8));
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0.12 alpha:0.9] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:12 yRadius:12] fill];
    if (!self.image) return;

    [NSGraphicsContext saveGraphicsState];
    const NSRect r = [self imageRect];
    [[NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6] addClip];
    [self.image drawInRect:r];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)mouseDown:(NSEvent*)event {
    _mouseDownEvent = event;
}

- (void)mouseDragged:(NSEvent*)event {
    if (!self.fileURL || !_mouseDownEvent) return;
    NSDraggingItem* item = [[NSDraggingItem alloc] initWithPasteboardWriter:self.fileURL];
    [item setDraggingFrame:[self imageRect] contents:self.image];
    [self beginDraggingSessionWithItems:@[ item ] event:_mouseDownEvent source:self];
    _mouseDownEvent = nil;
}

// Copy, never move: the screenshot stays on the shelf after every drop.
- (NSDragOperation)draggingSession:(NSDraggingSession*)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationCopy;
}

- (NSMenu*)menuForEvent:(NSEvent*)event {
    NSMenu* menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Hide" action:@selector(hideShelf:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Copy Image" action:@selector(copyImage:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Show in Finder" action:@selector(revealInFinder:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit snap" action:@selector(terminate:) keyEquivalent:@""];
    return menu;
}

// The next screenshot brings the shelf back (see -show:).
- (void)hideShelf:(id)sender {
    [self.window orderOut:nil];
}

- (void)copyImage:(id)sender {
    if (!self.image) return;
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb writeObjects:@[ self.image ]];
}

- (void)revealInFinder:(id)sender {
    if (self.fileURL) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ self.fileURL ]];
}

@end

// MARK: - App

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate {
    NSPanel* _panel;
    ShelfView* _shelf;
    NSTimer* _hideTimer;
    std::unique_ptr<snap::Watcher> _watcher;
    fs::path _watchDir;
    fs::path _archiveRoot;
    fs::path _current;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    _watchDir = screenshot_dir();
    _archiveRoot = fs::path([NSHomeDirectory() fileSystemRepresentation]) / "Screenshots" / "archive";

    [self buildPanel];

    // Show whatever the latest screenshot is right now; older ones are left alone.
    if (auto newest = snap::newest_screenshot(_watchDir)) [self show:*newest];

    __weak AppDelegate* weakSelf = self;
    _watcher = std::make_unique<snap::Watcher>(_watchDir, [weakSelf](const fs::path& p) {
        [weakSelf screenshotArrived:p];
    });
    if (!_watcher->start()) {
        NSLog(@"snap: could not watch %s", _watchDir.c_str());
        [NSApp terminate:nil];
    }
    NSLog(@"snap: watching %s, archiving to %s", _watchDir.c_str(), _archiveRoot.c_str());
}

- (void)buildPanel {
    const NSRect visible = [NSScreen mainScreen].visibleFrame;
    const NSRect frame = NSMakeRect(NSMaxX(visible) - kShelfWidth - kScreenMargin, NSMinY(visible) + kScreenMargin,
                                    kShelfWidth, kShelfHeight);

    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    _panel.level = NSFloatingWindowLevel;
    _panel.opaque = NO;
    _panel.backgroundColor = [NSColor clearColor];
    _panel.hasShadow = YES;
    _panel.hidesOnDeactivate = NO;
    _panel.collectionBehavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

    _shelf = [[ShelfView alloc] initWithFrame:NSMakeRect(0, 0, kShelfWidth, kShelfHeight)];
    _panel.contentView = _shelf;
}

- (void)screenshotArrived:(const fs::path&)path {
    if (path == _current) return;
    std::error_code ec;
    if (!_current.empty() && fs::exists(_current, ec)) {
        if (!snap::archive(_current, _archiveRoot)) NSLog(@"snap: could not archive %s", _current.c_str());
    }
    [self show:path];
}

- (void)show:(const fs::path&)path {
    _current = path;
    NSURL* url = [NSURL fileURLWithPath:@(path.c_str())];
    _shelf.fileURL = url;
    _shelf.image = [[NSImage alloc] initWithContentsOfURL:url];
    [_shelf setNeedsDisplay:YES];
    [_panel orderFrontRegardless];
    [self scheduleAutoHide:kAutoHideSeconds];
}

- (void)scheduleAutoHide:(NSTimeInterval)delay {
    [_hideTimer invalidate];
    __weak AppDelegate* weakSelf = self;
    _hideTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                 repeats:NO
                                                   block:^(NSTimer*) { [weakSelf autoHide]; }];
}

- (void)autoHide {
    // Don't pull the shelf away while the mouse is on it (e.g. about to drag).
    if (NSPointInRect([NSEvent mouseLocation], _panel.frame)) {
        [self scheduleAutoHide:5];
        return;
    }
    [_shelf hideShelf:nil];
}

@end

int main() {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyAccessory;  // no Dock icon
        AppDelegate* delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
