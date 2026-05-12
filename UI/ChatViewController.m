//
//  ChatViewController.m
//  i3Chat
//
//  Core implementation of ChatViewController
//  Additional functionality is provided via categories:
//  - ChatViewController+UI.m       - UI setup and layout
//  - ChatViewController+Channel.m  - Channel/server management
//  - ChatViewController+Message.m  - Message handling and formatting
//  - ChatViewController+IRC.m      - IRCClientDelegate implementation
//  - ChatViewController+DataSource.m - TableView/OutlineView data sources
//  - ChatViewController+Menu.m     - Menu handling
//  - ChatViewController+Input.m    - Input and command processing
//  - ChatViewController+Favorites.m - Favorites functionality
//

#import "ChatViewController+Private.h"

// MARK: - Constants
// Note: Storage-related constants are defined in StorageConstants.m
// These are channel-specific constants used by ChatViewController

NSString * const ChannelKeySeparator = @"||";
NSString * const ChannelGroupInfoGroupKey = @"groupName";
NSString * const ChannelGroupInfoChannelKey = @"channelKey";

// MARK: - ChannelTreeItem Implementation

@implementation ChannelTreeItem
@end

// Forward declaration for methods implemented in categories
@interface ChatViewController (ForwardDeclarations)
- (BOOL)handleChannelListNavigation:(NSEvent *)event;
@end

// MARK: - ChatView Implementation

@implementation ChatView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    // Handle Ctrl+O to toggle log window
    if ((event.modifierFlags & NSEventModifierFlagControl) == NSEventModifierFlagControl) {
        if (event.keyCode == 31) { // 'O' key
            if (self.chatViewController && [self.chatViewController respondsToSelector:@selector(toggleLogWindow)]) {
                [self.chatViewController toggleLogWindow];
                return YES;
            }
        }
    }
    
    // Call super for other key events
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    // Also handle in keyDown as fallback
    if ((event.modifierFlags & NSEventModifierFlagControl) == NSEventModifierFlagControl) {
        if (event.keyCode == 31) { // 'O' key
            if (self.chatViewController && [self.chatViewController respondsToSelector:@selector(toggleLogWindow)]) {
                [self.chatViewController toggleLogWindow];
                return;
            }
        }
    }
    
    // Handle arrow keys for channel list navigation
    if (self.chatViewController && [self.chatViewController respondsToSelector:@selector(handleChannelListNavigation:)]) {
        if ([self.chatViewController handleChannelListNavigation:event]) {
            return;
        }
    }
    
    [super keyDown:event];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if ([self.chatViewController respondsToSelector:@selector(applyAdaptiveLayerColors)]) {
        [self.chatViewController applyAdaptiveLayerColors];
    }
}

@end

// MARK: - ChatTextView Implementation

@implementation ChatTextView

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (self.chatViewController) {
        NSMenu *menu = [self.chatViewController chatMenuForEvent:event inTextView:self];
        if (menu) {
            return menu;
        }
    }
    return [super menuForEvent:event];
}

- (void)mouseDown:(NSEvent *)event {
    // Store click location for detecting single vs double click
    NSPoint clickPoint = [self convertPoint:event.locationInWindow fromView:nil];
    
    if (event.clickCount == 1) {
        // Single click - check if clicked on a nickname
        if (self.chatViewController) {
            NSString *nickname = [self.chatViewController extractNicknameAtPoint:clickPoint inTextView:self];
            if (nickname) {
                // Toggle highlight for this nickname (add or remove from highlighted set)
                [self.chatViewController toggleHighlightForNickname:nickname];
                return;
            } else {
                // Clicked on empty area or non-nickname text, clear all highlights
                [self.chatViewController clearAllNicknameHighlights];
            }
        }
    } else if (event.clickCount == 2) {
        // Double click - check if clicked on a nickname to open private chat
        if (self.chatViewController) {
            NSString *nickname = [self.chatViewController extractNicknameAtPoint:clickPoint inTextView:self];
            if (nickname) {
                [self.chatViewController openPrivateChatWithNickname:nickname];
                return;
            }
        }
    }
    
    [super mouseDown:event];
}

