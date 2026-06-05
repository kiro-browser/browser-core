/**
 * @file      SidePanel.mm
 * @project   BuildBrowser
 * @brief     Side panel showing bookmarks or history with search.
 *
 * @details   A floating panel (NSWindowController) with a segmented control
 *            to switch between Bookmarks and History views. Supports filtering
 *            via a search field, double-click to open in a new tab, and
 *            context menus for bookmark editing/deletion. Uses an openURL
 *            callback to communicate with the BrowserWindowController.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import <Cocoa/Cocoa.h>
#import "BookmarkManager.h"
#import "HistoryManager.h"
#import "ProfileManager.h"

#pragma mark - Interface

@interface SidePanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@property (copy) void (^openURLCallback)(NSString* url);
+ (instancetype)shared;
- (void)showBookmarks;
- (void)showHistory;
@end

/// The two display modes supported by the side panel.
typedef NS_ENUM(NSInteger, SidePanelMode) { ModeBookmarks, ModeHistory };

#pragma mark - Implementation

@implementation SidePanel {
    /// Segmented control for switching between Bookmarks and History.
    NSSegmentedControl* _segControl;
    /// Table view displaying the filtered items.
    NSTableView*        _tableView;
    /// Search field for filtering items by title or URL.
    NSSearchField*      _searchField;
    /// Label shown when no items match the current view.
    NSTextField*        _emptyLabel;
    /// Current display mode (bookmarks or history).
    SidePanelMode       _mode;
    /// Filtered array based on search query.
    NSArray*            _filtered;
}

/**
 * @brief   Returns the shared SidePanel singleton.
 *
 * @return  The singleton instance.
 */
+ (instancetype)shared {
    static SidePanel* inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [SidePanel new]; });
    return inst;
}

/**
 * @brief   Initialize the panel window.
 *
 * @return  An initialized SidePanel.
 */
- (instancetype)init {
    NSWindow* win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 340, 560)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                           | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered defer:NO];
    win.title = @"";
    win.titlebarAppearsTransparent = YES;
    win.movableByWindowBackground  = YES;
    win.minSize = NSMakeSize(280, 320);
    self = [super initWithWindow:win];
    if (!self) return nil;
    [self buildUI];
    return self;
}

/**
 * @brief   Build the panel UI: segmented control, search field, table, empty state.
 */
- (void)buildUI {
    NSView* root = self.window.contentView;
    root.wantsLayer = YES;
    CGFloat W = 340, H = 560;

    // Frosted background (sidebar material)
    NSVisualEffectView* bg = [[NSVisualEffectView alloc] initWithFrame:root.bounds];
    bg.material        = NSVisualEffectMaterialSidebar;
    bg.blendingMode    = NSVisualEffectBlendingModeWithinWindow;
    bg.state           = NSVisualEffectStateActive;
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:bg];

    // Segmented control — pill style for Bookmarks / History
    _segControl = [NSSegmentedControl
        segmentedControlWithLabels:@[@"Bookmarks", @"History"]
                      trackingMode:NSSegmentSwitchTrackingSelectOne
                            target:self action:@selector(segChanged:)];
    _segControl.segmentStyle = NSSegmentStyleCapsule;
    _segControl.frame = NSMakeRect((W - 220) / 2, H - 52, 220, 28);
    _segControl.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
    _segControl.selectedSegment = 0;
    [root addSubview:_segControl];

    // Search field
    _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(12, H - 92, W - 24, 28)];
    _searchField.placeholderString = @"Search…";
    _searchField.autoresizingMask  = NSViewWidthSizable | NSViewMinYMargin;
    _searchField.target = self;
    _searchField.action = @selector(filterChanged:);
    [root addSubview:_searchField];

    // Separator below search
    NSView* sep = [[NSView alloc] initWithFrame:NSMakeRect(0, H - 100, W, 1)];
    sep.wantsLayer = YES;
    sep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    sep.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [root addSubview:sep];

    // Scrollable table
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, W, H - 101)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;

    _tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _tableView.backgroundColor = [NSColor clearColor];
    _tableView.dataSource = self;
    _tableView.delegate   = self;
    _tableView.rowHeight  = 56;
    _tableView.intercellSpacing = NSMakeSize(0, 0);
    _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _tableView.doubleAction = @selector(rowDoubleClicked:);
    _tableView.target       = self;
    _tableView.headerView   = nil;

    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    col.width = W;
    [_tableView addTableColumn:col];
    scroll.documentView = _tableView;
    [root addSubview:scroll];

    // Empty state label
    _emptyLabel = [NSTextField labelWithString:@"Nothing here yet"];
    _emptyLabel.frame     = NSMakeRect(0, H / 2 - 20, W, 40);
    _emptyLabel.alignment = NSTextAlignmentCenter;
    _emptyLabel.font      = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
    _emptyLabel.textColor = [NSColor tertiaryLabelColor];
    _emptyLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    _emptyLabel.hidden = YES;
    [root addSubview:_emptyLabel];

    [self reloadData];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Public API
