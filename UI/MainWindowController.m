//
//  MainWindowController.m
//  i3Chat
//

#import "MainWindowController.h"
#import "IRCClient.h"
#import "IRCConfig.h"
#import "LoginWindowController.h"
#import "ChatViewController.h"
#import "LocalizationManager.h"
#import "ServerHistoryStorage.h"
#import "DebugLog.h"

@interface MainWindowController () <LoginWindowControllerDelegate>

@property (nonatomic, strong) ChatViewController *chatViewController;
@property (nonatomic, strong) LoginWindowController *loginWindowController;
@property (nonatomic, strong) NSTitlebarAccessoryViewController *titlebarAccessory;
@property (nonatomic, strong) NSButton *toggleChannelsButton;
@property (nonatomic, strong) NSButton *toggleLogButton;
@property (nonatomic, strong) NSButton *toggleUsersButton;
@property (nonatomic, strong) NSButton *settingsButton;

@end

@interface MainWindow : NSWindow
@end

@implementation MainWindow

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    // Handle Ctrl+O to toggle log window
    if ((event.modifierFlags & NSEventModifierFlagControl) == NSEventModifierFlagControl) {
        if (event.keyCode == 31) { // 'O' key
            MainWindowController *controller = (MainWindowController *)self.windowController;
            if (controller) {
                // Access the private property using valueForKey since it's in the same file
                ChatViewController *chatVC = [controller valueForKey:@"chatViewController"];
                if (chatVC && [chatVC respondsToSelector:@selector(toggleLogWindow)]) {
                    [chatVC toggleLogWindow];
                    return YES;
                }
            }
        }
    }
    
    // Call super for other key events
    return [super performKeyEquivalent:event];
}

@end

@implementation MainWindowController

static NSInteger const CommandsMenuItemTag = 5001;
static NSInteger const HelpMenuItemTag = 5002;
static NSInteger const ServersMenuItemTag = 5003;
static NSInteger const WindowMenuItemTag = 5004;

- (instancetype)init {
    // Don't create window yet, defer it
    self = [super initWithWindow:nil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleLocalizationDidChange:)
                                                     name:LocalizationDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleServerHistoryDidUpdate:)
                                                     name:ServerHistoryDidUpdateNotification
                                                   object:nil];
        @try {
            MWLog(@"MainWindowController: Creating LoginWindowController");
            // Show login window immediately with defaults - no database access
            self.loginWindowController = [[LoginWindowController alloc] init];
            MWLog(@"MainWindowController: LoginWindowController created: %@", self.loginWindowController ? @"YES" : @"NO");
            
            if (!self.loginWindowController) {
                MWLog(@"Error: Failed to create LoginWindowController");
                return self;
            }
            
            MWLog(@"MainWindowController: Setting delegate");
            self.loginWindowController.delegate = self;
            
            MWLog(@"MainWindowController: Scheduling window show");
            // Delay showing window slightly to ensure UI is fully initialized
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try {
                    MWLog(@"MainWindowController: Attempting to show window");
                    if (self.loginWindowController && self.loginWindowController.window) {
                        MWLog(@"MainWindowController: Window exists, showing");
                        [self.loginWindowController showWindow:nil];
                        [self.loginWindowController.window makeKeyAndOrderFront:nil];
                        MWLog(@"MainWindowController: Window shown");
                    } else {
                        MWLog(@"MainWindowController: Window is nil");
                    }
                } @catch (NSException *exception) {
                    MWLog(@"Error showing login window: %@", exception);
                    MWLog(@"Stack trace: %@", [exception callStackSymbols]);
                }
            });
            MWLog(@"MainWindowController: Window show scheduled");
        } @catch (NSException *exception) {
            MWLog(@"Error creating login window: %@", exception);
            MWLog(@"Stack trace: %@", [exception callStackSymbols]);
            // Try to show a simple alert
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = L(@"app.alert.initError.title", @"Initialization Error");
                    alert.informativeText = [NSString stringWithFormat:L(@"app.alert.initError.message", @"Failed to create login window: %@"), exception.reason];
                    [alert runModal];
                } @catch (NSException *alertException) {
                    MWLog(@"Error showing alert: %@", alertException);
                }
            });
        }
        
        // Load last login info asynchronously and update login window if available
        // Delay significantly to ensure database is initialized
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                ServerHistoryStorage *storage = [ServerHistoryStorage sharedStorage];
                if (storage) {
                    LoginInfo *lastLogin = [storage getLastLoginInfo];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try {
                            if (lastLogin && lastLogin.server.length > 0 && self.loginWindowController) {
                                // Update login window with last login info
                                if (self.loginWindowController.serverField) {
                                    self.loginWindowController.serverField.stringValue = lastLogin.server;
                                }
                                if (lastLogin.nick && self.loginWindowController.nickField) {
                                    self.loginWindowController.nickField.stringValue = lastLogin.nick;
                                }
                                if (lastLogin.channel && self.loginWindowController.channelField) {
                                    self.loginWindowController.channelField.stringValue = lastLogin.channel;
                                }
                                if (lastLogin.realName && self.loginWindowController.realNameField) {
                                    self.loginWindowController.realNameField.stringValue = lastLogin.realName;
                                }
                                if (lastLogin.password && self.loginWindowController.passwordField) {
                                    self.loginWindowController.passwordField.stringValue = lastLogin.password;
                                }
                                if (self.loginWindowController.savePasswordCheckbox) {
                                    self.loginWindowController.savePasswordCheckbox.state = lastLogin.savePassword ? NSControlStateValueOn : NSControlStateValueOff;
                                }
                                if (self.loginWindowController.useTLSCheckbox) {
                                    BOOL useTLS;
                                    if ([lastLogin.server hasSuffix:@":6697"]) useTLS = YES;
                                    else if ([lastLogin.server hasSuffix:@":6667"]) useTLS = NO;
                                    else useTLS = lastLogin.useTLS;
                                    self.loginWindowController.useTLSCheckbox.state = useTLS ? NSControlStateValueOn : NSControlStateValueOff;
                                }
                            }
                        } @catch (NSException *exception) {
                            MWLog(@"Error updating login window: %@", exception);
                        }
                    });
                }
            } @catch (NSException *exception) {
                MWLog(@"Error loading login history: %@", exception);
            }
        });
    }
    return self;
}