// Update cursor when hovering over clickable nicknames
- (void)mouseMoved:(NSEvent *)event {
    // Skip processing only during active scroll to reduce CPU usage
    if (self.chatViewController) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - self.chatViewController.lastScrollEventTime < 0.2) {
            return;
        }
    }
    
    // Throttle mouse move handling to reduce CPU usage
    static NSTimeInterval lastMouseMoveTime = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - lastMouseMoveTime < 0.1) { // 100ms throttle
        return;
    }
    lastMouseMoveTime = now;
    
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    
    if (self.chatViewController) {
        NSString *nickname = [self.chatViewController extractNicknameAtPoint:point inTextView:self];
        if (nickname) {
            [[NSCursor pointingHandCursor] set];
            return;
        }
    }
    
    [[NSCursor arrowCursor] set];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    
    // Only update tracking areas if we don't already have one
    // This avoids unnecessary work during scrolling
    if (self.trackingAreas.count > 0) {
        return;
    }
    
    // Add a tracking area for mouse movement
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                               options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
                                                                 owner:self
                                                              userInfo:nil];
    [self addTrackingArea:trackingArea];
}

@end

// MARK: - FavoritesTextView Implementation

@implementation FavoritesTextView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    if (self.chatViewController) {
        NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        if ((flags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand) {
            NSString *chars = event.charactersIgnoringModifiers.lowercaseString ?: @"";
            if ([chars isEqualToString:@"c"]) {
                [self.chatViewController handleFavoritesCopyShortcutFromTextView:self];
                return;
            }
            if ([chars isEqualToString:@"o"]) {
                [self.chatViewController handleFavoritesOpenShortcutFromTextView:self];
                return;
            }
        }
    }
    [super keyDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    // Return custom favorites menu instead of default text menu
    if (self.chatViewController) {
        // Find the row for this text view
        NSTableView *tableView = self.chatViewController.favoritesTableView;
        if (tableView) {
            NSPoint pointInTable = [tableView convertPoint:event.locationInWindow fromView:nil];
            NSInteger row = [tableView rowAtPoint:pointInTable];
            if (row >= 0) {
                // Select the row
                [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
                
                // Build and return custom menu
                NSMenu *menu = [[NSMenu alloc] initWithTitle:@"FavoritesContextMenu"];
                
                NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.copy", @"Copy")
                                                                  action:@selector(handleFavoritesCopy:)
                                                           keyEquivalent:@""];
                copyItem.target = self.chatViewController;
                copyItem.representedObject = @(row);
                [menu addItem:copyItem];
                
                NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.delete", @"Delete")
                                                                    action:@selector(handleFavoritesDelete:)
                                                             keyEquivalent:@""];
                deleteItem.target = self.chatViewController;
                deleteItem.representedObject = @(row);
                [menu addItem:deleteItem];
                
                return menu;
            }
        }
    }
    return nil; // Return nil to suppress default menu
}

@end

// MARK: - ChatViewController Implementation

@implementation ChatViewController

#pragma mark - Initialization

- (instancetype)initWithConfig:(IRCConfig *)config {
    return [self initWithConfigs:config ? @[config] : @[]];
}

