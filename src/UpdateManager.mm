/**
 * @file      UpdateManager.mm
 * @project   BuildBrowser
 * @brief     Software update engine — fetch, download, and install.
 *
 * @details   Checks a JSON manifest from the configured feed URL (default:
 *            GitHub raw manifest.json). Compares remote build number against
 *            the current bundle. If a newer build exists, prompts the user,
 *            downloads the .zip archive, unpacks it via /usr/bin/ditto,
 *            and runs a shell script that waits for the current process to
 *            exit, then replaces the app bundle and relaunches.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "UpdateManager.h"
#import "SettingsManager.h"
#import <sys/stat.h>
#import <unistd.h>

// ───────────────────────────────────────────────────────────────────────────────
// @name Internal Helpers
// ───────────────────────────────────────────────────────────────────────────────

/// Safely coerce a value to NSString, returning @"". Handles nil/KVO.
static NSString* BBStringOrEmpty(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

/// Shell-quote a string for use in the installer script.
static NSString* BBShellQuote(NSString* value) {
    if (!value.length) return @"''";
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

/// Default update feed URL (public GitHub).
static NSString* const kDefaultUpdateFeedURL = @"https://raw.githubusercontent.com/kiro-browser/browser-core/dev/updates/manifest.json";

/// Extract the first 500 bytes of data as a UTF-8 snippet for error reporting.
static NSString* BBBodySnippet(NSData* data) {
    if (!data.length) return @"";
    NSUInteger length = MIN((NSUInteger)500, data.length);
    NSData* prefix = [data subdataWithRange:NSMakeRange(0, length)];
    NSString* text = [[NSString alloc] initWithData:prefix encoding:NSUTF8StringEncoding] ?: @"";
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : @"The response was not UTF-8 text.";
}

/// Convert a GitHub blob URL to a raw.githubusercontent.com URL.
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

#pragma mark - Private Interface

@interface UpdateManager () <NSURLSessionDownloadDelegate>

/// Session for manifest fetching (data tasks).
@property (strong) NSURLSession* session;
/// Session for update bundle download (download tasks).
@property (strong) NSURLSession* downloadSession;
/// The active download task for the update bundle.
@property (strong) NSURLSessionDownloadTask* activeUpdateTask;
/// The manifest dict for the currently downloading update.
@property (copy) NSDictionary* activeUpdateManifest;

// Progress window UI
@property (strong) NSWindow* progressWindow;
@property (strong) NSTextField* progressTitleLabel;
@property (strong) NSTextField* progressDetailLabel;
@property (strong) NSProgressIndicator* progressIndicator;
@property (strong) NSButton* cancelButton;

/// Whether an update check is currently in progress.
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

#pragma mark - Implementation

@implementation UpdateManager

/**
 * @brief   Returns the shared UpdateManager singleton.
 *
 * @return  The singleton instance.
 */
+ (instancetype)shared {
    static UpdateManager* inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [UpdateManager new];
    });
    return inst;
}

/**
 * @brief   Initialize with ephemeral URL sessions for manifest and download.
 *
 * @return  An initialized UpdateManager.
 */
- (instancetype)init {
    self = [super init];
    if (self) {
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
        NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        _downloadSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    }
    return self;
}

/**
 * @brief   Check for updates and prompt the user (user-initiated).
 */
- (void)checkForUpdates {
    [self checkForUpdatesPrompting:YES];
}

/**
 * @brief   Check for updates silently (auto-launch check).
 */
- (void)checkForUpdatesSilently {
    [self checkForUpdatesPrompting:NO];
}

/**
 * @brief   Core update check logic.
 *
 * @details Fetches the manifest JSON, validates it, compares build numbers,
 *          and either prompts (if newer) or reports no updates available
 *          (if prompting is enabled).
 *
 * @param   prompt  If YES, shows alerts for success (no update) and failures.
 */
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
        dispatch_async(dispatch_get_main_queue(), ^{ self.checking = NO; });

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
                    [self presentAlert:@"Update Check Failed" message:message];
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

/**
 * @brief   Show an update-available alert and ask the user to download.
 */
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

/**
 * @brief   Start downloading the update bundle.
 */
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

/**
 * @brief   Install the downloaded update: unzip, replace app bundle, relaunch.
 *
 * @details Uses /usr/bin/ditto to unzip the downloaded archive. Finds the
 *          .app bundle inside, then writes a shell script that waits for
 *          the current process (getpid) to exit, removes the old app,
 *          copies the new one, and reopens it.
 */
- (void)installDownloadedUpdateAtURL:(NSURL*)location manifest:(NSDictionary*)manifest {
        [self updateProgressTitle:@"Installing Update" detail:@"Unpacking update archive..." percent:1.0 indeterminate:YES];
        NSString* tempRoot = [@"/private/tmp" stringByAppendingPathComponent:[NSString stringWithFormat:@"BuildBrowserUpdate-%@", [[NSUUID UUID] UUIDString]]];
        NSString* unzipRoot = [tempRoot stringByAppendingPathComponent:@"unpacked"];
        NSString* scriptPath = [tempRoot stringByAppendingPathComponent:@"install.sh"];
        NSString* bundlePath = [NSBundle mainBundle].bundlePath;
        NSString* bundleName = bundlePath.lastPathComponent;
        [[NSFileManager defaultManager] createDirectoryAtPath:unzipRoot withIntermediateDirectories:YES attributes:nil error:nil];

        // Unzip using ditto
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

        // Shell script: wait for this process to die, then replace and reopen.
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

// ───────────────────────────────────────────────────────────────────────────────
// @name Progress Window
// ───────────────────────────────────────────────────────────────────────────────

/** @brief   Show or update the download progress window. */
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

/** @brief   Update the progress window's status and progress bar. */
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

/** @brief   Close and clean up the progress window. */
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

/** @brief   Cancel the active download. */
- (void)cancelUpdateDownload:(id)sender {
    [self.activeUpdateTask cancel];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name NSURLSessionDownloadDelegate
// ───────────────────────────────────────────────────────────────────────────────

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

// ───────────────────────────────────────────────────────────────────────────────
// @name Helpers
// ───────────────────────────────────────────────────────────────────────────────

/** @brief   Search a directory for the first .app bundle. */
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

/** @brief   Show a modal alert sheet on the key window. */
- (void)presentAlert:(NSString*)title message:(NSString*)message {
    NSAlert* alert = [NSAlert new];
    alert.messageText = title ?: @"Update";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:[self presentationWindow] completionHandler:nil];
}

/** @brief   Return the best available window for sheet presentation. */
- (NSWindow*)presentationWindow {
    return NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
}

@end
