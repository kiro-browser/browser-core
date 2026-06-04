#import "UpdateManager.h"

#import "SettingsManager.h"
#import <sys/stat.h>
#import <unistd.h>

static NSString* BBStringOrEmpty(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSString* BBShellQuote(NSString* value) {
    if (!value.length) return @"''";
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static NSString* const kDefaultUpdateFeedURL = @"https://raw.githubusercontent.com/kiro-browser/browser-core/dev/updates/manifest.json";

static NSString* BBBodySnippet(NSData* data) {
    if (!data.length) return @"";
    NSUInteger length = MIN((NSUInteger)500, data.length);
    NSData* prefix = [data subdataWithRange:NSMakeRange(0, length)];
    NSString* text = [[NSString alloc] initWithData:prefix encoding:NSUTF8StringEncoding] ?: @"";
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : @"The response was not UTF-8 text.";
}

static NSString* BBNormalizeUpdateFeedURL(NSString* value) {
    if (!value.length) return value;
    NSURLComponents* components = [NSURLComponents componentsWithString:value];
    if (!components) return value;

    NSString* host = components.host.lowercaseString;
    if (![host isEqualToString:@"github.com"]) return value;

    NSArray<NSString*>* parts = [components.path componentsSeparatedByString:@"/"];
    NSMutableArray<NSString*>* clean = [NSMutableArray new];
    for (NSString* part in parts) {
        if (part.length) [clean addObject:part];
    }
    if (clean.count < 5 || ![clean[2] isEqualToString:@"blob"]) return value;

    NSString* owner = clean[0];
    NSString* repo = clean[1];
    NSString* branch = clean[3];
    NSArray<NSString*>* pathParts = [clean subarrayWithRange:NSMakeRange(4, clean.count - 4)];
    NSString* rawPath = [pathParts componentsJoinedByString:@"/"];
    return [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/%@/%@", owner, repo, branch, rawPath];
}

@interface UpdateManager () <NSURLSessionDownloadDelegate>
@property (strong) NSURLSession* session;
@property (strong) NSURLSession* downloadSession;
@property (strong) NSURLSessionDownloadTask* activeUpdateTask;
@property (copy) NSDictionary* activeUpdateManifest;
@property (strong) NSWindow* progressWindow;
@property (strong) NSTextField* progressTitleLabel;
@property (strong) NSTextField* progressDetailLabel;
@property (strong) NSProgressIndicator* progressIndicator;
@property (strong) NSButton* cancelButton;
@property (assign) BOOL checking;
- (void)checkForUpdatesPrompting:(BOOL)prompt;
- (void)promptForUpdate:(NSDictionary*)manifest currentBuild:(NSInteger)currentBuild remoteBuild:(NSInteger)remoteBuild;
- (void)downloadAndInstallUpdate:(NSDictionary*)manifest;
- (void)installDownloadedUpdateAtURL:(NSURL*)location manifest:(NSDictionary*)manifest;
- (void)showUpdateProgressWindowForManifest:(NSDictionary*)manifest;
- (void)updateProgressTitle:(NSString*)title detail:(NSString*)detail percent:(double)percent indeterminate:(BOOL)indeterminate;
- (void)closeUpdateProgressWindow;
- (void)cancelUpdateDownload:(id)sender;
- (NSString*)findAppBundleInsideDirectory:(NSString*)root preferredName:(NSString*)bundleName;
- (void)presentAlert:(NSString*)title message:(NSString*)message;
- (NSWindow*)presentationWindow;
@end

@implementation UpdateManager

+ (instancetype)shared {
    static UpdateManager* inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [UpdateManager new];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
        NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        _downloadSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    }
    return self;
}

- (void)checkForUpdates {
    [self checkForUpdatesPrompting:YES];
}

- (void)checkForUpdatesSilently {
    [self checkForUpdatesPrompting:NO];
}

- (void)checkForUpdatesPrompting:(BOOL)prompt {
    if (self.checking) return;
    self.checking = YES;

    SettingsManager* settings = [SettingsManager profileShared];
    NSString* feedURLString = BBNormalizeUpdateFeedURL(settings.updateFeedURL.length ? settings.updateFeedURL : kDefaultUpdateFeedURL);
    NSURL* feedURL = [NSURL URLWithString:feedURLString];
    if (!feedURL) {
        self.checking = NO;
        if (prompt) [self presentAlert:@"Update Check Failed" message:@"The configured update feed URL is invalid."];
        return;
    }

    NSURLSessionDataTask* task = [self.session dataTaskWithURL:feedURL completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.checking = NO;
        });

        if (error || !data.length) {
            if (prompt) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self presentAlert:@"Update Check Failed"
                               message:error.localizedDescription ?: @"The update server did not respond."];
                });
            }
            return;
        }

        NSHTTPURLResponse* http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)response : nil;
        if (http && (http.statusCode < 200 || http.statusCode >= 300)) {
            if (prompt) {
                NSString* snippet = BBBodySnippet(data);
                NSString* message = [NSString stringWithFormat:@"The update server returned HTTP %@ for:\n%@%@%@",
                                     @(http.statusCode), feedURLString, snippet.length ? @"\n\nResponse:\n" : @"", snippet];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self presentAlert:@"Update Check Failed" message:message];
                });
            }
            return;
        }

        NSError* jsonError = nil;
        NSDictionary* manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (![manifest isKindOfClass:[NSDictionary class]]) {
            if (prompt) {
                NSString* snippet = BBBodySnippet(data);
                NSString* message = [NSString stringWithFormat:@"The update manifest was not valid JSON.\n\nURL:\n%@%@%@",
                                     feedURLString, snippet.length ? @"\n\nResponse:\n" : @"", snippet];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self presentAlert:@"Update Check Failed"
                               message:message];
                });
            }
            return;
        }

        NSInteger currentBuild = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] integerValue];
        NSInteger remoteBuild = [manifest[@"build"] integerValue];
        if (remoteBuild <= currentBuild) {
            if (prompt) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self presentAlert:@"No Updates Available"
                               message:@"BuildBrowser is already on the latest build."];
                });
            }
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self promptForUpdate:manifest currentBuild:currentBuild remoteBuild:remoteBuild];
        });
    }];

    [task resume];
}