- (instancetype)initWithConfigs:(NSArray<IRCConfig *> *)configs {
    self = [super init];
    if (self) {
        _configs = configs ?: @[];
        _serverConfigs = [[NSMutableDictionary alloc] init];
        _ircClients = [[NSMutableDictionary alloc] init];
        _channels = [[NSMutableDictionary alloc] init];
        _serverOrder = [[NSMutableArray alloc] init];
        _serverChannelOrder = [[NSMutableDictionary alloc] init];
        _serverItems = [[NSMutableDictionary alloc] init];
        _channelItems = [[NSMutableDictionary alloc] init];
        _joinedChannels = [[NSMutableDictionary alloc] init];
        _disconnectedServers = [[NSMutableSet alloc] init];
        _autoJoinChannels = [[NSMutableDictionary alloc] init];
        _isLoadingPersistedChannels = NO;
        _currentServer = _configs.count > 0 ? _configs[0].server : @"";
        _inputHistory = [[NSMutableArray alloc] init];
        _inputHistoryIndex = -1;
        
        // Load settings from SQLite database
        MessageStorage *storage = [MessageStorage sharedStorage];
        NSString *showLogValue = [storage getSettingForKey:kSettingShowLogWindowOnStartup];
        NSLog(@"[Settings] ChatViewController init - showLogValue from DB: '%@'", showLogValue);
        _logWindowVisible = (showLogValue == nil) ? NO : [showLogValue boolValue];
        NSLog(@"[Settings] ChatViewController init - _logWindowVisible set to: %@", _logWindowVisible ? @"YES" : @"NO");
        
        NSString *showColorsValue = [storage getSettingForKey:kSettingShowChannelColors];
        NSLog(@"[Settings] ChatViewController init - showColorsValue from DB: '%@'", showColorsValue);
        _showChannelColors = (showColorsValue == nil) ? YES : [showColorsValue boolValue];
        
        NSString *maxMessagesValue = [storage getSettingForKey:kSettingMaxMessagesPerChannel];
        _maxMessagesPerChannel = (maxMessagesValue == nil) ? kDefaultMaxMessagesPerChannel : [maxMessagesValue integerValue];
        NSLog(@"[Settings] ChatViewController init - maxMessagesPerChannel: %ld", (long)_maxMessagesPerChannel);

        NSString *lineSpacingValue = [storage getSettingForKey:kSettingMessageLineSpacing];
        _messageLineSpacing = (lineSpacingValue == nil) ? kDefaultMessageLineSpacing : [lineSpacingValue floatValue];
        if (_messageLineSpacing < 0) {
            _messageLineSpacing = 0;
        }
        NSLog(@"[Settings] ChatViewController init - messageLineSpacing: %.2f", _messageLineSpacing);
        
        _userIsScrolling = NO;
        _userPinnedToBottom = YES;
        
        _channelListVisible = YES;
        _userListVisible = YES;
        _lastLeftPanelWidth = 220.0;
        _lastRightPanelWidth = 220.0;
        _savedChannelPanelWidth = 220.0;
        _channelListMode = ChannelListModeChannels;
        _leftSidebarMode = SidebarModeMessages;
        _recentChannelKeys = [[NSMutableArray alloc] init];
        _recentItems = [[NSMutableDictionary alloc] init];
        _customGroupOrder = @[];
        _customGroupChannels = @{};
        _groupItems = [[NSMutableDictionary alloc] init];
        _groupChannelItems = [[NSMutableDictionary alloc] init];
        _favoriteItems = [[[MessageStorage sharedStorage] loadAllFavorites] mutableCopy] ?: [[NSMutableArray alloc] init];
        _currentFavoritesFilter = FavoritesFilterAll;
        _cachedAttributedMessages = [[NSMutableDictionary alloc] init];
        _lastRenderedMessageCount = [[NSMutableDictionary alloc] init];
        _previousChannelListSelectedRow = -1;
        _previousUserListSelectedRow = -1;
        _isUpdatingChannelSelection = NO;
        _channelListWindowControllers = [[NSMutableDictionary alloc] init];
        _highlightedNicknames = [[NSMutableSet alloc] init];
        _pendingDisplayChannels = [[NSMutableSet alloc] init];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyLocalization)
                                                     name:LocalizationDidChangeNotification
                                                   object:nil];
        
        // Listen for window and first responder changes to update channel list text colors
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleWindowOrFocusChange:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleWindowOrFocusChange:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];
        
        // Listen for outline view focus changes
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleOutlineViewFocusChange:)
                                                     name:@"FocusableOutlineViewDidBecomeFirstResponder"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleOutlineViewFocusChange:)
                                                     name:@"FocusableOutlineViewDidResignFirstResponder"
                                                   object:nil];
        
        for (IRCConfig *config in _configs) {
            if (config.server.length > 0) {
                _serverConfigs[config.server] = config;
            }
        }
        
        // Setup UI - must be on main thread
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUI];
            });
        } else {
            [self setupUI];
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Cancel display timer
    if (self.displayTimer) {
        dispatch_source_cancel(self.displayTimer);
        self.displayTimer = nil;
    }
    
    // Disconnect all IRC clients
    for (NSString *server in self.ircClients) {
        IRCClient *client = self.ircClients[server];
        [client disconnect];
    }
}

