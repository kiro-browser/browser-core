#import "TabManager.h"
#import "ContentBlocker.h"
#import "DownloadManager.h"
#import "SettingsManager.h"
#import "BookmarkManager.h"
#import <Security/Security.h>

static NSString* const kBuildBrowserStartURL = @"buildbrowser://start";

@interface BrowserContextWebView : WKWebView
@property (copy) void (^contextMenuHandler)(BrowserContextWebView* webView, NSDictionary* info, NSEvent* event);
@property (copy) void (^middleClickLinkHandler)(NSString* url);
@end

@implementation BrowserContextWebView
- (void)rightMouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat domX = point.x;
    CGFloat domY = self.bounds.size.height - point.y;
    NSString* js = [NSString stringWithFormat:
        @"(function(){"
        "var el=document.elementFromPoint(%f,%f);"
        "function closest(n,s){while(n&&n.nodeType===1){if(n.matches&&n.matches(s))return n;n=n.parentElement;}return null;}"
        "var a=closest(el,'a[href]');var img=closest(el,'img[src]');"
        "return {linkURL:a?a.href:'',linkText:a?(a.innerText||a.title||a.href):'',"
        "imageURL:img?(img.currentSrc||img.src):'',imageAlt:img?(img.alt||img.title||''):''};"
        "})()", domX, domY];

    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:js completionHandler:^(id result, NSError* error) {
        BrowserContextWebView* strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary* info = [result isKindOfClass:[NSDictionary class]] ? result : @{};
        if (strongSelf.contextMenuHandler) strongSelf.contextMenuHandler(strongSelf, info, event);
    }];
}

- (void)otherMouseDown:(NSEvent*)event {
    if (event.buttonNumber != 2) {
        [super otherMouseDown:event];
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat domX = point.x;
    CGFloat domY = self.bounds.size.height - point.y;
    NSString* js = [NSString stringWithFormat:
        @"(function(){"
        "var el=document.elementFromPoint(%f,%f);"
        "while(el&&el.nodeType===1){"
        "if(el.matches&&el.matches('a[href]'))return el.href;"
        "el=el.parentElement;"
        "}"
        "return '';"
        "})()", domX, domY];

    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:js completionHandler:^(id result, NSError* error) {
        BrowserContextWebView* strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString* url = [result isKindOfClass:[NSString class]] ? result : @"";
        if (url.length && strongSelf.middleClickLinkHandler) {
            strongSelf.middleClickLinkHandler(url);
        }
    }];
}
@end

// ── BrowserTab ───────────────────────────────────────────────────────────────

@implementation BrowserTab
@end

// ── TabManager ───────────────────────────────────────────────────────────────

@interface TabManager () <WKNavigationDelegate, WKUIDelegate>
@property (strong) NSMutableArray<BrowserTab*>* mutableTabs;
@property (assign) NSInteger currentIndex;
+ (WKWebsiteDataStore*)websiteDataStoreForProfile:(Profile*)profile privateBrowsing:(BOOL)privateBrowsing;
+ (NSString*)startPageHTML;
+ (NSString*)commandPageHTMLForCommand:(NSString*)command;
+ (NSString*)displayNameForCommand:(NSString*)command;
+ (BOOL)shouldOfferContinueForError:(NSError*)error url:(NSString*)url;
+ (NSString*)errorPageHTMLForURL:(NSString*)url error:(NSError*)error;
+ (NSString*)htmlEscape:(NSString*)value;
- (NSString*)suggestedFilenameForURL:(NSString*)urlString;
- (void)writeStringToPasteboard:(NSString*)value;
- (void)showContextMenuForWebView:(WKWebView*)webView info:(NSDictionary*)info event:(NSEvent*)event;
- (NSDictionary*)certificateInfoForTrust:(SecTrustRef)trust host:(NSString*)host;
- (BOOL)isSearchResultsPage:(NSURL*)url;
- (BOOL)shouldOpenSearchClickInNewTab:(WKNavigationAction*)navigationAction fromWebView:(WKWebView*)webView;
@end

@implementation TabManager

- (instancetype)initWithProfile:(Profile*)profile {
    self = [super init];
    if (self) {
        _profile      = profile;
        _mutableTabs  = [NSMutableArray new];
        _currentIndex = -1;
    }
    return self;
}

- (NSArray<BrowserTab*>*)tabs { return _mutableTabs; }
- (BrowserTab*)activeTab      { return _currentIndex >= 0 ? _mutableTabs[_currentIndex] : nil; }
- (NSInteger)activeIndex      { return _currentIndex; }

// ── Tab creation ─────────────────────────────────────────────────────────────