- (void)loginWindowController:(LoginWindowController *)controller didLoginWithConfigs:(NSArray<IRCConfig *> *)configs {
    // Ensure we're on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loginWindowController:controller didLoginWithConfigs:configs];
        });
        return;
    }
    
    [controller.window close];
    
    // Create main window now
    if (!self.window) {
        NSRect screenRect = [[NSScreen mainScreen] frame];
        NSRect windowRect = NSMakeRect(
            (screenRect.size.width - 1200) / 2,
            (screenRect.size.height - 800) / 2,
            1200,
            800
        );
        
        MainWindow *window = [[MainWindow alloc] initWithContentRect:windowRect
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window setTitle:L(@"main.window.title", @"i3Chat - IRC Client")];
        [window setMinSize:NSMakeSize(800, 600)];
        [self setWindow:window];
    }
    
    // Clear any existing subviews
    for (NSView *subview in [self.window.contentView.subviews copy]) {
        [subview removeFromSuperview];
    }
    
    // Create chat view controller
    self.chatViewController = [[ChatViewController alloc] initWithConfigs:configs];
    [self setupCommandMenu];
    
    // Set content view and ensure it fills the window
    NSView *contentView = self.chatViewController.view;
    NSRect bounds = self.window.contentView.bounds;
    MWLog(@"MainWindowController: Window bounds: %.0f x %.0f", bounds.size.width, bounds.size.height);
    MWLog(@"MainWindowController: ContentView frame before: (%.0f, %.0f) size (%.0f, %.0f)", 
          contentView.frame.origin.x, contentView.frame.origin.y,
          contentView.frame.size.width, contentView.frame.size.height);
    
    // Update contentView frame to match window (origin at 0,0)
    contentView.frame = NSMakeRect(0, 0, bounds.size.width, bounds.size.height);
    contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    contentView.wantsLayer = YES;
    
    [self.window.contentView addSubview:contentView];
    MWLog(@"MainWindowController: Added contentView with %lu subviews", (unsigned long)contentView.subviews.count);
    MWLog(@"MainWindowController: ContentView frame after: (%.0f, %.0f) size (%.0f, %.0f)", 
          contentView.frame.origin.x, contentView.frame.origin.y,
          contentView.frame.size.width, contentView.frame.size.height);
    
    // List all subviews for debugging
    for (NSView *subview in contentView.subviews) {
        MWLog(@"MainWindowController: Subview: %@ at (%.1f, %.1f) size (%.1f, %.1f)", 
              NSStringFromClass([subview class]), 
              subview.frame.origin.x, subview.frame.origin.y,
              subview.frame.size.width, subview.frame.size.height);
    }

    [self configureTitleBarButtonsIfNeeded];
    
    // Show main window
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    
    // Force layout update
    [contentView setNeedsLayout:YES];
    [contentView layoutSubtreeIfNeeded];
    [contentView setNeedsDisplay:YES];
    [contentView display];
    
    // Force all subviews to update and ensure input/status fields are on top
    NSView *inputField = nil;
    NSView *statusField = nil;
    
    MWLog(@"MainWindowController: Searching through %lu subviews", (unsigned long)contentView.subviews.count);
    
    // First pass: update all subviews
    for (NSView *subview in contentView.subviews) {
        [subview setNeedsLayout:YES];
        [subview layoutSubtreeIfNeeded];
        [subview setNeedsDisplay:YES];
        [subview display];
    }
    
    // Second pass: find input and status fields
    for (NSView *subview in contentView.subviews) {
        // Find input and status fields by checking their frame positions and class
        if ([subview isKindOfClass:[NSTextField class]]) {
            NSTextField *textField = (NSTextField *)subview;
            CGFloat y = textField.frame.origin.y;
            CGFloat height = textField.frame.size.height;
            CGFloat width = textField.frame.size.width;
            MWLog(@"MainWindowController: Found NSTextField at y=%.1f, height=%.1f, width=%.1f", y, height, width);
            
            // Check if it's input field (y=32, height=32) or status field (y=5, height=22)
            // Also check for negative y values (might be relative to wrong coordinate system)
            // Input field: y around 32, height=32
            // Status field: y around 5, height=22
            if (height >= 30 && height <= 35) {
                // This is likely the input field
                inputField = subview;
                MWLog(@"MainWindowController: Identified as inputField (y=%.1f, height=%.1f)", y, height);
            } else if (height >= 20 && height <= 25) {
                // This is likely the status field
                statusField = subview;
                MWLog(@"MainWindowController: Identified as statusField (y=%.1f, height=%.1f)", y, height);
            }
        }
    }
    
    // Ensure input and status fields are visible by bringing them to front
    // Also fix their frames if they have negative y coordinates
    if (statusField) {
        // Fix frame if y is negative
        if (statusField.frame.origin.y < 0) {
            NSRect frame = statusField.frame;
            frame.origin.y = 5; // Set to correct position from bottom
            statusField.frame = frame;
            MWLog(@"MainWindowController: Fixed statusField frame, new y=%.1f", statusField.frame.origin.y);
        }
        [contentView addSubview:statusField positioned:NSWindowAbove relativeTo:nil];
        MWLog(@"MainWindowController: Brought statusField to front, frame=(%.1f, %.1f, %.1f, %.1f)",
              statusField.frame.origin.x, statusField.frame.origin.y,
              statusField.frame.size.width, statusField.frame.size.height);
    } else {
        MWLog(@"MainWindowController: WARNING - statusField not found!");
    }
    
    if (inputField) {
        // Fix frame if y is negative
        if (inputField.frame.origin.y < 0) {
            NSRect frame = inputField.frame;
            frame.origin.y = 32; // Set to correct position from bottom
            inputField.frame = frame;
            MWLog(@"MainWindowController: Fixed inputField frame, new y=%.1f", inputField.frame.origin.y);
        }
        [contentView addSubview:inputField positioned:NSWindowAbove relativeTo:nil];
        MWLog(@"MainWindowController: Brought inputField to front, frame=(%.1f, %.1f, %.1f, %.1f)",
              inputField.frame.origin.x, inputField.frame.origin.y,
              inputField.frame.size.width, inputField.frame.size.height);
    } else {
        MWLog(@"MainWindowController: WARNING - inputField not found!");
    }
    
    // Force immediate display
    [contentView display];
    [self.window.contentView display];
    
    // Force layout update
    [self.window.contentView setNeedsLayout:YES];
    [self.window.contentView setNeedsDisplay:YES];
    [self.window.contentView layoutSubtreeIfNeeded];
}