#pragma mark - View Lifecycle

- (void)viewWillLayout {
    [super viewWillLayout];
    
    if (!self.mainSplitView) {
        return;
    }
    
    NSRect viewBounds = self.view.bounds;
    CGFloat windowWidth = viewBounds.size.width;
    CGFloat windowHeight = viewBounds.size.height;
    CGFloat inputBarHeight = 70;
    CGFloat contentHeight = windowHeight - inputBarHeight;
    
    // mainSplitView fills entire window (original behavior)
    self.mainSplitView.frame = NSMakeRect(0, 0, windowWidth, windowHeight);
    [self.mainSplitView adjustSubviews];
    
    // bottomBar positioned at bottom, x starts from leftWidth (set by updateInputLayoutForWidth)
    // It only covers middle and right areas, not the left channelPanel area
    if (self.bottomBar) {
        NSRect bottomFrame = self.bottomBar.frame;
        bottomFrame.origin.y = 0;
        bottomFrame.size.height = inputBarHeight;
        self.bottomBar.frame = bottomFrame;
    }
    
    // Update input layout - this sets bottomBar.origin.x = leftWidth
    [self updateInputLayoutForWidth:windowWidth];
    
    // Update side panels
    [self updateSidePanelLayouts];
    [self updateChannelPanelLayout];
}

#pragma mark - Panel Toggle

- (void)toggleLogWindow {
    self.logWindowVisible = !self.logWindowVisible;
    
    NSView *logView = self.logContainer ?: self.logScrollView;
    if (!self.middleSplitView || !logView) {
        return;
    }
    
            logView.hidden = !self.logWindowVisible;
            
            CGFloat contentHeight = self.middleSplitView ? self.middleSplitView.bounds.size.height : (self.view.bounds.size.height - 70);
            if (!self.logWindowVisible) {
                [self.middleSplitView setPosition:contentHeight ofDividerAtIndex:0];
                if (self.logTextView) {
                    [self.logTextView.textStorage.mutableString setString:@""];
                }
                if (logView) {
                    logView.hidden = YES;
                    logView.frame = NSMakeRect(0, 0, self.middleSplitView.bounds.size.width, 0);
                }
            } else {
                if (logView) {
                    logView.hidden = NO;
                }
                [self.middleSplitView setPosition:contentHeight * 0.75 ofDividerAtIndex:0];
            }
            [self.middleSplitView adjustSubviews];
            logView.hidden = !self.logWindowVisible;
    
    // Force updates
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (self.middleSplitView && logView) {
        logView.hidden = !self.logWindowVisible;
        CGFloat contentHeight = self.middleSplitView ? self.middleSplitView.bounds.size.height : (self.view.bounds.size.height - 70);
        if (!self.logWindowVisible) {
            [self.middleSplitView setPosition:contentHeight ofDividerAtIndex:0];
            if (self.logTextView) {
                [self.logTextView.textStorage.mutableString setString:@""];
            }
            if (logView) {
                logView.hidden = YES;
                logView.frame = NSMakeRect(0, 0, self.middleSplitView.bounds.size.width, 0);
            }
        } else {
            if (logView) {
                logView.hidden = NO;
            }
            [self.middleSplitView setPosition:contentHeight * 0.75 ofDividerAtIndex:0];
        }
        [self.middleSplitView adjustSubviews];
            logView.hidden = !self.logWindowVisible;
    }
    });
    
    CVLog(@"Log window toggled: %@", self.logWindowVisible ? @"visible" : @"hidden");
}