- (BrowserTab*)newTabWithURL:(NSString*)url {
    WKWebViewConfiguration* config = [WKWebViewConfiguration new];
    SettingsManager* settings = [SettingsManager profileShared];
    config.preferences.javaScriptCanOpenWindowsAutomatically = !settings.blockPopups;
    config.defaultWebpagePreferences.allowsContentJavaScript = settings.javascriptEnabled;
    config.websiteDataStore = [TabManager websiteDataStoreForProfile:_profile privateBrowsing:settings.privateBrowsing];
    
    [[ContentBlocker shared] applyToConfiguration:config completion:nil];

    BrowserTab* tab   = [BrowserTab new];
    BrowserContextWebView* webView = [[BrowserContextWebView alloc] initWithFrame:NSZeroRect configuration:config];
    __weak typeof(self) weakSelf = self;
    webView.contextMenuHandler = ^(BrowserContextWebView* wv, NSDictionary* info, NSEvent* event) {
        [weakSelf showContextMenuForWebView:wv info:info event:event];
    };
    webView.middleClickLinkHandler = ^(NSString* linkURL) {
        [weakSelf newTabWithURL:linkURL];
    };
    tab.webView       = webView;
    tab.webView.navigationDelegate = self;
    tab.webView.UIDelegate         = self;
    tab.title = @"New Tab";
    tab.url   = url ?: @"";
    tab.pinned = NO;

    // Tab strip button
    tab.tabButton = [NSButton buttonWithTitle:@"New Tab" target:nil action:nil];
    tab.tabButton.bezelStyle    = NSBezelStyleRecessed;
    tab.tabButton.buttonType    = NSButtonTypePushOnPushOff;
    tab.tabButton.font          = [NSFont systemFontOfSize:12];
    tab.tabButton.imagePosition = NSNoImage;
    [tab.tabButton.cell setLineBreakMode:NSLineBreakByTruncatingTail];

    // KVO for live progress / title / URL updates
    [tab.webView addObserver:self forKeyPath:@"estimatedProgress"
                    options:NSKeyValueObservingOptionNew context:nil];
    [tab.webView addObserver:self forKeyPath:@"title"
                    options:NSKeyValueObservingOptionNew context:nil];
    [tab.webView addObserver:self forKeyPath:@"URL"
                    options:NSKeyValueObservingOptionNew context:nil];

    // Set default icon
    tab.favicon = [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:nil];

    NSInteger index = (NSInteger)_mutableTabs.count;
    [_mutableTabs addObject:tab];

    if (self.onTabAdded) self.onTabAdded(tab, index);

    [self switchToIndex:index];
    [self loadURL:url inTab:tab];

    return tab;
}

+ (WKWebsiteDataStore*)websiteDataStoreForProfile:(Profile*)profile privateBrowsing:(BOOL)privateBrowsing {
    if (privateBrowsing) return [WKWebsiteDataStore nonPersistentDataStore];

    if (@available(macOS 14.0, *)) {
        NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:profile.uuid];
        if (uuid) return [WKWebsiteDataStore dataStoreForIdentifier:uuid];
    }

    return [WKWebsiteDataStore defaultDataStore];
}

// ── Tab switching / closing ───────────────────────────────────────────────────

- (void)switchToIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_mutableTabs.count) return;
    _currentIndex = index;
    if (self.onTabSwitched) self.onTabSwitched(_mutableTabs[index], index);
}

- (void)closeTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_mutableTabs.count) return;

    // Never close the last tab — navigate home instead
    if (_mutableTabs.count == 1) {
        [self loadURL:[SettingsManager profileShared].homepage inTab:_mutableTabs[0]];
        return;
    }

    // Remove KVO before releasing the web view
    BrowserTab* dying = _mutableTabs[index];
    [dying.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [dying.webView removeObserver:self forKeyPath:@"title"];
    [dying.webView removeObserver:self forKeyPath:@"URL"];

    [_mutableTabs removeObjectAtIndex:index];
    if (self.onTabClosed) self.onTabClosed(index);

    NSInteger next = (index > 0) ? index - 1 : 0;
    _currentIndex  = -1;
    [self switchToIndex:next];
}

- (void)setPinned:(BOOL)pinned forTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_mutableTabs.count) return;
    _mutableTabs[index].pinned = pinned;
}

// ── URL loading ───────────────────────────────────────────────────────────────

