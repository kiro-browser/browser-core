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

@interface UpdateManager ()
@property (strong) NSURLSession* session;
@property (assign) BOOL checking;
- (void)checkForUpdatesPrompting:(BOOL)prompt;
- (void)promptForUpdate:(NSDictionary*)manifest currentBuild:(NSInteger)currentBuild remoteBuild:(NSInteger)remoteBuild;
- (void)downloadAndInstallUpdate:(NSDictionary*)manifest;
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
    NSString* feedURLString = settings.updateFeedURL.length ? settings.updateFeedURL : @"http://127.0.0.1:8787/manifest.json";
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

        NSError* jsonError = nil;
        NSDictionary* manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (![manifest isKindOfClass:[NSDictionary class]]) {
            if (prompt) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self presentAlert:@"Update Check Failed"
                               message:@"The update manifest was not valid JSON."];
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

    NSURLSessionDownloadTask* task = [self.session downloadTaskWithURL:bundleURL completionHandler:^(NSURL* location, NSURLResponse* response, NSError* error) {
        if (error || !location) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentAlert:@"Update Failed" message:error.localizedDescription ?: @"The update archive could not be downloaded."];
            });
            return;
        }

        NSString* tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"BuildBrowserUpdate-%@", [[NSUUID UUID] UUIDString]]];
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
                [self presentAlert:@"Update Failed" message:@"The update archive could not be unpacked."];
            });
            return;
        }

        NSString* stagedApp = [self findAppBundleInsideDirectory:unzipRoot preferredName:bundleName];
        if (!stagedApp.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentAlert:@"Update Failed" message:@"The update archive did not contain an app bundle."];
            });
            return;
        }

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
                [self presentAlert:@"Update Failed" message:@"The installer could not be started."];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    }];

    [task resume];
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