- (void)toggleChannelListPanel {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self toggleChannelListPanel];
        });
        return;
    }
    
    if (!self.mainSplitView || self.mainSplitView.subviews.count < 3) {
        return;
    }
    
    NSView *leftPanel = self.mainSplitView.subviews[0];
    NSView *rightPanel = self.mainSplitView.subviews[2];
    CGFloat totalWidth = self.mainSplitView.bounds.size.width;
    
    if (self.channelListVisible) {
        // Save widths before hiding
        self.lastLeftPanelWidth = MAX(150.0, leftPanel.frame.size.width);
        // Save right panel width to prevent it from expanding
        if (!rightPanel.hidden) {
            CGFloat currentRightWidth = rightPanel.frame.size.width;
            if (self.lastRightPanelWidth <= 0.0 || ABS(currentRightWidth - self.lastRightPanelWidth) > 1.0) {
                self.lastRightPanelWidth = MAX(150.0, currentRightWidth);
            }
        }
        
        // First set divider positions to prevent right panel expansion
        if (!rightPanel.hidden && self.lastRightPanelWidth > 0.0) {
            [self.mainSplitView setPosition:(totalWidth - self.lastRightPanelWidth) ofDividerAtIndex:1];
        }
        // Then set left panel divider position to 0 to collapse it
        [self.mainSplitView setPosition:0 ofDividerAtIndex:0];
        
        // Then hide the panel and its subviews
        leftPanel.hidden = YES;
        if (self.channelBottomBar) {
            self.channelBottomBar.hidden = YES;
        }
        if (self.channelPanel) {
            self.channelPanel.hidden = YES;
        }
    } else {
        // First show the panel
        leftPanel.hidden = NO;
        if (self.channelPanel) {
            self.channelPanel.hidden = NO;
        }
        // Then set divider position to restore width
        CGFloat rightWidth = rightPanel.hidden ? 0.0 : rightPanel.frame.size.width;
        CGFloat restoredWidth = self.lastLeftPanelWidth > 0.0 ? self.lastLeftPanelWidth : 220.0;
        CGFloat maxLeftWidth = totalWidth - rightWidth - 300.0;
        maxLeftWidth = MAX(maxLeftWidth, 150.0);
        restoredWidth = MIN(restoredWidth, maxLeftWidth);
        [self.mainSplitView setPosition:restoredWidth ofDividerAtIndex:0];
        if (self.channelBottomBar) {
            self.channelBottomBar.hidden = (self.leftSidebarMode != SidebarModeMessages);
            NSRect frame = self.channelBottomBar.frame;
            frame.origin.y = 0;
            frame.size.height = 40.0;
            self.channelBottomBar.frame = frame;
        }
    }
    
    self.channelListVisible = !self.channelListVisible;
    [self.mainSplitView adjustSubviews];
    
    // Ensure hidden state is maintained after adjustSubviews
    if (!self.channelListVisible) {
        leftPanel.hidden = YES;
        if (self.channelPanel) {
            self.channelPanel.hidden = YES;
        }
        if (self.channelBottomBar) {
            self.channelBottomBar.hidden = YES;
        }
        // Ensure right panel width is maintained after adjustSubviews
        if (!rightPanel.hidden && self.lastRightPanelWidth > 0.0) {
            CGFloat currentTotalWidth = self.mainSplitView.bounds.size.width;
            CGFloat expectedRightPosition = currentTotalWidth - self.lastRightPanelWidth;
            CGFloat currentRightPosition = self.mainSplitView.subviews.count > 2 ? 
                (currentTotalWidth - rightPanel.frame.size.width) : expectedRightPosition;
            if (ABS(currentRightPosition - expectedRightPosition) > 1.0) {
                [self.mainSplitView setPosition:expectedRightPosition ofDividerAtIndex:1];
                [self.mainSplitView adjustSubviews];
            }
        }
    }
    [self updateInputLayoutForWidth:self.view.bounds.size.width];
    [self updateChannelPanelLayout];
    [self updateSidePanelLayouts];
    
    CVLog(@"Channel list panel toggled: %@", self.channelListVisible ? @"visible" : @"hidden");
}