// ───────────────────────────────────────────────────────────────────────────────

/** @brief   Switch to Bookmarks mode and show the panel. */
- (void)showBookmarks {
    _mode = ModeBookmarks;
    _segControl.selectedSegment = 0;
    [self.window setTitle:@"Bookmarks"];
    [self reloadData];
    [self.window makeKeyAndOrderFront:nil];
}

/** @brief   Switch to History mode and show the panel. */
- (void)showHistory {
    _mode = ModeHistory;
    _segControl.selectedSegment = 1;
    [self.window setTitle:@"History"];
    [self reloadData];
    [self.window makeKeyAndOrderFront:nil];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Data
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Reload data from the appropriate source, apply search filter.
 */
- (void)reloadData {
    NSString* q = _searchField.stringValue.lowercaseString;
    NSArray* source = (_mode == ModeBookmarks)
        ? (NSArray*)[BookmarkManager profileShared].bookmarks
        : (NSArray*)[HistoryManager  profileShared].entries;

    _filtered = q.length == 0 ? source :
        [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
            ^BOOL(id obj, NSDictionary* _) {
                NSString* t = [[obj valueForKey:@"title"] lowercaseString] ?: @"";
                NSString* u = [[obj valueForKey:@"url"]   lowercaseString] ?: @"";
                return [t containsString:q] || [u containsString:q];
            }]];

    [_tableView reloadData];
    _emptyLabel.hidden = (_filtered.count > 0);

    NSString* emptyMsg = (_mode == ModeBookmarks)
        ? @"No bookmarks yet\nPress ⌘D to bookmark a page"
        : @"No history yet";
    _emptyLabel.stringValue = emptyMsg;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name NSTableViewDataSource
// ───────────────────────────────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView*)_ { return (NSInteger)_filtered.count; }

/**
 * @brief   Build a table cell with icon, title, URL/subtitle, and separator.
 */
- (NSView*)tableView:(NSTableView*)tv viewForTableColumn:(NSTableColumn*)_ row:(NSInteger)row {
    NSTableCellView* cell = [tv makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 340, 56)];
        cell.identifier = @"cell";

        NSView* iconBg = [[NSView alloc] initWithFrame:NSMakeRect(12, 14, 28, 28)];
        iconBg.wantsLayer = YES;
        iconBg.layer.cornerRadius = 6;
        iconBg.layer.backgroundColor = [NSColor controlAccentColor].CGColor;
        iconBg.identifier = @"iconBg";
        [cell addSubview:iconBg];

        NSImageView* icon = [[NSImageView alloc] initWithFrame:NSMakeRect(4, 4, 20, 20)];
        icon.contentTintColor = [NSColor whiteColor];
        icon.identifier = @"icon";
        [iconBg addSubview:icon];

        NSTextField* titleLabel = [NSTextField labelWithString:@""];
        titleLabel.frame = NSMakeRect(52, 28, 272, 16);
        titleLabel.font  = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        titleLabel.identifier = @"titleLabel";
        [cell addSubview:titleLabel];

        NSTextField* urlLabel = [NSTextField labelWithString:@""];
        urlLabel.frame = NSMakeRect(52, 10, 272, 14);
        urlLabel.font  = [NSFont systemFontOfSize:11];
        urlLabel.textColor = [NSColor secondaryLabelColor];
        urlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        urlLabel.identifier = @"urlLabel";
        [cell addSubview:urlLabel];

        NSView* rowSep = [[NSView alloc] initWithFrame:NSMakeRect(52, 0, 280, 1)];
        rowSep.wantsLayer = YES;
        rowSep.layer.backgroundColor = [NSColor separatorColor].CGColor;
        rowSep.identifier = @"sep";
        [cell addSubview:rowSep];
    }

    id obj = _filtered[row];
    NSString* title = [obj valueForKey:@"title"] ?: @"";
    NSString* url   = [obj valueForKey:@"url"]   ?: @"";
    NSString* folder = [obj valueForKey:@"folder"] ?: @"Favorites";
    BOOL isBookmark = (_mode == ModeBookmarks);

    for (NSView* sub in cell.subviews) {
        if ([sub.identifier isEqualToString:@"titleLabel"])
            ((NSTextField*)sub).stringValue = title.length ? title : url;
        else if ([sub.identifier isEqualToString:@"urlLabel"])
            ((NSTextField*)sub).stringValue = isBookmark
                ? [NSString stringWithFormat:@"%@  -  %@", folder.length ? folder : @"Favorites", url]
                : url;
        else if ([sub.identifier isEqualToString:@"iconBg"]) {
            NSColor* c = isBookmark ? [NSColor systemOrangeColor] : [NSColor systemBlueColor];
            ((NSView*)sub).layer.backgroundColor = c.CGColor;
            for (NSView* s2 in sub.subviews) {
                if ([s2.identifier isEqualToString:@"icon"]) {
                    NSString* sym = isBookmark ? @"bookmark.fill" : @"clock.fill";
                    ((NSImageView*)s2).image = [NSImage imageWithSystemSymbolName:sym
                                                          accessibilityDescription:nil];
                }
            }
        } else if ([sub.identifier isEqualToString:@"sep"]) {
            sub.hidden = (row == (NSInteger)_filtered.count - 1);
        }
    }
    return cell;
}