- (void)configureTitleBarButtonsIfNeeded {
    if (!self.window || self.titlebarAccessory) {
        return;
    }
    
    NSStackView *stackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stackView.alignment = NSLayoutAttributeCenterY;
    stackView.spacing = 6.0;
    
    self.toggleChannelsButton = [self makeTitleBarButtonWithSymbol:@"sidebar.left"
                                                     fallbackTitle:L(@"titlebar.button.channels", @"Channels")
                                                            action:@selector(toggleChannelListPanel:)];
    self.toggleLogButton = [self makeTitleBarButtonWithSymbol:@"rectangle.split.1x2"
                                                fallbackTitle:L(@"titlebar.button.logs", @"Logs")
                                                       action:@selector(toggleLogPanel:)];
    self.toggleUsersButton = [self makeTitleBarButtonWithSymbol:@"sidebar.right"
                                                  fallbackTitle:L(@"titlebar.button.users", @"Users")
                                                         action:@selector(toggleUserListPanel:)];
    self.settingsButton = [self makeTitleBarButtonWithSymbol:@"gearshape"
                                               fallbackTitle:L(@"titlebar.button.settings", @"Settings")
                                                      action:@selector(openSettings:)];
    
    [stackView addArrangedSubview:self.toggleChannelsButton];
    [stackView addArrangedSubview:self.toggleLogButton];
    [stackView addArrangedSubview:self.toggleUsersButton];
    [stackView addArrangedSubview:self.settingsButton];
    
    NSSize fittingSize = stackView.fittingSize;
    stackView.frame = NSMakeRect(0, 0, fittingSize.width, fittingSize.height);
    
    NSTitlebarAccessoryViewController *accessory = [[NSTitlebarAccessoryViewController alloc] init];
    accessory.view = stackView;
    accessory.layoutAttribute = NSLayoutAttributeRight;
    self.titlebarAccessory = accessory;
    
    [self.window addTitlebarAccessoryViewController:accessory];
    [self updateTitleBarButtonTooltips];
}