- (void)toggleUserListPanel {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self toggleUserListPanel];
        });
        return;
    }
    
    if (self.leftSidebarMode == SidebarModeFavorites) {
        self.userListWasVisibleBeforeFavorites = !self.userListWasVisibleBeforeFavorites;
        CVLog(@"User list toggle stored for when returning to messages mode: %@", 
              self.userListWasVisibleBeforeFavorites ? @"visible" : @"hidden");
        return;
    }
    
    if (!self.mainSplitView || self.mainSplitView.subviews.count < 3) {
        return;
    }
    
    NSView *leftPanel = self.mainSplitView.subviews[0];
    NSView *rightPanel = self.mainSplitView.subviews[2];
    CGFloat totalWidth = self.mainSplitView.bounds.size.width;
    
    if (self.userListVisible) {
        // Save widths before hiding
        self.lastRightPanelWidth = MAX(150.0, rightPanel.frame.size.width);
        // Save left panel width to prevent it from expanding
        if (!leftPanel.hidden) {
            CGFloat currentLeftWidth = leftPanel.frame.size.width;
            if (self.lastLeftPanelWidth <= 0.0 || ABS(currentLeftWidth - self.lastLeftPanelWidth) > 1.0) {
                self.lastLeftPanelWidth = MAX(150.0, currentLeftWidth);
            }
        }
        
        // First set left panel divider position to maintain its width
        if (!leftPanel.hidden && self.lastLeftPanelWidth > 0.0) {
            [self.mainSplitView setPosition:self.lastLeftPanelWidth ofDividerAtIndex:0];
        }
        // Then set right panel divider position to hide it
        [self.mainSplitView setPosition:totalWidth ofDividerAtIndex:1];
        
        rightPanel.hidden = YES;
    } else {
        rightPanel.hidden = NO;
        CGFloat leftWidth = leftPanel.hidden ? 0.0 : leftPanel.frame.size.width;
        CGFloat restoredWidth = self.lastRightPanelWidth > 0.0 ? self.lastRightPanelWidth : 220.0;
        CGFloat maxRightWidth = totalWidth - leftWidth - 300.0;
        maxRightWidth = MAX(maxRightWidth, 150.0);
        restoredWidth = MIN(restoredWidth, maxRightWidth);
        [self.mainSplitView setPosition:(totalWidth - restoredWidth) ofDividerAtIndex:1];
    }
    
    self.userListVisible = !self.userListVisible;
    [self.mainSplitView adjustSubviews];
    [self updateInputLayoutForWidth:self.view.bounds.size.width];
    [self updateSidePanelLayouts];
    
    // Ensure left panel width is maintained after adjustSubviews
    if (!self.userListVisible) {
        // Right panel is hidden, ensure left panel width is maintained
        if (!leftPanel.hidden && self.lastLeftPanelWidth > 0.0) {
            CGFloat currentLeftWidth = leftPanel.frame.size.width;
            // Only adjust if width has drifted significantly
            if (ABS(currentLeftWidth - self.lastLeftPanelWidth) > 1.0) {
                [self.mainSplitView setPosition:self.lastLeftPanelWidth ofDividerAtIndex:0];
                [self.mainSplitView adjustSubviews];
            }
        }
    }
    
    CVLog(@"User list panel toggled: %@", self.userListVisible ? @"visible" : @"hidden");
}