- (NSTableRowView*)tableView:(NSTableView*)tv rowViewForRow:(NSInteger)_ {
    NSTableRowView* rv = [tv makeViewWithIdentifier:@"rv" owner:self];
    if (!rv) { rv = [NSTableRowView new]; rv.identifier = @"rv"; }
    return rv;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Actions
// ───────────────────────────────────────────────────────────────────────────────

/// Switch between bookmarks and history mode.
- (void)segChanged:(id)_ {
    _mode = (_segControl.selectedSegment == 0) ? ModeBookmarks : ModeHistory;
    [self.window setTitle:(_mode == ModeBookmarks) ? @"Bookmarks" : @"History"];
    [self reloadData];
}

/// Apply search filter.
- (void)filterChanged:(id)_ { [self reloadData]; }

/// Open the double-clicked item in a new tab via the callback.
- (void)rowDoubleClicked:(id)_ {
    NSInteger row = _tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)_filtered.count) return;
    NSString* url = [_filtered[row] valueForKey:@"url"];
    if (url && self.openURLCallback) self.openURLCallback(url);
}

/**
 * @brief   Build a context menu for right-click on table rows.
 *
 * @details In bookmarks mode, adds Edit Bookmark and Remove Bookmark items.
 */
- (NSMenu*)tableView:(NSTableView*)tv menuForEvent:(NSEvent*)ev {
    NSPoint pt  = [tv convertPoint:ev.locationInWindow fromView:nil];
    NSInteger row = [tv rowAtPoint:pt];
    if (row < 0) return nil;
    [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];

    NSMenu* menu = [NSMenu new];
    NSMenuItem* open = [[NSMenuItem alloc] initWithTitle:@"Open in New Tab"
        action:@selector(openSelected:) keyEquivalent:@""];
    open.target = self; [menu addItem:open];

    if (_mode == ModeBookmarks) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem* edit = [[NSMenuItem alloc] initWithTitle:@"Edit Bookmark…"
            action:@selector(editSelected:) keyEquivalent:@""];
        edit.target = self; [menu addItem:edit];

        NSMenuItem* del = [[NSMenuItem alloc] initWithTitle:@"Remove Bookmark"
            action:@selector(deleteSelected:) keyEquivalent:@""];
        del.target = self; [menu addItem:del];
    }
    return menu;
}

/// Open the selected item in a new tab.
- (void)openSelected:(id)_ {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filtered.count) return;
    NSString* url = [_filtered[row] valueForKey:@"url"];
    if (url && self.openURLCallback) self.openURLCallback(url);
}

/**
 * @brief   Show an edit dialog for the selected bookmark.
 *
 * @details Allows editing title, URL, and folder fields.
 */
- (void)editSelected:(id)_ {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filtered.count || _mode != ModeBookmarks) return;

    Bookmark* bm = _filtered[row];
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"Edit Bookmark";
    alert.informativeText = @"Update the bookmark title or URL.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView* form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 88)];
    NSTextField* titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 64, 360, 24)];
    titleField.stringValue = bm.title ?: @"";
    titleField.placeholderString = @"Title";
    [form addSubview:titleField];

    NSTextField* urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 32, 360, 24)];
    urlField.stringValue = bm.url ?: @"";
    urlField.placeholderString = @"URL";
    [form addSubview:urlField];

    NSTextField* folderField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 24)];
    folderField.stringValue = bm.folder.length ? bm.folder : @"Favorites";
    folderField.placeholderString = @"Folder";
    [form addSubview:folderField];
    alert.accessoryView = form;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertFirstButtonReturn) return;
        NSString* oldURL = bm.url;
        NSArray<Bookmark*>* bms = [BookmarkManager profileShared].bookmarks;
        for (NSInteger i = 0; i < (NSInteger)bms.count; i++) {
            if ([bms[i].url isEqualToString:oldURL]) {
                [[BookmarkManager profileShared] updateBookmarkAtIndex:i
                                                                   title:titleField.stringValue
                                                                     url:urlField.stringValue
                                                                  folder:folderField.stringValue];
                break;
            }
        }
        [self reloadData];
    }];
}

/// Delete the selected bookmark after confirmation.
- (void)deleteSelected:(id)_ {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filtered.count) return;
    NSString* url = [_filtered[row] valueForKey:@"url"];
    NSArray<Bookmark*>* bms = [BookmarkManager profileShared].bookmarks;
    for (NSInteger i = 0; i < (NSInteger)bms.count; i++) {
        if ([bms[i].url isEqualToString:url]) {
            [[BookmarkManager profileShared] removeBookmarkAtIndex:i]; break;
        }
    }
    [self reloadData];
}

@end