- (NSButton *)makeTitleBarButtonWithSymbol:(NSString *)symbol
                            fallbackTitle:(NSString *)fallbackTitle
                                   action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:action];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.controlSize = NSControlSizeSmall;
    
    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:fallbackTitle];
    }
    if (image) {
        button.image = image;
        button.imagePosition = NSImageOnly;
    } else {
        button.title = fallbackTitle ?: @"";
    }
    return button;
}

- (void)updateTitleBarButtonTooltips {
    if (self.toggleChannelsButton) {
        self.toggleChannelsButton.toolTip = L(@"titlebar.button.channels", @"Channels");
    }
    if (self.toggleLogButton) {
        self.toggleLogButton.toolTip = L(@"titlebar.button.logs", @"Logs");
    }
    if (self.toggleUsersButton) {
        self.toggleUsersButton.toolTip = L(@"titlebar.button.users", @"Users");
    }
    if (self.settingsButton) {
        self.settingsButton.toolTip = L(@"titlebar.button.settings", @"Settings");
    }
}

- (void)toggleChannelListPanel:(id)sender {
    if (self.chatViewController && [self.chatViewController respondsToSelector:@selector(toggleChannelListPanel)]) {
        [self.chatViewController toggleChannelListPanel];
    }
}

- (void)toggleLogPanel:(id)sender {
    if (self.chatViewController && [self.chatViewController respondsToSelector:@selector(toggleLogWindow)]) {
        [self.chatViewController toggleLogWindow];
    }
}

- (void)toggleUserListPanel:(id)sender {
    if (self.chatViewController && [self.chatViewController respondsToSelector:@selector(toggleUserListPanel)]) {
        [self.chatViewController toggleUserListPanel];
    }
}

- (void)openSettings:(id)sender {
    if (self.chatViewController && [self.chatViewController respondsToSelector:@selector(openSettings)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.chatViewController performSelector:@selector(openSettings)];
#pragma clang diagnostic pop
    }
}

- (void)updateTitleBarButtonsForFavoritesMode:(BOOL)isFavoritesMode {
    if (!self.toggleChannelsButton || !self.toggleLogButton || !self.toggleUsersButton || !self.settingsButton) {
        return;
    }
    
    // When in favorites mode, only show first (Channels) and fourth (Settings) buttons
    // When in messages mode, show all buttons
    self.toggleChannelsButton.hidden = NO;  // Always show first button
    self.toggleLogButton.hidden = isFavoritesMode;  // Hide second button in favorites mode
    self.toggleUsersButton.hidden = isFavoritesMode;  // Hide third button in favorites mode
    self.settingsButton.hidden = NO;  // Always show fourth button
}