- (void)loadURL:(NSString*)raw inTab:(BrowserTab*)tab {
    NSString* url = [TabManager sanitizeURL:raw];
    tab.url = url;
    NSURL* parsed = [NSURL URLWithString:url];
    if ([parsed.scheme.lowercaseString isEqualToString:@"buildbrowser"]) {
        NSString* command = parsed.host.length ? parsed.host.lowercaseString : @"start";
        if ([command isEqualToString:@"continue"]) {
            NSURLComponents* components = [NSURLComponents componentsWithString:url];
            NSString* target = nil;
            for (NSURLQueryItem* item in components.queryItems) {
                if ([item.name isEqualToString:@"url"]) { target = item.value; break; }
            }
            if (target.length) [self loadURL:target inTab:tab];
            return;
        }
        NSString* html = [command isEqualToString:@"start"]
            ? [TabManager startPageHTML]
            : [TabManager commandPageHTMLForCommand:command];
        tab.title = [TabManager displayNameForCommand:command];
        [tab.webView loadHTMLString:html baseURL:[NSURL URLWithString:@"https://buildbrowser.local/"]];
        if (self.onInternalCommand) self.onInternalCommand(command);
        return;
    }

    NSURL* nsurl = [NSURL URLWithString:url];
    if (nsurl) [tab.webView loadRequest:[NSURLRequest requestWithURL:nsurl]];
}

