#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ProfileManager.h"

@interface ProfilePanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
+ (void)showAsSheetOnWindow:(NSWindow*)parent;
@end

@implementation ProfilePanel {
    NSTableView* _tableView;
    NSWindow*    _parentWindow;
}

+ (instancetype)shared {
    static ProfilePanel* inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [ProfilePanel new]; });
    return inst;
}

+ (void)showAsSheetOnWindow:(NSWindow*)parent {
    ProfilePanel* p = [ProfilePanel shared];
    p->_parentWindow = parent;
    [parent beginSheet:p.window completionHandler:nil];
}

- (instancetype)init {
    NSWindow* win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 400, 300)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered defer:NO];
    win.title = @"Manage Profiles";
    self = [super initWithWindow:win];
    if (self) [self buildUI];
    return self;
}

- (void)buildUI {
    NSView* root = self.window.contentView;
    root.wantsLayer = YES;
    
    NSVisualEffectView* bg = [[NSVisualEffectView alloc] initWithFrame:root.bounds];
    bg.material = NSVisualEffectMaterialHeaderView;
    bg.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:bg];

    NSTextField* header = [NSTextField labelWithString:@"Profiles"];
    header.frame = NSMakeRect(20, 260, 200, 24);
    header.font = [NSFont boldSystemFontOfSize:17];
    [root addSubview:header];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 360, 190)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    _tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 36;
    _tableView.headerView = nil;
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.title = @"Name";
    [_tableView addTableColumn:col];
    scroll.documentView = _tableView;
    [root addSubview:scroll];

    NSButton* addBtn = [NSButton buttonWithTitle:@"+" target:self action:@selector(addProfile:)];
    addBtn.frame = NSMakeRect(20, 20, 32, 32);
    addBtn.bezelStyle = NSBezelStyleSmallSquare;
    [root addSubview:addBtn];

    NSButton* delBtn = [NSButton buttonWithTitle:@"-" target:self action:@selector(deleteProfile:)];
    delBtn.frame = NSMakeRect(52, 20, 32, 32);
    delBtn.bezelStyle = NSBezelStyleSmallSquare;
    [root addSubview:delBtn];

    NSButton* pictureBtn = [NSButton buttonWithTitle:@"Picture…" target:self action:@selector(changePicture:)];
    pictureBtn.frame = NSMakeRect(92, 20, 90, 32);
    pictureBtn.bezelStyle = NSBezelStyleRounded;
    [root addSubview:pictureBtn];

    NSButton* done = [NSButton buttonWithTitle:@"Done" target:self action:@selector(done:)];
    done.frame = NSMakeRect(300, 20, 80, 32);
    done.bezelStyle = NSBezelStyleRounded;
    [root addSubview:done];
}

- (void)addProfile:(id)_ {
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"New Profile";
    alert.informativeText = @"Enter a name for the new profile:";
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.placeholderString = @"e.g. Work, School";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString* name = input.stringValue;
            if (name.length > 0) {
                [[ProfileManager shared] createProfileWithName:name];
                [self->_tableView reloadData];
            }
        }
    }];
}

- (void)deleteProfile:(id)_ {
    NSInteger row = _tableView.selectedRow;
    if (row < 0) return;
    Profile* p = [ProfileManager shared].profiles[row];
    if (p == [ProfileManager shared].activeProfile) {
        NSAlert* a = [NSAlert new];
        a.messageText = @"Cannot Delete Active Profile";
        [a runModal];
        return;
    }
    [[ProfileManager shared] deleteProfile:p];
    [_tableView reloadData];
}

- (void)changePicture:(id)_ {
    NSInteger row = _tableView.selectedRow;
    if (row < 0) return;
    Profile* p = [ProfileManager shared].profiles[row];

    NSMenu* menu = [NSMenu new];
    NSMenuItem* choose = [[NSMenuItem alloc] initWithTitle:@"Choose Picture…"
                                                    action:@selector(choosePictureForSelectedProfile:)
                                             keyEquivalent:@""];
    choose.target = self;
    [menu addItem:choose];

    NSMenuItem* remove = [[NSMenuItem alloc] initWithTitle:@"Remove Picture"
                                                    action:@selector(removePictureForSelectedProfile:)
                                             keyEquivalent:@""];
    remove.target = self;
    remove.enabled = p.avatarPath.length > 0;
    [menu addItem:remove];

    NSButton* btn = (NSButton*)_;
    [NSMenu popUpContextMenu:menu withEvent:[NSApp currentEvent] forView:btn];
}

- (void)choosePictureForSelectedProfile:(id)_ {
    NSInteger row = _tableView.selectedRow;
    if (row < 0) return;
    Profile* p = [ProfileManager shared].profiles[row];
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[ UTTypeImage ];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        [p setAvatarFromImageURL:panel.URL];
        [[ProfileManager shared] saveProfiles];
        [self->_tableView reloadData];
    }];
}

- (void)removePictureForSelectedProfile:(id)_ {
    NSInteger row = _tableView.selectedRow;
    if (row < 0) return;
    Profile* p = [ProfileManager shared].profiles[row];
    [p clearAvatar];
    [[ProfileManager shared] saveProfiles];
    [_tableView reloadData];
}

- (void)done:(id)_ {
    [_parentWindow endSheet:self.window];
    _parentWindow = nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)_ { return [ProfileManager shared].profiles.count; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)_ row:(NSInteger)row {
    NSTableCellView* v = [tv makeViewWithIdentifier:@"cell" owner:self];
    if (!v) {
        v = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 360, 36)];
        v.identifier = @"cell";
        NSImageView* avatar = [[NSImageView alloc] initWithFrame:NSMakeRect(2, 4, 28, 28)];
        avatar.identifier = @"avatar";
        avatar.imageScaling = NSImageScaleProportionallyUpOrDown;
        [v addSubview:avatar];

        NSTextField* t = [NSTextField labelWithString:@""];
        t.frame = NSMakeRect(40, 9, 300, 18);
        t.identifier = @"name";
        [v addSubview:t];
    }
    Profile* p = [ProfileManager shared].profiles[row];
    for (NSView* sub in v.subviews) {
        if ([sub.identifier isEqualToString:@"name"]) ((NSTextField*)sub).stringValue = p.name;
        else if ([sub.identifier isEqualToString:@"avatar"]) ((NSImageView*)sub).image = [self avatarImageForProfile:p size:28];
    }
    return v;
}

- (NSImage*)avatarImageForProfile:(Profile*)profile size:(CGFloat)size {
    NSImage* source = [profile avatarImage];
    if (!source) {
        NSImage* fallback = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
        [fallback lockFocus];
        NSBezierPath* oval = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1, 1, size - 2, size - 2)];
        [(profile.color ?: [NSColor controlAccentColor]) setFill];
        [oval fill];
        [[NSColor separatorColor] setStroke];
        oval.lineWidth = 1;
        [oval stroke];
        [fallback unlockFocus];
        return fallback;
    }

    NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSRect rect = NSMakeRect(1, 1, size - 2, size - 2);
    NSBezierPath* clip = [NSBezierPath bezierPathWithOvalInRect:rect];
    [clip addClip];
    [source drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [(profile.color ?: [NSColor controlAccentColor]) setStroke];
    clip.lineWidth = 1.5;
    [clip stroke];
    [image unlockFocus];
    return image;
}

@end
