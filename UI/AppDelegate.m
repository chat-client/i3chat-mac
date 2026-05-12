//
//  AppDelegate.m
//  i3Chat
//

#import "AppDelegate.h"
#import "MainWindowController.h"
#import "LocalizationManager.h"
#import "DebugLog.h"

@interface AppDelegate ()

@property (nonatomic, strong) MainWindowController *mainWindowController;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    ADLog(@"AppDelegate: applicationDidFinishLaunching called");
    @try {
        // Explicitly initialize LocalizationManager before using it
        [LocalizationManager sharedManager];
        
        NSImage *appIcon = nil;
        NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"png"];
        if (iconPath.length > 0) {
            appIcon = [[NSImage alloc] initWithContentsOfFile:iconPath];
        }
        if (appIcon) {
            [NSApp setApplicationIconImage:appIcon];
        }

        // Delay initialization slightly to ensure app is fully ready
        dispatch_async(dispatch_get_main_queue(), ^{
            ADLog(@"AppDelegate: Creating MainWindowController");
            @try {
                self.mainWindowController = [[MainWindowController alloc] init];
                ADLog(@"AppDelegate: MainWindowController created: %@", self.mainWindowController ? @"YES" : @"NO");
                // Window is shown in MainWindowController's init
            } @catch (NSException *exception) {
                ADLog(@"Error creating main window controller: %@", exception);
                ADLog(@"Stack trace: %@", [exception callStackSymbols]);
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = L(@"app.alert.appError.title", @"Application Error");
                alert.informativeText = [NSString stringWithFormat:L(@"app.alert.appError.message", @"Failed to initialize: %@"), exception.reason];
                [alert runModal];
                [NSApp terminate:nil];
            }
        });
    } @catch (NSException *exception) {
        ADLog(@"Fatal error in applicationDidFinishLaunching: %@", exception);
        ADLog(@"Stack trace: %@", [exception callStackSymbols]);
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = L(@"app.alert.fatal.title", @"Fatal Error");
        alert.informativeText = [NSString stringWithFormat:L(@"app.alert.fatal.message", @"Application failed to start: %@"), exception.reason];
        [alert runModal];
        [NSApp terminate:nil];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    // Don't terminate when the last window is closed
    // App stays in Dock and can be reopened
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
    // When user clicks on Dock icon, always show the main window and bring it to front
    // This handles the case where other windows (like channel list, whois) are visible
    // but the main window is closed
    if (self.mainWindowController && self.mainWindowController.window) {
        [self.mainWindowController.window makeKeyAndOrderFront:nil];
    }
    return YES;
}

@end