- (void)promptForUpdate:(NSDictionary*)manifest currentBuild:(NSInteger)currentBuild remoteBuild:(NSInteger)remoteBuild {
    NSString* version = BBStringOrEmpty(manifest[@"version"]);
    NSString* notes = BBStringOrEmpty(manifest[@"notes"]);
    NSString* title = [NSString stringWithFormat:@"Build %@ is available", @(remoteBuild)];
    NSString* message = version.length ? [NSString stringWithFormat:@"Version %@ is ready to install.", version]
                                       : @"A newer build is ready to install.";
    if (notes.length) {
        message = [message stringByAppendingFormat:@"\n\n%@", notes];
    }

    NSAlert* alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = [NSString stringWithFormat:@"%@\nCurrent build: %@", message, @(currentBuild)];
    [alert addButtonWithTitle:@"Download & Install"];
    [alert addButtonWithTitle:@"Later"];
    [alert beginSheetModalForWindow:[self presentationWindow] completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [self downloadAndInstallUpdate:manifest];
        }
    }];
}

- (void)downloadAndInstallUpdate:(NSDictionary*)manifest {
    if (self.activeUpdateTask) return;

    NSString* bundleURLString = BBStringOrEmpty(manifest[@"bundleURL"]);
    if (!bundleURLString.length) bundleURLString = BBStringOrEmpty(manifest[@"url"]);
    if (!bundleURLString.length) {
        [self presentAlert:@"Update Failed" message:@"The manifest did not provide a bundle URL."];
        return;
    }

    NSURL* bundleURL = [NSURL URLWithString:bundleURLString];
    if (!bundleURL) {
        [self presentAlert:@"Update Failed" message:@"The update bundle URL is invalid."];
        return;
    }

    self.activeUpdateManifest = manifest;
    [self showUpdateProgressWindowForManifest:manifest];
    NSURLSessionDownloadTask* task = [self.downloadSession downloadTaskWithURL:bundleURL];
    self.activeUpdateTask = task;
    [task resume];
}