- (void)setupCommandMenu {
    if (!self.chatViewController) {
        return;
    }

    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) {
        mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
        [NSApp setMainMenu:mainMenu];
    }

    NSString *appName = @"i3Chat";
    NSMenuItem *appMenuItem = nil;
    for (NSMenuItem *item in mainMenu.itemArray) {
        if ([item.title isEqualToString:appName]) {
            appMenuItem = item;
            break;
        }
    }

    if (!appMenuItem) {
        appMenuItem = [[NSMenuItem alloc] initWithTitle:appName action:nil keyEquivalent:@""];
        [mainMenu insertItem:appMenuItem atIndex:0];
    }

    NSMenu *appMenu = appMenuItem.submenu;
    if (!appMenu) {
        appMenu = [[NSMenu alloc] initWithTitle:appName];
        appMenuItem.submenu = appMenu;
    } else {
        [appMenu removeAllItems];
    }

    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.about", @"About") action:@selector(showAboutWindow:) keyEquivalent:@""];
    aboutItem.target = self;
    [appMenu addItem:aboutItem];

    NSMenuItem *languageItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.language", @"Language") action:nil keyEquivalent:@""];
    NSMenu *languageMenu = [[NSMenu alloc] initWithTitle:L(@"menu.language", @"Language")];
    languageItem.submenu = languageMenu;

    NSMenuItem *englishItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.language.english", @"English")
                                                         action:@selector(selectLanguageEnglish:)
                                                  keyEquivalent:@""];
    englishItem.target = self;
    englishItem.state = [[[LocalizationManager sharedManager] currentLanguageCode] isEqualToString:@"en"] ? NSControlStateValueOn : NSControlStateValueOff;
    [languageMenu addItem:englishItem];

    NSMenuItem *chineseItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.language.chinese", @"Simplified Chinese")
                                                         action:@selector(selectLanguageChinese:)
                                                  keyEquivalent:@""];
    chineseItem.target = self;
    chineseItem.state = [[[LocalizationManager sharedManager] currentLanguageCode] isEqualToString:@"zh-Hans"] ? NSControlStateValueOn : NSControlStateValueOff;
    [languageMenu addItem:chineseItem];

    [appMenu addItem:languageItem];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSString *quitTitle = [NSString stringWithFormat:L(@"menu.quit.format", @"Quit %@"), appName];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle action:@selector(terminate:) keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quitItem.target = NSApp;
    [appMenu addItem:quitItem];

    // === Servers Menu ===
    NSMenuItem *serversItem = nil;
    NSMutableArray<NSMenuItem *> *serversCandidates = [[NSMutableArray alloc] init];
    NSArray<NSString *> *serversTitles = @[
        @"Servers",
        @"服务",
        L(@"menu.servers", @"Servers")
    ];
    for (NSMenuItem *item in mainMenu.itemArray) {
        if (item.tag == ServersMenuItemTag) {
            serversItem = item;
        } else if ([serversTitles containsObject:item.title ?: @""]) {
            [serversCandidates addObject:item];
        }
    }

    if (!serversItem && serversCandidates.count > 0) {
        serversItem = serversCandidates.firstObject;
        serversItem.tag = ServersMenuItemTag;
    }

    // Remove any extra Servers items to avoid stale titles.
    if (serversCandidates.count > 1) {
        for (NSMenuItem *item in serversCandidates) {
            if (item != serversItem) {
                [mainMenu removeItem:item];
            }
        }
    }

    if (!serversItem) {
        serversItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.servers", @"Servers") action:nil keyEquivalent:@""];
        serversItem.tag = ServersMenuItemTag;
        [mainMenu addItem:serversItem];
    }
    serversItem.title = L(@"menu.servers", @"Servers");
    serversItem.tag = ServersMenuItemTag;

    NSMenu *serversMenu = serversItem.submenu;
    if (!serversMenu) {
        serversMenu = [[NSMenu alloc] initWithTitle:L(@"menu.servers", @"Servers")];
        serversItem.submenu = serversMenu;
    } else {
        [serversMenu removeAllItems];
    }
    serversMenu.title = L(@"menu.servers", @"Servers");

    // Add recent servers section
    NSArray<NSString *> *recentServers = [[ServerHistoryStorage sharedStorage] getServerHistoryWithLimit:10];
    
    NSMenuItem *recentHeader = [[NSMenuItem alloc] initWithTitle:L(@"menu.servers.recent", @"Recent Servers") action:nil keyEquivalent:@""];
    recentHeader.enabled = NO;
    [serversMenu addItem:recentHeader];
    
    if (recentServers.count > 0) {
        for (NSString *server in recentServers) {
            NSMenuItem *serverItem = [[NSMenuItem alloc] initWithTitle:server
                                                                action:@selector(menuConnectToServer:)
                                                         keyEquivalent:@""];
            serverItem.target = self.chatViewController;
            serverItem.representedObject = server;
            [serversMenu addItem:serverItem];
        }
    } else {
        NSMenuItem *noRecentItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.servers.noRecent", @"No Recent Servers") action:nil keyEquivalent:@""];
        noRecentItem.enabled = NO;
        [serversMenu addItem:noRecentItem];
    }
    
    [serversMenu addItem:[NSMenuItem separatorItem]];
    
    // Add recommended servers section
    NSMenuItem *recommendedHeader = [[NSMenuItem alloc] initWithTitle:L(@"menu.servers.recommended", @"Recommended Servers") action:nil keyEquivalent:@""];
    recommendedHeader.enabled = NO;
    [serversMenu addItem:recommendedHeader];
    
    // Recommended IRC servers (including TLS variants for 6697)
    NSArray<NSDictionary<NSString *, NSString *> *> *recommendedServers = @[
        @{@"address": @"irc.libera.chat:6667", @"name": @"Libera.Chat"},
        @{@"address": @"irc.libera.chat:6697", @"name": @"Libera.Chat (TLS)"},
        @{@"address": @"irc.oftc.net:6667", @"name": @"OFTC"},
        @{@"address": @"irc.oftc.net:6697", @"name": @"OFTC (TLS)"},
        @{@"address": @"irc.efnet.org:6667", @"name": @"EFnet"},
        @{@"address": @"irc.undernet.org:6667", @"name": @"Undernet"},
        @{@"address": @"irc.dal.net:6667", @"name": @"DALnet"},
        @{@"address": @"irc.dal.net:6697", @"name": @"DALnet (TLS)"},
        @{@"address": @"irc.quakenet.org:6667", @"name": @"QuakeNet"},
        @{@"address": @"open.ircnet.net:6667", @"name": @"IRCnet"},
        @{@"address": @"irc.rizon.net:6667", @"name": @"Rizon"},
        @{@"address": @"irc.snoonet.org:6667", @"name": @"Snoonet"}
    ];
    
    for (NSDictionary<NSString *, NSString *> *serverInfo in recommendedServers) {
        NSString *address = serverInfo[@"address"];
        NSString *name = serverInfo[@"name"];
        NSString *displayTitle = [NSString stringWithFormat:@"%@ (%@)", name, address];
        NSMenuItem *serverItem = [[NSMenuItem alloc] initWithTitle:displayTitle
                                                            action:@selector(menuConnectToServer:)
                                                     keyEquivalent:@""];
        serverItem.target = self.chatViewController;
        serverItem.representedObject = address;
        [serversMenu addItem:serverItem];
    }

    // === Commands Menu ===
    NSMenuItem *commandsItem = nil;
    NSMutableArray<NSMenuItem *> *commandsCandidates = [[NSMutableArray alloc] init];
    NSArray<NSString *> *commandsTitles = @[
        @"Commands",
        @"命令",
        L(@"menu.commands", @"Commands")
    ];
    for (NSMenuItem *item in mainMenu.itemArray) {
        if (item.tag == CommandsMenuItemTag) {
            commandsItem = item;
        } else if ([commandsTitles containsObject:item.title ?: @""]) {
            [commandsCandidates addObject:item];
        }
    }

    if (!commandsItem && commandsCandidates.count > 0) {
        commandsItem = commandsCandidates.firstObject;
        commandsItem.tag = CommandsMenuItemTag;
    }

    // Remove any extra Commands items to avoid stale titles.
    if (commandsCandidates.count > 1) {
        for (NSMenuItem *item in commandsCandidates) {
            if (item != commandsItem) {
                [mainMenu removeItem:item];
            }
        }
    }

    if (!commandsItem) {
        commandsItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.commands", @"Commands") action:nil keyEquivalent:@""];
        commandsItem.tag = CommandsMenuItemTag;
        [mainMenu addItem:commandsItem];
    }
    commandsItem.title = L(@"menu.commands", @"Commands");
    commandsItem.tag = CommandsMenuItemTag;
    commandsItem.tag = CommandsMenuItemTag;

    NSMenu *commandsMenu = commandsItem.submenu;
    if (!commandsMenu) {
        commandsMenu = [[NSMenu alloc] initWithTitle:L(@"menu.commands", @"Commands")];
        commandsItem.submenu = commandsMenu;
    } else {
        [commandsMenu removeAllItems];
    }
    commandsMenu.title = L(@"menu.commands", @"Commands");

    NSArray<NSDictionary<NSString *, NSString *> *> *items = @[
        @{@"title": L(@"menu.commands.join", @"Join Channel (/join)"), @"action": @"menuJoinChannel:"},
        @{@"title": L(@"menu.commands.part", @"Part Channel (/part)"), @"action": @"menuPartChannel:"},
        @{@"title": L(@"menu.commands.msg", @"Private Message (/msg)"), @"action": @"menuPrivateMessage:"},
        @{@"title": L(@"menu.commands.nick", @"Change Nickname (/nick)"), @"action": @"menuChangeNick:"},
        @{@"title": L(@"menu.commands.server", @"Connect Server (/server)"), @"action": @"menuConnectServer:"},
        @{@"title": L(@"menu.commands.links", @"Server Links (/links)"), @"action": @"menuServerLinks:"},
        @{@"title": L(@"menu.commands.list", @"List Channels (/list)"), @"action": @"menuListChannels:"},
        @{@"title": L(@"menu.commands.raw", @"Raw Command (/raw)"), @"action": @"menuRawCommand:"},
        @{@"title": L(@"menu.commands.help", @"Help (/help)"), @"action": @"menuHelp:"},
        @{@"title": L(@"menu.commands.quit", @"Quit (/quit)"), @"action": @"menuQuit:"}
    ];

    for (NSDictionary<NSString *, NSString *> *itemInfo in items) {
        NSString *title = itemInfo[@"title"] ?: @"";
        NSString *actionName = itemInfo[@"action"] ?: @"";
        SEL action = NSSelectorFromString(actionName);
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
        menuItem.target = self.chatViewController;
        [commandsMenu addItem:menuItem];
    }

    // === Window Menu ===
    NSMenuItem *windowItem = nil;
    NSMutableArray<NSMenuItem *> *windowCandidates = [[NSMutableArray alloc] init];
    NSArray<NSString *> *windowTitles = @[
        @"Window",
        L(@"menu.window", @"Window")
    ];
    for (NSMenuItem *item in mainMenu.itemArray) {
        if (item.tag == WindowMenuItemTag) {
            windowItem = item;
        } else if ([windowTitles containsObject:item.title ?: @""]) {
            [windowCandidates addObject:item];
        }
    }

    if (!windowItem && windowCandidates.count > 0) {
        windowItem = windowCandidates.firstObject;
        windowItem.tag = WindowMenuItemTag;
    }

    if (windowCandidates.count > 1) {
        for (NSMenuItem *item in windowCandidates) {
            if (item != windowItem) {
                [mainMenu removeItem:item];
            }
        }
    }

    if (!windowItem) {
        windowItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.window", @"Window") action:nil keyEquivalent:@""];
        windowItem.tag = WindowMenuItemTag;
        [mainMenu addItem:windowItem];
    }
    windowItem.title = L(@"menu.window", @"Window");
    windowItem.tag = WindowMenuItemTag;

    NSMenu *windowMenu = windowItem.submenu;
    if (!windowMenu) {
        windowMenu = [[NSMenu alloc] initWithTitle:L(@"menu.window", @"Window")];
        windowItem.submenu = windowMenu;
    } else {
        [windowMenu removeAllItems];
    }
    windowMenu.title = L(@"menu.window", @"Window");

    NSMenuItem *showMainWindowItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.window.showMain", @"Show Main Window")
                                                                 action:@selector(showMainWindow:)
                                                          keyEquivalent:@"0"];
    showMainWindowItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    showMainWindowItem.target = self;
    [windowMenu addItem:showMainWindowItem];

    NSMenuItem *minimizeItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.window.minimize", @"Minimize")
                                                           action:@selector(performMiniaturize:)
                                                    keyEquivalent:@"m"];
    minimizeItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    minimizeItem.target = self.window;
    [windowMenu addItem:minimizeItem];

    [NSApp setWindowsMenu:windowMenu];

    NSMenuItem *helpItem = nil;
    NSMutableArray<NSMenuItem *> *helpCandidates = [[NSMutableArray alloc] init];
    NSArray<NSString *> *helpTitles = @[
        @"Help",
        @"帮助",
        L(@"menu.help", @"Help")
    ];
    for (NSMenuItem *item in mainMenu.itemArray) {
        if (item.tag == HelpMenuItemTag) {
            helpItem = item;
        } else if ([helpTitles containsObject:item.title ?: @""]) {
            [helpCandidates addObject:item];
        }
    }

    if (!helpItem && helpCandidates.count > 0) {
        helpItem = helpCandidates.firstObject;
        helpItem.tag = HelpMenuItemTag;
    }

    if (helpCandidates.count > 1) {
        for (NSMenuItem *item in helpCandidates) {
            if (item != helpItem) {
                [mainMenu removeItem:item];
            }
        }
    }

    if (!helpItem) {
        helpItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.help", @"Help") action:nil keyEquivalent:@""];
        helpItem.tag = HelpMenuItemTag;
        [mainMenu addItem:helpItem];
    }
    helpItem.title = L(@"menu.help", @"Help");
    helpItem.tag = HelpMenuItemTag;

    NSMenu *helpMenu = helpItem.submenu;
    if (!helpMenu) {
        helpMenu = [[NSMenu alloc] initWithTitle:L(@"menu.help", @"Help")];
        helpItem.submenu = helpMenu;
    } else {
        [helpMenu removeAllItems];
    }
    helpMenu.title = L(@"menu.help", @"Help");

    NSMenuItem *developerModeItem = [[NSMenuItem alloc] initWithTitle:L(@"menu.help.developerMode", @"Developer Mode")
                                                                action:@selector(toggleLogWindow)
                                                         keyEquivalent:@""];
    developerModeItem.target = self.chatViewController;
    [helpMenu addItem:developerModeItem];

    // Force menu bar refresh to reflect updated titles.
    [NSApp setMainMenu:mainMenu];
}