#pragma mark - Localization

- (void)applyLocalization {
    // Ensure localization updates happen on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyLocalization];
        });
        return;
    }
    // Update status field
        [self updateStatus];
    
    // Update input field placeholder
    if (self.inputField) {
        self.inputField.placeholderString = L(@"chat.input.placeholder", @"Type message or /command...");
        }
        
        // Update user count label
        if (self.userCountLabel) {
        NSArray<NSString *> *users = [self displayedUsersForCurrentChannel];
        self.userCountLabel.stringValue = [NSString stringWithFormat:L(@"chat.userCount.format", @"Users: %ld"), (long)users.count];
    }
    
    // Update user search field
    if (self.userSearchField) {
        self.userSearchField.placeholderString = L(@"chat.userSearch.placeholder", @"Search users");
    }
    
    // Update favorites title
    if (self.favoritesTitleLabel) {
        self.favoritesTitleLabel.stringValue = L(@"chat.favorites.title", @"Favorites");
    }
    
    // Update favorites panel title
    if (self.favoritesPanelTitleLabel) {
        self.favoritesPanelTitleLabel.stringValue = L(@"chat.favorites.title", @"Favorites");
    }
    
    // Update favorites empty state
    if (self.favoritesEmptyLabel) {
        self.favoritesEmptyLabel.stringValue = L(@"chat.favorites.empty", @"No favorites yet.\nSelect text and right-click to add.");
    }
    
    // Update channel list mode button tooltips
    [self updateChannelListModeButtonTooltips];
    
    // Update sidebar button tooltips
    [self updateSidebarButtonTooltips];
    
    // Update favorites button titles and states (including text colors)
    [self updateFavoritesButtonTitles];
    [self updateFavoritesButtonStates];
    
    // Reload tables to update localized content
    self.isReloadingChannelList = YES;
    [self.channelListView reloadData];
    self.isReloadingChannelList = NO;
    [self.userListView reloadData];
    [self.favoritesTableView reloadData];
    
    CVLog(@"Localization applied to ChatViewController");
}

#pragma mark - Window Title

- (void)updateWindowTitleForChatName:(NSString *)chatName {
    NSWindow *window = self.view.window;
    if (!window) {
        return;
    }

    NSString *appName = L(@"app.name", @"i3Chat");
    
    // Get current nick and server info
    NSString *nick = nil;
    NSString *server = self.currentServer;
    
    if (server.length > 0) {
        IRCConfig *config = [self configForServer:server];
        if (config) {
            nick = config.nick;
        }
    }
    
    // Build title: "i3chat - nick on server #channel"
    if (nick.length > 0 && server.length > 0 && chatName.length > 0) {
        window.title = [NSString stringWithFormat:@"%@ - %@ on %@ %@", appName, nick, server, chatName];
    } else if (nick.length > 0 && server.length > 0) {
        window.title = [NSString stringWithFormat:@"%@ - %@ on %@", appName, nick, server];
    } else if (chatName.length > 0) {
        window.title = [NSString stringWithFormat:@"%@ - %@", appName, chatName];
    } else {
        window.title = appName;
    }
}

#pragma mark - Focus Handling

- (void)handleWindowOrFocusChange:(NSNotification *)notification {
    // Only handle notifications for our window
    if (notification.object != self.view.window) {
        return;
    }
    
    // Update channel list text colors when window or focus changes
    // Use a small delay to ensure first responder has been updated
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateChannelListTextColors];
    });
}

- (void)handleOutlineViewFocusChange:(NSNotification *)notification {
    // Only handle notifications for our channel list view
    if (notification.object != self.channelListView) {
        return;
    }
    
    // Update channel list text colors when outline view focus changes
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateChannelListTextColors];
    });
}

@end