- (void)installDownloadedUpdateAtURL:(NSURL*)location manifest:(NSDictionary*)manifest {
        [self updateProgressTitle:@"Installing Update" detail:@"Unpacking update archive..." percent:1.0 indeterminate:YES];
        NSString* tempRoot = [@"/private/tmp" stringByAppendingPathComponent:[NSString stringWithFormat:@"BuildBrowserUpdate-%@", [[NSUUID UUID] UUIDString]]];
        NSString* unzipRoot = [tempRoot stringByAppendingPathComponent:@"unpacked"];
        NSString* scriptPath = [tempRoot stringByAppendingPathComponent:@"install.sh"];
        NSString* bundlePath = [NSBundle mainBundle].bundlePath;
        NSString* bundleName = bundlePath.lastPathComponent;
        [[NSFileManager defaultManager] createDirectoryAtPath:unzipRoot withIntermediateDirectories:YES attributes:nil error:nil];

        NSTask* unzip = [NSTask new];
        unzip.launchPath = @"/usr/bin/ditto";
        unzip.arguments = @[ @"-x", @"-k", location.path, unzipRoot ];
        @try {
            [unzip launch];
            [unzip waitUntilExit];
        } @catch (__unused NSException* e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self closeUpdateProgressWindow];
                [self presentAlert:@"Update Failed" message:@"The update archive could not be unpacked."];
            });
            return;
        }
        if (unzip.terminationStatus != 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self closeUpdateProgressWindow];
                [self presentAlert:@"Update Failed" message:@"The update archive could not be unpacked."];
            });
            return;
        }

        NSString* stagedApp = [self findAppBundleInsideDirectory:unzipRoot preferredName:bundleName];
        if (!stagedApp.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self closeUpdateProgressWindow];
                [self presentAlert:@"Update Failed" message:@"The update archive did not contain an app bundle."];
            });
            return;
        }

        [self updateProgressTitle:@"Installing Update" detail:@"Preparing to replace the app and relaunch..." percent:1.0 indeterminate:YES];
        NSString* waitPid = [NSString stringWithFormat:@"%d", getpid()];
        NSString* script = [NSString stringWithFormat:
            @"#!/bin/sh\n"
            "set -eu\n"
            "APP=%@\n"
            "STAGED=%@\n"
            "PID=%@\n"
            "while kill -0 \"$PID\" 2>/dev/null; do\n"
            "  sleep 0.5\n"
            "done\n"
            "/bin/rm -rf \"$APP\"\n"
            "/usr/bin/ditto \"$STAGED\" \"$APP\"\n"
            "/usr/bin/open \"$APP\"\n",
            BBShellQuote(bundlePath),
            BBShellQuote(stagedApp),
            BBShellQuote(waitPid)];

        NSError* writeError = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:tempRoot withIntermediateDirectories:YES attributes:nil error:nil];
        [script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
        if (writeError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self closeUpdateProgressWindow];
                [self presentAlert:@"Update Failed" message:writeError.localizedDescription ?: @"The installer script could not be written."];
            });
            return;
        }

        chmod(scriptPath.fileSystemRepresentation, 0755);
        NSTask* installer = [NSTask new];
        installer.launchPath = @"/bin/sh";
        installer.arguments = @[ scriptPath ];
        @try {
            [installer launch];
        } @catch (__unused NSException* e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self closeUpdateProgressWindow];
                [self presentAlert:@"Update Failed" message:@"The installer could not be started."];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateProgressTitle:@"Relaunching" detail:@"BuildBrowser will quit, install the update, and reopen." percent:1.0 indeterminate:YES];
            [NSApp terminate:nil];
        });
}

- (void)showUpdateProgressWindowForManifest:(NSDictionary*)manifest {
    if (self.progressWindow) {
        [self.progressWindow makeKeyAndOrderFront:nil];
        return;
    }

    NSWindow* parent = [self presentationWindow];
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 146)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.title = @"Software Update";
    window.releasedWhenClosed = NO;

    NSView* content = window.contentView;
    NSTextField* title = [NSTextField labelWithString:@"Downloading Update"];
    title.frame = NSMakeRect(20, 102, 380, 22);
    title.font = [NSFont boldSystemFontOfSize:15];
    [content addSubview:title];

    NSTextField* detail = [NSTextField labelWithString:@"Starting download..."];
    detail.frame = NSMakeRect(20, 78, 380, 18);
    detail.font = [NSFont systemFontOfSize:12];
    detail.textColor = [NSColor secondaryLabelColor];
    [content addSubview:detail];

    NSProgressIndicator* progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 48, 380, 16)];
    progress.style = NSProgressIndicatorStyleBar;
    progress.minValue = 0.0;
    progress.maxValue = 100.0;
    progress.doubleValue = 0.0;
    progress.indeterminate = YES;
    [progress startAnimation:nil];
    [content addSubview:progress];

    NSButton* cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelUpdateDownload:)];
    cancel.frame = NSMakeRect(318, 12, 82, 28);
    cancel.bezelStyle = NSBezelStyleRounded;
    [content addSubview:cancel];

    self.progressWindow = window;
    self.progressTitleLabel = title;
    self.progressDetailLabel = detail;
    self.progressIndicator = progress;
    self.cancelButton = cancel;

    if (parent) {
        [parent beginSheet:window completionHandler:nil];
    } else {
        [window center];
        [window makeKeyAndOrderFront:nil];
    }
}