- (void)selectLanguageEnglish:(id)sender {
    [[LocalizationManager sharedManager] setLanguageCode:@"en"];
}

- (void)selectLanguageChinese:(id)sender {
    [[LocalizationManager sharedManager] setLanguageCode:@"zh-Hans"];
}

- (void)handleLocalizationDidChange:(NSNotification *)notification {
    if (self.window) {
        [self.window setTitle:L(@"main.window.title", @"i3Chat - IRC Client")];
    }
    if (self.loginWindowController) {
        [self.loginWindowController applyLocalization];
    }
    if (self.chatViewController) {
        [self.chatViewController applyLocalization];
    }
    [self setupCommandMenu];
    [self updateTitleBarButtonTooltips];
}

- (void)handleServerHistoryDidUpdate:(NSNotification *)notification {
    // Refresh the servers menu when server history is updated
    if (self.chatViewController) {
        [self setupCommandMenu];
    }
}

- (void)showAboutWindow:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"i3Chat";
    
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.1.0";
    NSString *copyright = L(@"app.about.copyright", @"Copyright © 2025-2028");
    
    alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@", version, copyright];
    
    NSImage *appIcon = [NSApp applicationIconImage];
    if (appIcon) {
        alert.icon = appIcon;
    }
    
    // Add OK button with localized text
    [alert addButtonWithTitle:L(@"app.about.button.ok", @"OK")];
    
    // Make the button smaller by accessing the button and adjusting its size
    NSArray *buttons = alert.buttons;
    if (buttons.count > 0) {
        NSButton *okButton = buttons[0];
        okButton.controlSize = NSControlSizeSmall;
        // Adjust frame to make it smaller
        NSRect frame = okButton.frame;
        frame.size.width = 60;
        okButton.frame = frame;
    }
    
    [alert runModal];
}

- (void)showMainWindow:(id)sender {
    if (!self.window) {
        return;
    }
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
