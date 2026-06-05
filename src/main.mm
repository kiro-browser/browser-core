/**
 * @file      main.mm
 * @project   BuildBrowser
 * @brief     Application entry point.
 *
 * @details   Creates the shared NSApplication, sets the activation policy
 *            to regular (app appears in Dock), installs the AppDelegate,
 *            and starts the main event loop. This is the macOS Cocoa
 *            entry point; the legacy GTK main (main.cpp) is deprecated.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

/**
 * @brief   Program entry point — launches the Cocoa application.
 *
 * @param   argc  Argument count from the command line / launchd.
 * @param   argv  Argument vector.
 * @return  Process exit code (typically 0 on normal termination).
 */
int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        AppDelegate* delegate = [AppDelegate new];
        app.delegate = delegate;

        [app run];
    }
    return 0;
}