- (void)updateProgressTitle:(NSString*)title detail:(NSString*)detail percent:(double)percent indeterminate:(BOOL)indeterminate {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.progressWindow) return;
        self.progressTitleLabel.stringValue = title ?: @"Updating";
        self.progressDetailLabel.stringValue = detail ?: @"";
        self.progressIndicator.indeterminate = indeterminate;
        if (indeterminate) {
            [self.progressIndicator startAnimation:nil];
        } else {
            [self.progressIndicator stopAnimation:nil];
            self.progressIndicator.doubleValue = MAX(0.0, MIN(100.0, percent * 100.0));
        }
    });
}

- (void)closeUpdateProgressWindow {
    if (!self.progressWindow) return;
    NSWindow* window = self.progressWindow;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow* parent = window.sheetParent;
        if (parent) [parent endSheet:window];
        [window orderOut:nil];
    });
    self.progressWindow = nil;
    self.progressTitleLabel = nil;
    self.progressDetailLabel = nil;
    self.progressIndicator = nil;
    self.cancelButton = nil;
}

- (void)cancelUpdateDownload:(id)sender {
    [self.activeUpdateTask cancel];
}

- (void)URLSession:(NSURLSession*)session downloadTask:(NSURLSessionDownloadTask*)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (downloadTask != self.activeUpdateTask) return;
    if (totalBytesExpectedToWrite > 0) {
        double percent = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
        NSString* detail = [NSString stringWithFormat:@"Downloaded %.0f%%", percent * 100.0];
        [self updateProgressTitle:@"Downloading Update" detail:detail percent:percent indeterminate:NO];
    } else {
        NSString* detail = [NSString stringWithFormat:@"Downloaded %.1f MB", (double)totalBytesWritten / 1024.0 / 1024.0];
        [self updateProgressTitle:@"Downloading Update" detail:detail percent:0.0 indeterminate:YES];
    }
}

- (void)URLSession:(NSURLSession*)session downloadTask:(NSURLSessionDownloadTask*)downloadTask
didFinishDownloadingToURL:(NSURL*)location {
    if (downloadTask != self.activeUpdateTask) return;
    NSURL* destination = [NSURL fileURLWithPath:[@"/private/tmp" stringByAppendingPathComponent:[NSString stringWithFormat:@"BuildBrowserUpdate-%@.zip", [[NSUUID UUID] UUIDString]]]];
    NSError* error = nil;
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:destination error:&error];
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.activeUpdateTask = nil;
            self.activeUpdateManifest = nil;
            [self closeUpdateProgressWindow];
            [self presentAlert:@"Update Failed" message:error.localizedDescription ?: @"The update archive could not be saved."];
        });
        return;
    }

    NSDictionary* manifest = self.activeUpdateManifest;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.activeUpdateTask = nil;
        self.activeUpdateManifest = nil;
        [self installDownloadedUpdateAtURL:destination manifest:manifest ?: @{}];
    });
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    if (task != self.activeUpdateTask || !error) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.activeUpdateTask = nil;
        self.activeUpdateManifest = nil;
        [self closeUpdateProgressWindow];
        if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
        [self presentAlert:@"Update Failed" message:error.localizedDescription ?: @"The update archive could not be downloaded."];
    });
}

- (NSString*)findAppBundleInsideDirectory:(NSString*)root preferredName:(NSString*)bundleName {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray<NSString*>* entries = [fm contentsOfDirectoryAtPath:root error:nil];
    for (NSString* entry in entries) {
        if ([entry.pathExtension.lowercaseString isEqualToString:@"app"]) {
            return [root stringByAppendingPathComponent:entry];
        }
    }
    if (bundleName.length) {
        NSString* candidate = [root stringByAppendingPathComponent:bundleName];
        if ([fm fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

- (void)presentAlert:(NSString*)title message:(NSString*)message {
    NSAlert* alert = [NSAlert new];
    alert.messageText = title ?: @"Update";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:[self presentationWindow] completionHandler:nil];
}

- (NSWindow*)presentationWindow {
    return NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
}

@end
