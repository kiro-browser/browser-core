/**
 * @file      ProfilePanel.mm
 * @project   BuildBrowser
 * @brief     Profile management sheet — add, delete, change picture.
 *
 * @details   A sheet-based NSWindowController that lists profiles in a
 *            table and allows the user to create new profiles, delete
 *            existing ones (except the active profile), and change or
 *            remove profile avatars.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ProfileManager.h"

#pragma mark - Interface

@interface ProfilePanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
+ (void)showAsSheetOnWindow:(NSWindow*)parent;
@end

#pragma mark - Implementation

@implementation ProfilePanel {
    /// Table displaying all profiles.
    NSTableView* _tableView;
    /// The parent window for sheet presentation.
    NSWindow*    _parentWindow;
}

/**
 * @brief   Returns the shared ProfilePanel singleton.
 *
 * @return  The singleton instance.
 */
+ (instancetype)shared {
    static ProfilePanel* inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [ProfilePanel new]; });
    return inst;
}

/**
 * @brief   Show the profile management panel as a sheet.
 *
 * @param   parent  The parent window to attach the sheet to.
 */
+ (void)showAsSheetOnWindow:(NSWindow*)parent {
    ProfilePanel* p = [ProfilePanel shared];
    p->_parentWindow = parent;
    [parent beginSheet:p.window completionHandler:nil];
}

/**
 * @brief   Initialize the panel window.
 *
 * @return  An initialized ProfilePanel.
 */
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

/**
 * @brief   Build the panel UI: frosted background, header, table, action buttons.
 */
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

/**
 * @brief   Prompt for a new profile name and create it.
 *
 * @param   _  The sender (unused).
 */
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

/**
 * @brief   Delete the selected profile (safe: cannot delete active profile).
 *
 * @param   _  The sender (unused).
 */
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

/**
 * @brief   Show a context menu to choose or remove a profile picture.
 *
 * @param   _  The sender button.
 */
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

/**
 * @brief   Open a file picker to choose a new avatar image.
 */
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

/**
 * @brief   Remove the avatar image from the selected profile.
 */
- (void)removePictureForSelectedProfile:(id)_ {
    NSInteger row = _tableView.selectedRow;
    if (row < 0) return;
    Profile* p = [ProfileManager shared].profiles[row];
    [p clearAvatar];
    [[ProfileManager shared] saveProfiles];
    [_tableView reloadData];
}

/**
 * @brief   Dismiss the sheet.
 */
- (void)done:(id)_ {
    [_parentWindow endSheet:self.window];
    _parentWindow = nil;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name NSTableViewDataSource / Delegate
// ───────────────────────────────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)_ { return [ProfileManager shared].profiles.count; }

/**
 * @brief   Build a table cell with the profile name and avatar image.
 */
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

/**
 * @brief   Generate a circular avatar image (or fallback swatch) for a profile.
 *
 * @param   profile  The profile whose avatar to render.
 * @param   size     The desired image size in points.
 * @return  An NSImage with a circular cropped avatar or colored swatch.
 */
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