+ (NSString*)sanitizeURL:(NSString*)input {
    NSString* trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return kBuildBrowserStartURL;
    if ([trimmed hasPrefix:@"buildbrowser://"]) return trimmed;
    if ([trimmed hasPrefix:@"@"]) {
        NSArray<NSString*>* parts = [trimmed componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString* alias = [parts.firstObject substringFromIndex:1].lowercaseString;
        NSDictionary* launcher = [SettingsManager profileShared].domainLaunchers[alias];
        if (launcher) {
            NSString* query = @"";
            if (trimmed.length > alias.length + 1)
                query = [[trimmed substringFromIndex:alias.length + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (query.length && launcher[@"search"]) {
                NSString* enc = [query stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
                return [NSString stringWithFormat:launcher[@"search"], enc];
            }
            return launcher[@"url"];
        }
    }
    if ([trimmed hasPrefix:@"http://"] || [trimmed hasPrefix:@"https://"]) return trimmed;
    if ([trimmed hasPrefix:@"localhost"] || [trimmed hasPrefix:@"127.0.0.1"])
        return [@"http://" stringByAppendingString:trimmed];
    if ([trimmed containsString:@"://"]) return trimmed;
    if ([trimmed containsString:@"."] && ![trimmed containsString:@" "])
        return [@"https://" stringByAppendingString:trimmed];

    SettingsManager* settings = [SettingsManager profileShared];
    NSString* searchTemplate = settings.searchEngineURL.length ? settings.searchEngineURL : @"https://duckduckgo.com/?q=%@";
    if (![searchTemplate containsString:@"%@"]) searchTemplate = @"https://duckduckgo.com/?q=%@";
    NSString* enc = [trimmed stringByAddingPercentEncodingWithAllowedCharacters:
                     NSCharacterSet.URLQueryAllowedCharacterSet];
    return [NSString stringWithFormat:searchTemplate, enc];
}

+ (NSString*)startPageHTML {
    return @"<!doctype html><html><head><meta charset='utf-8'>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>BuildBrowser Start</title>"
    "<style>"
    ":root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif}"
    "body{margin:0;min-height:100vh;display:grid;place-items:center;background:Canvas;color:CanvasText}"
    ".wrap{width:min(720px,calc(100vw - 48px));transform:translateY(-5vh)}"
    "h1{font-size:42px;line-height:1.05;margin:0 0 22px;font-weight:700;letter-spacing:0}"
    "form{display:flex;gap:10px}"
    "input{flex:1;height:48px;border-radius:12px;border:1px solid color-mix(in srgb,CanvasText 18%,transparent);"
    "background:color-mix(in srgb,Canvas 92%,CanvasText 8%);color:CanvasText;font-size:17px;padding:0 16px;outline:none}"
    "input:focus{border-color:#5b9dff;box-shadow:0 0 0 3px color-mix(in srgb,#5b9dff 25%,transparent)}"
    "button{height:50px;border:0;border-radius:12px;padding:0 18px;background:#de5833;color:white;font-size:15px;font-weight:600}"
    ".meta{margin-top:14px;color:color-mix(in srgb,CanvasText 62%,transparent);font-size:13px}"
    "a{color:CanvasText;text-decoration:none;border:1px solid color-mix(in srgb,CanvasText 16%,transparent);border-radius:9px;padding:8px 10px;font-size:13px}"
    "@media(max-width:520px){h1{font-size:32px}form{flex-direction:column}button{width:100%}}"
    "</style></head><body><main class='wrap'>"
    "<h1>BuildBrowser</h1>"
    "<form action='https://duckduckgo.com/' method='get' target='_blank'>"
    "<input name='q' autofocus autocomplete='off' placeholder='Search DuckDuckGo or enter a URL'>"
    "<button type='submit'>Search</button>"
    "</form><div class='meta'>Private DuckDuckGo search from your local start page.</div>"
    "<nav style='margin-top:22px;display:flex;gap:10px;flex-wrap:wrap'>"
    "<a href='buildbrowser://bookmarks'>Bookmarks</a>"
    "<a href='buildbrowser://history'>History</a>"
    "<a href='buildbrowser://downloads'>Downloads</a>"
    "<a href='buildbrowser://settings'>Settings</a>"
    "<a href='buildbrowser://profiles'>Profiles</a>"
    "<a href='buildbrowser://help'>Help</a>"
    "</nav>"
    "</main></body></html>";
}

+ (NSString*)commandPageHTMLForCommand:(NSString*)command {
    NSString* title = [TabManager displayNameForCommand:command];
    NSString* body = @"";
    if ([command isEqualToString:@"bookmarks"]) {
        body = @"The Bookmarks panel is open. Use it to search, edit, and organize bookmark folders.";
    } else if ([command isEqualToString:@"history"]) {
        body = @"The History panel is open. Use search to find recently visited pages.";
    } else if ([command isEqualToString:@"downloads"]) {
        body = @"The Downloads panel is open. Recent downloads and file actions appear there.";
    } else if ([command isEqualToString:@"settings"]) {
        body = @"The Settings sheet is open for the current profile.";
    } else if ([command isEqualToString:@"profiles"]) {
        body = @"The Profiles manager is open. Profiles keep separate bookmarks, history, settings, and website data.";
    } else {
        body = @"Use local command URLs to open browser tools directly from the address bar.";
    }

    return [NSString stringWithFormat:
        @"<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>%@</title><style>"
        ":root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif}"
        "body{margin:0;min-height:100vh;display:grid;place-items:center;background:Canvas;color:CanvasText}"
        "main{width:min(760px,calc(100vw - 48px));transform:translateY(-4vh)}"
        "h1{font-size:36px;margin:0 0 12px}.lead{color:color-mix(in srgb,CanvasText 70%%,transparent);line-height:1.5}"
        ".grid{margin-top:26px;display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px}"
        "a{border:1px solid color-mix(in srgb,CanvasText 16%%,transparent);border-radius:10px;padding:13px 14px;text-decoration:none;color:CanvasText;background:color-mix(in srgb,CanvasText 5%%,transparent)}"
        "code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:color-mix(in srgb,CanvasText 70%%,transparent)}"
        "</style></head><body><main><h1>%@</h1><p class='lead'>%@</p>"
        "<div class='grid'>"
        "<a href='buildbrowser://start'>Start<br><code>buildbrowser://start</code></a>"
        "<a href='buildbrowser://bookmarks'>Bookmarks<br><code>buildbrowser://bookmarks</code></a>"
        "<a href='buildbrowser://history'>History<br><code>buildbrowser://history</code></a>"
        "<a href='buildbrowser://downloads'>Downloads<br><code>buildbrowser://downloads</code></a>"
        "<a href='buildbrowser://settings'>Settings<br><code>buildbrowser://settings</code></a>"
        "<a href='buildbrowser://profiles'>Profiles<br><code>buildbrowser://profiles</code></a>"
        "</div></main></body></html>", title, title, body];
}

+ (NSString*)displayNameForCommand:(NSString*)command {
    if ([command isEqualToString:@"start"]) return @"BuildBrowser Start";
    if ([command isEqualToString:@"bookmarks"]) return @"Bookmarks";
    if ([command isEqualToString:@"history"]) return @"History";
    if ([command isEqualToString:@"downloads"]) return @"Downloads";
    if ([command isEqualToString:@"settings"]) return @"Settings";
    if ([command isEqualToString:@"profiles"]) return @"Profiles";
    return @"BuildBrowser Commands";
}

// ── WKNavigationDelegate ──────────────────────────────────────────────────────

- (void)webView:(WKWebView*)wv didStartProvisionalNavigation:(WKNavigation*)_ {
    BrowserTab* tab = [self tabForWebView:wv];
    if (!tab) return;
    tab.certificateInfo = nil;
    if (self.onLoadStateChanged) self.onLoadStateChanged(tab, YES);
}

- (void)webView:(WKWebView*)wv didFinishNavigation:(WKNavigation*)_ {
    BrowserTab* tab = [self tabForWebView:wv];
    if (!tab) return;
    if (self.onLoadStateChanged) self.onLoadStateChanged(tab, NO);
    NSString* title = wv.title.length ? wv.title : @"New Tab";
    NSString* url   = wv.URL.absoluteString ?: @"";
    if (tab.url.length && [url isEqualToString:@"about:blank"])
        url = tab.url;
    tab.title = title;  tab.url = url;
    if (self.onTitleChanged) self.onTitleChanged(tab, title);
    if (self.onURLChanged)   self.onURLChanged(tab, url);
    [self updateFaviconForTab:tab];
}

- (void)webView:(WKWebView*)wv didFailNavigation:(WKNavigation*)_ withError:(NSError*)error {
    BrowserTab* tab = [self tabForWebView:wv];
    if (!tab) return;
    if (self.onLoadStateChanged) self.onLoadStateChanged(tab, NO);
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
    [self showErrorPageForTab:tab error:error failedURL:wv.URL.absoluteString ?: tab.url];
}

- (void)webView:(WKWebView*)wv didFailProvisionalNavigation:(WKNavigation*)_ withError:(NSError*)error {
    BrowserTab* tab = [self tabForWebView:wv];
    if (!tab) return;
    if (self.onLoadStateChanged) self.onLoadStateChanged(tab, NO);
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
    [self showErrorPageForTab:tab error:error failedURL:tab.url];
}

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL* requestURL = navigationAction.request.URL;
    if ([requestURL.scheme isEqualToString:@"buildbrowser"]) {
        BrowserTab* tab = [self tabForWebView:webView];
        if (tab) [self loadURL:requestURL.absoluteString inTab:tab];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if ([self shouldOpenSearchClickInNewTab:navigationAction fromWebView:webView]) {
        [self newTabWithURL:requestURL.absoluteString];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (@available(macOS 11.3, *)) {
        if (navigationAction.shouldPerformDownload) {
            decisionHandler(WKNavigationActionPolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView*)webView decidePolicyForNavigationResponse:(WKNavigationResponse*)navigationResponse
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (!navigationResponse.canShowMIMEType) {
        decisionHandler(WKNavigationResponsePolicyDownload);
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView*)webView navigationAction:(WKNavigationAction*)navigationAction didBecomeDownload:(WKDownload*)download API_AVAILABLE(macos(11.3)) {
    [[DownloadManager profileShared] startDownload:download];
}

- (void)webView:(WKWebView*)webView navigationResponse:(WKNavigationResponse*)navigationResponse didBecomeDownload:(WKDownload*)download API_AVAILABLE(macos(11.3)) {
    [[DownloadManager profileShared] startDownload:download];
}

- (WKWebView*)webView:(WKWebView*)webView createWebViewWithConfiguration:(WKWebViewConfiguration*)configuration
  forNavigationAction:(WKNavigationAction*)navigationAction windowFeatures:(WKWindowFeatures*)windowFeatures {
    if (!navigationAction.targetFrame) {
        if (@available(macOS 11.3, *)) {
            if (navigationAction.shouldPerformDownload) return nil;
        }
        [self newTabWithURL:navigationAction.request.URL.absoluteString];
        return nil;
    }
    return nil;
}

- (void)webView:(WKWebView*)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge*)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential* credential))completionHandler {
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    BrowserTab* tab = [self tabForWebView:webView];
    if (trust && tab) {
        tab.certificateInfo = [self certificateInfoForTrust:trust host:challenge.protectionSpace.host];
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

// ── KVO ───────────────────────────────────────────────────────────────────────

- (void)observeValueForKeyPath:(NSString*)kp ofObject:(id)obj
                        change:(NSDictionary*)_ context:(void*)__ {
    WKWebView*  wv  = (WKWebView*)obj;
    BrowserTab* tab = [self tabForWebView:wv];
    if (!tab) return;

    if ([kp isEqualToString:@"estimatedProgress"]) {
        if (self.onLoadProgress) self.onLoadProgress(tab, wv.estimatedProgress);
    } else if ([kp isEqualToString:@"title"]) {
        NSString* t = wv.title.length ? wv.title : @"New Tab";
        tab.title = t;
        if (self.onTitleChanged) self.onTitleChanged(tab, t);
    } else if ([kp isEqualToString:@"URL"]) {
        NSString* u = wv.URL.absoluteString ?: @"";
        if (tab.url.length && [u isEqualToString:@"about:blank"])
            return;
        tab.url = u;
        if (self.onURLChanged) self.onURLChanged(tab, u);
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

- (void)updateFaviconForTab:(BrowserTab*)tab {
    // 1. Try to extract from page via JS
    NSString* js = @"(function() {"
    "  var rels = ['icon', 'shortcut icon', 'apple-touch-icon'];"
    "  for (var i = 0; i < rels.length; i++) {"
    "    var el = document.querySelector('link[rel=\"' + rels[i] + '\"]');"
    "    if (el && el.href) return el.href;"
    "  }"
    "  return null;"
    "})();";

    __weak typeof(self) weakSelf = self;
    [tab.webView evaluateJavaScript:js completionHandler:^(id result, NSError* error) {
        NSString* iconURLString = (NSString*)result;
        if (![iconURLString isKindOfClass:[NSString class]] || iconURLString.length == 0) {
            // 2. Fallback to Google Favicon API
            NSURL* url = [NSURL URLWithString:tab.url];
            if (url.host) {
                iconURLString = [NSString stringWithFormat:@"https://www.google.com/s2/favicons?domain=%@&sz=32", url.host];
            }
        }

        if (iconURLString) {
            [weakSelf downloadFavicon:iconURLString forTab:tab];
        }
    }];
}

- (void)downloadFavicon:(NSString*)urlString forTab:(BrowserTab*)tab {
    NSURL* url = [NSURL URLWithString:urlString];
    if (!url) return;

    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        if (data && !error) {
            NSImage* image = [[NSImage alloc] initWithData:data];
            if (image) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    tab.favicon = image;
                    if (weakSelf.onFaviconChanged) weakSelf.onFaviconChanged(tab, image);
                });
            }
        }
    }] resume];
}

- (void)showErrorPageForTab:(BrowserTab*)tab error:(NSError*)error failedURL:(NSString*)failedURL {
    NSString* url = failedURL.length ? failedURL : tab.url;
    tab.url = url;
    tab.title = @"Page Load Error";
    [tab.webView loadHTMLString:[TabManager errorPageHTMLForURL:url error:error]
                        baseURL:[NSURL URLWithString:@"https://buildbrowser.local/"]];
    if (self.onTitleChanged) self.onTitleChanged(tab, tab.title);
    if (self.onURLChanged) self.onURLChanged(tab, tab.url);
}

+ (NSString*)errorPageHTMLForURL:(NSString*)url error:(NSError*)error {
    NSString* safeURL = [TabManager htmlEscape:url ?: @""];
    NSString* detail = [TabManager htmlEscape:error.localizedDescription ?: @"The page could not be loaded."];
    NSString* retryHref = [TabManager htmlEscape:url ?: kBuildBrowserStartURL];
    BOOL atsError = [TabManager shouldOfferContinueForError:error url:url];
    NSString* continueLink = @"";
    if (atsError && url.length) {
        NSString* enc = [url stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        continueLink = [NSString stringWithFormat:@"<a class='warning' href='buildbrowser://continue?url=%@'>Continue Anyway</a>", [TabManager htmlEscape:enc]];
    }
    return [NSString stringWithFormat:
        @"<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>Page Load Error</title>"
        "<style>"
        ":root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif}"
        "body{margin:0;min-height:100vh;display:grid;place-items:center;background:Canvas;color:CanvasText}"
        ".panel{width:min(680px,calc(100vw - 48px));padding:34px 0;transform:translateY(-4vh)}"
        ".badge{width:44px;height:44px;border-radius:12px;background:#de5833;color:white;display:grid;place-items:center;font-size:24px;font-weight:700;margin-bottom:18px}"
        "h1{font-size:32px;line-height:1.12;margin:0 0 10px;font-weight:700;letter-spacing:0}"
        "p{font-size:15px;line-height:1.5;margin:0 0 18px;color:color-mix(in srgb,CanvasText 70%%,transparent)}"
        ".url{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;padding:10px 12px;border-radius:9px;background:color-mix(in srgb,CanvasText 8%%,transparent);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-bottom:18px}"
        ".actions{display:flex;gap:10px;flex-wrap:wrap}"
        "a{display:inline-flex;height:36px;align-items:center;border-radius:9px;padding:0 14px;text-decoration:none;font-size:14px;font-weight:600}"
        ".primary{background:#de5833;color:white}.secondary{background:color-mix(in srgb,CanvasText 10%%,transparent);color:CanvasText}.warning{background:#b3261e;color:white}"
        "</style></head><body><main class='panel'>"
        "<div class='badge'>!</div><h1>This page could not be opened</h1>"
        "<p>%@</p><div class='url'>%@</div>"
        "<div class='actions'><a class='primary' href='%@'>Try Again</a>%@<a class='secondary' href='buildbrowser://start'>Start Page</a></div>"
        "</main></body></html>", detail, safeURL, retryHref, continueLink];
}

+ (BOOL)shouldOfferContinueForError:(NSError*)error url:(NSString*)url {
    if (![url.lowercaseString hasPrefix:@"http://"]) return NO;
    if ([error.domain isEqualToString:NSURLErrorDomain] &&
        error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection) return YES;
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return YES;
    if ([error.localizedDescription rangeOfString:@"Frame load interrupted" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

+ (NSString*)htmlEscape:(NSString*)value {
    NSString* escaped = [value stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
    return escaped;
}

- (void)showContextMenuForWebView:(WKWebView*)webView info:(NSDictionary*)info event:(NSEvent*)event {
    NSString* linkURL = [info[@"linkURL"] isKindOfClass:[NSString class]] ? info[@"linkURL"] : @"";
    NSString* linkText = [info[@"linkText"] isKindOfClass:[NSString class]] ? info[@"linkText"] : @"";
    NSString* imageURL = [info[@"imageURL"] isKindOfClass:[NSString class]] ? info[@"imageURL"] : @"";

    NSMenu* menu = [NSMenu new];
    if (linkURL.length) {
        NSDictionary* linkInfo = @{ @"url": linkURL, @"title": linkText.length ? linkText : linkURL };
        NSMenuItem* open = [[NSMenuItem alloc] initWithTitle:@"Open Link in New Tab"
                                                      action:@selector(contextOpenLinkInNewTab:)
                                               keyEquivalent:@""];
        open.target = self; open.representedObject = linkInfo; [menu addItem:open];

        NSMenuItem* copy = [[NSMenuItem alloc] initWithTitle:@"Copy Link"
                                                      action:@selector(contextCopyString:)
                                               keyEquivalent:@""];
        copy.target = self; copy.representedObject = linkURL; [menu addItem:copy];

        NSMenuItem* bookmark = [[NSMenuItem alloc] initWithTitle:@"Bookmark Link"
                                                          action:@selector(contextBookmarkLink:)
                                                   keyEquivalent:@""];
        bookmark.target = self; bookmark.representedObject = linkInfo; [menu addItem:bookmark];
    }

    if (imageURL.length) {
        if (menu.numberOfItems) [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem* save = [[NSMenuItem alloc] initWithTitle:@"Save Image As…"
                                                      action:@selector(contextSaveImage:)
                                               keyEquivalent:@""];
        save.target = self; save.representedObject = imageURL; [menu addItem:save];

        NSMenuItem* copyImageURL = [[NSMenuItem alloc] initWithTitle:@"Copy Image Address"
                                                              action:@selector(contextCopyString:)
                                                       keyEquivalent:@""];
        copyImageURL.target = self; copyImageURL.representedObject = imageURL; [menu addItem:copyImageURL];
    }

    if (menu.numberOfItems) [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* back = [[NSMenuItem alloc] initWithTitle:@"Back" action:@selector(contextBack:) keyEquivalent:@""];
    back.target = self; back.representedObject = webView; back.enabled = webView.canGoBack; [menu addItem:back];

    NSMenuItem* forward = [[NSMenuItem alloc] initWithTitle:@"Forward" action:@selector(contextForward:) keyEquivalent:@""];
    forward.target = self; forward.representedObject = webView; forward.enabled = webView.canGoForward; [menu addItem:forward];

    NSMenuItem* reload = [[NSMenuItem alloc] initWithTitle:@"Reload" action:@selector(contextReload:) keyEquivalent:@""];
    reload.target = self; reload.representedObject = webView; [menu addItem:reload];

    [NSMenu popUpContextMenu:menu withEvent:event forView:webView];
}

- (void)contextOpenLinkInNewTab:(NSMenuItem*)item {
    NSDictionary* info = [item.representedObject isKindOfClass:[NSDictionary class]] ? item.representedObject : @{};
    NSString* url = info[@"url"];
    if (url.length) [self newTabWithURL:url];
}

- (void)contextBookmarkLink:(NSMenuItem*)item {
    NSDictionary* info = [item.representedObject isKindOfClass:[NSDictionary class]] ? item.representedObject : @{};
    NSString* url = info[@"url"];
    NSString* title = info[@"title"];
    if (url.length) [[BookmarkManager profileShared] addBookmarkWithTitle:title.length ? title : url url:url];
}

- (void)contextCopyString:(NSMenuItem*)item {
    NSString* value = [item.representedObject isKindOfClass:[NSString class]] ? item.representedObject : @"";
    [self writeStringToPasteboard:value];
}

- (void)contextSaveImage:(NSMenuItem*)item {
    NSString* urlString = [item.representedObject isKindOfClass:[NSString class]] ? item.representedObject : @"";
    NSURL* url = [NSURL URLWithString:urlString];
    if (!url) return;

    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = [self suggestedFilenameForURL:urlString];
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            if (!data || error) return;
            [data writeToURL:panel.URL atomically:YES];
        }] resume];
    }];
}

- (void)contextBack:(NSMenuItem*)item {
    WKWebView* webView = [item.representedObject isKindOfClass:[WKWebView class]] ? item.representedObject : nil;
    [webView goBack];
}

- (void)contextForward:(NSMenuItem*)item {
    WKWebView* webView = [item.representedObject isKindOfClass:[WKWebView class]] ? item.representedObject : nil;
    [webView goForward];
}

- (void)contextReload:(NSMenuItem*)item {
    WKWebView* webView = [item.representedObject isKindOfClass:[WKWebView class]] ? item.representedObject : nil;
    [webView reload];
}

- (NSString*)suggestedFilenameForURL:(NSString*)urlString {
    NSString* name = [NSURL URLWithString:urlString].lastPathComponent;
    if (!name.length) name = @"image";
    if (!name.pathExtension.length) name = [name stringByAppendingPathExtension:@"png"];
    return name;
}

- (void)writeStringToPasteboard:(NSString*)value {
    if (!value.length) return;
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:value forType:NSPasteboardTypeString];
}

- (NSDictionary*)certificateInfoForTrust:(SecTrustRef)trust host:(NSString*)host {
    NSMutableDictionary* info = [NSMutableDictionary new];
    info[@"host"] = host ?: @"";

    CFErrorRef trustError = NULL;
    BOOL trusted = SecTrustEvaluateWithError(trust, &trustError);
    info[@"trusted"] = @(trusted);
    if (trustError) {
        NSError* err = CFBridgingRelease(trustError);
        info[@"trustError"] = err.localizedDescription ?: @"Trust validation failed";
    }

    CFArrayRef chainRef = SecTrustCopyCertificateChain(trust);
    NSArray* chain = CFBridgingRelease(chainRef) ?: @[];
    info[@"chainLength"] = @(chain.count);

    if (chain.count > 0) {
        SecCertificateRef leaf = (__bridge SecCertificateRef)chain[0];
        NSString* subject = CFBridgingRelease(SecCertificateCopySubjectSummary(leaf));
        if (subject.length) info[@"subject"] = subject;

        NSArray* keys = @[ (__bridge NSString*)kSecOIDX509V1ValidityNotBefore,
                           (__bridge NSString*)kSecOIDX509V1ValidityNotAfter ];
        CFErrorRef valueError = NULL;
        NSDictionary* values = CFBridgingRelease(SecCertificateCopyValues(leaf, (__bridge CFArrayRef)keys, &valueError));
        NSDictionary* before = values[(__bridge NSString*)kSecOIDX509V1ValidityNotBefore];
        NSDictionary* after = values[(__bridge NSString*)kSecOIDX509V1ValidityNotAfter];
        if (before[(__bridge NSString*)kSecPropertyKeyValue])
            info[@"notBefore"] = before[(__bridge NSString*)kSecPropertyKeyValue];
        if (after[(__bridge NSString*)kSecPropertyKeyValue])
            info[@"notAfter"] = after[(__bridge NSString*)kSecPropertyKeyValue];
        if (valueError) CFRelease(valueError);
    }

    if (chain.count > 1) {
        SecCertificateRef issuer = (__bridge SecCertificateRef)chain[1];
        NSString* issuerSummary = CFBridgingRelease(SecCertificateCopySubjectSummary(issuer));
        if (issuerSummary.length) info[@"issuer"] = issuerSummary;
    }

    return info;
}

- (BOOL)shouldOpenSearchClickInNewTab:(WKNavigationAction*)navigationAction fromWebView:(WKWebView*)webView {
    if (navigationAction.navigationType != WKNavigationTypeLinkActivated) return NO;
    NSURL* sourceURL = webView.URL;
    NSURL* targetURL = navigationAction.request.URL;
    if (![self isSearchResultsPage:sourceURL] || !targetURL.absoluteString.length) return NO;

    NSString* targetHost = targetURL.host.lowercaseString ?: @"";
    if ([targetHost containsString:@"duckduckgo.com"]) {
        NSString* path = targetURL.path.lowercaseString ?: @"";
        if (![path hasPrefix:@"/l/"] && ![targetURL.query containsString:@"uddg="])
            return NO;
    }
    return YES;
}

- (BOOL)isSearchResultsPage:(NSURL*)url {
    NSString* host = url.host.lowercaseString ?: @"";
    if (![host containsString:@"duckduckgo.com"]) return NO;
    NSString* query = url.query ?: @"";
    if ([query containsString:@"q="]) return YES;
    NSString* path = url.path.lowercaseString ?: @"";
    return [path isEqualToString:@"/"] || [path isEqualToString:@"/html/"];
}

- (BrowserTab*)tabForWebView:(WKWebView*)wv {
    for (BrowserTab* t in _mutableTabs)
        if (t.webView == wv) return t;
    return nil;
}

@end
