//
//  ChannelListWindowController.m
//  i3Chat
//

#import "ChannelListWindowController.h"
#import "DebugLog.h"
#import "LocalizationManager.h"

@interface ChannelListWindowController () <NSWindowDelegate>

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTableColumn *channelColumn;
@property (nonatomic, strong) NSTableColumn *usersColumn;
@property (nonatomic, strong) NSTableColumn *topicColumn;
@property (nonatomic, strong) NSButton *joinButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, assign) NSInteger pendingUpdateCount;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, assign) NSInteger incrementalUpdateThreshold; // Threshold for incremental table refresh
@property (nonatomic, strong) NSArray<NSColor *> *ircColorTable;
@property (nonatomic, strong) NSCache *attributedTopicCache; // Cache for parsed topic attributed strings

// Sorting state
@property (nonatomic, copy) NSString *currentSortKey; // "channel", "userCount", or "topic"
@property (nonatomic, assign) BOOL sortAscending;

// Search/Filter state
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *filteredChannels;

// Buttons
@property (nonatomic, strong) NSButton *updateListButton;

// Private method declarations
- (NSString *)stripIRCFormattingCodes:(NSString *)string;
- (NSString *)windowTitleWithBase:(NSString *)baseTitle;
- (void)updateFilteredChannels;
- (NSArray<NSDictionary<NSString *, id> *> *)displayedChannels;

@end

@implementation ChannelListWindowController

#pragma mark - Helper Methods

// Helper method to generate window title with server address
- (NSString *)windowTitleWithBase:(NSString *)baseTitle {
    if (self.serverAddress.length > 0) {
        return [NSString stringWithFormat:@"%@ - %@", baseTitle, self.serverAddress];
    }
    return baseTitle;
}

#pragma mark - Initialization

- (instancetype)init {
    return [self initWithServerAddress:nil];
}

- (instancetype)initWithServerAddress:(NSString *)serverAddress {
    _channels = [[NSMutableArray alloc] init];
    _pendingUpdateCount = 0;
    _incrementalUpdateThreshold = 50; // Refresh table every 50 channels
    _attributedTopicCache = [[NSCache alloc] init];
    _attributedTopicCache.countLimit = 1000; // Cache up to 1000 parsed topics
    _serverAddress = [serverAddress copy];
    
    // Initialize sorting state - default sort by user count descending
    _currentSortKey = @"userCount";
    _sortAscending = NO;
    
    // Initialize IRC color table
    _ircColorTable = [self buildIRCColorTable];
    
    // Create window first
    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSRect windowRect = NSMakeRect(
        (screenRect.size.width - 800) / 2,
        (screenRect.size.height - 500) / 2,
        800,
        500
    );
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    // Set window title (will be updated with server address after self is initialized)
    [window setTitle:L(@"channelList.window.title", @"Channel List")];
    [window setMinSize:NSMakeSize(600, 400)];
    [window setDelegate:self];
    
    // Set window level to floating so it stays above main window
    // NSFloatingWindowLevel keeps the window above normal windows but below modal windows
    [window setLevel:NSFloatingWindowLevel];
    
    // Allow the window to be key (can receive keyboard input)
    [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    
    // Don't hide when app loses focus (keeps window visible)
    [window setHidesOnDeactivate:NO];
    
    // Initialize NSWindowController with the window
    self = [super initWithWindow:window];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyLocalization)
                                                     name:LocalizationDidChangeNotification
                                                   object:nil];
        
        // Create main view
        NSView *contentView = window.contentView;
        contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        
        // Create scroll view for table
        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, 780, 420)];
        scrollView.hasVerticalScroller = YES;
        scrollView.hasHorizontalScroller = YES;
        scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scrollView.borderType = NSBezelBorder;
        [contentView addSubview:scrollView];
        
        // Create table view (view-based for attributed string support)
        self.tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 780, 420)];
        self.tableView.delegate = self;
        self.tableView.dataSource = self;
        self.tableView.allowsMultipleSelection = NO;
        self.tableView.usesAlternatingRowBackgroundColors = YES;
        self.tableView.doubleAction = @selector(doubleClickAction:);
        self.tableView.target = self;
        // Use static contents = NO to ensure view-based table mode
        self.tableView.usesStaticContents = NO;
        
        // Channel column - sortable by channel name
        self.channelColumn = [[NSTableColumn alloc] initWithIdentifier:@"Channel"];
        self.channelColumn.title = L(@"channelList.column.channel", @"Channel");
        self.channelColumn.width = 200;
        self.channelColumn.minWidth = 150;
        self.channelColumn.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:@"channel" ascending:YES selector:@selector(caseInsensitiveCompare:)];
        [self.tableView addTableColumn:self.channelColumn];
        
        // Users column - sortable by user count (default sort column)
        self.usersColumn = [[NSTableColumn alloc] initWithIdentifier:@"Users"];
        self.usersColumn.title = L(@"channelList.column.users", @"Users");
        self.usersColumn.width = 100;
        self.usersColumn.minWidth = 80;
        self.usersColumn.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:@"userCount" ascending:NO selector:@selector(compare:)];
        [self.tableView addTableColumn:self.usersColumn];
        
        // Topic column - sortable by topic, supports IRC color formatting
        self.topicColumn = [[NSTableColumn alloc] initWithIdentifier:@"Topic"];
        self.topicColumn.title = L(@"channelList.column.topic", @"Topic");
        self.topicColumn.width = 480;
        self.topicColumn.minWidth = 200;
        self.topicColumn.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:@"topic" ascending:YES selector:@selector(caseInsensitiveCompare:)];
        [self.tableView addTableColumn:self.topicColumn];
        
        scrollView.documentView = self.tableView;
        
        // Set default row height (will be overridden by heightOfRow delegate)
        self.tableView.rowHeight = 20;
        
        // Set default sort descriptor (sort by user count descending)
        NSSortDescriptor *defaultSort = [NSSortDescriptor sortDescriptorWithKey:@"userCount" ascending:NO selector:@selector(compare:)];
        self.tableView.sortDescriptors = @[defaultSort];
        
        // Create search field at the top
        self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(10, 478, 780, 22)];
        self.searchField.placeholderString = L(@"channelList.search.placeholder", @"Search channels...");
        self.searchField.target = self;
        self.searchField.action = @selector(handleSearchChanged:);
        self.searchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [self.searchField setRecentsAutosaveName:@"ChannelListSearchRecents"];
        [contentView addSubview:self.searchField];
        
        // Adjust scroll view position to accommodate search field
        scrollView.frame = NSMakeRect(10, 50, 780, 420);
        
        // Initialize filtered channels array
        _filteredChannels = [[NSMutableArray alloc] init];
        
        // Create buttons
        // Join button - fixed at left
        self.joinButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, 10, 100, 32)];
        [self.joinButton setTitle:L(@"channelList.button.join", @"Join")];
        [self.joinButton setButtonType:NSButtonTypeMomentaryPushIn];
        [self.joinButton setBezelStyle:NSBezelStyleRounded];
        [self.joinButton setTarget:self];
        [self.joinButton setAction:@selector(joinButtonClicked:)];
        [self.joinButton setEnabled:NO];
        self.joinButton.autoresizingMask = NSViewMaxXMargin;  // Fixed at left
        [contentView addSubview:self.joinButton];
        
        // Close button - fixed at right
        self.closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(690, 10, 100, 32)];
        [self.closeButton setTitle:L(@"channelList.button.close", @"Close")];
        [self.closeButton setButtonType:NSButtonTypeMomentaryPushIn];
        [self.closeButton setBezelStyle:NSBezelStyleRounded];
        [self.closeButton setTarget:self];
        [self.closeButton setAction:@selector(closeButtonClicked:)];
        self.closeButton.autoresizingMask = NSViewMinXMargin;  // Move with right edge
        [contentView addSubview:self.closeButton];
        
        // Update List button - before Close button, fixed at right
        self.updateListButton = [[NSButton alloc] initWithFrame:NSMakeRect(580, 10, 100, 32)];
        [self.updateListButton setTitle:L(@"channelList.button.updateList", @"Update List")];
        [self.updateListButton setButtonType:NSButtonTypeMomentaryPushIn];
        [self.updateListButton setBezelStyle:NSBezelStyleRounded];
        [self.updateListButton setTarget:self];
        [self.updateListButton setAction:@selector(updateListButtonClicked:)];
        self.updateListButton.autoresizingMask = NSViewMinXMargin;  // Move with right edge
        [contentView addSubview:self.updateListButton];
        
        // Register for window resize notifications to recalculate row heights
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResize:)
                                                     name:NSWindowDidResizeNotification
                                                   object:window];
    }
    return self;
}

- (void)addChannel:(NSString *)channel userCount:(NSInteger)userCount topic:(NSString *)topic {
    // Log received data for debugging
    CHLog(@"addChannel: Received - channel: '%@' (length: %lu), users: %ld, topic: '%@' (length: %lu)", 
          channel, (unsigned long)(channel ? channel.length : 0), 
          (long)userCount, 
          topic, (unsigned long)(topic ? topic.length : 0));
    
    NSDictionary *channelInfo = @{
        @"channel": channel ?: @"",
        @"userCount": @(userCount),
        @"topic": topic ?: @""
    };
    
    // Ensure we're on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self addChannel:channel userCount:userCount topic:topic];
        });
        return;
    }
    
    if (!self.channels) {
        CHLog(@"ERROR: channels array is nil!");
        self.channels = [[NSMutableArray alloc] init];
    }
    
    // Add channel to array
    [self.channels addObject:channelInfo];
    
    NSUInteger totalCount = self.channels.count;
    CHLog(@"addChannel: Added channel %@ (%ld users), topic length: %lu, total: %lu", 
          channel, (long)userCount, (unsigned long)(topic ? topic.length : 0), (unsigned long)totalCount);
    
    // Update window title to show progress
    if (self.window) {
        NSString *baseTitle = [NSString stringWithFormat:L(@"channelList.title.receiving", @"Channel List (Receiving... %lu channels)"), (unsigned long)totalCount];
        [self.window setTitle:[self windowTitleWithBase:baseTitle]];
    }
    
    // Incremental refresh: refresh table every N channels or use timer
    self.pendingUpdateCount++;
    
    // If threshold reached, refresh immediately
    if (self.pendingUpdateCount >= self.incrementalUpdateThreshold) {
        CHLog(@"addChannel: Threshold reached (%ld), refreshing table incrementally", (long)self.pendingUpdateCount);
        [self refreshTableIncremental];
        self.pendingUpdateCount = 0;
    } else {
        // Schedule delayed refresh using timer (debounce)
        [self scheduleIncrementalRefresh];
    }
}

// Schedule incremental refresh with debouncing
- (void)scheduleIncrementalRefresh {
    // Cancel existing timer
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    
    // Schedule new timer to refresh after a short delay (debounce)
    // This allows multiple channels to be added before refreshing
    __weak ChannelListWindowController *weakSelf = self;
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                         repeats:NO
                                                           block:^(NSTimer * _Nonnull timer) {
        ChannelListWindowController *strongSelf = weakSelf;
        if (strongSelf && strongSelf.pendingUpdateCount > 0) {
            CHLog(@"scheduleIncrementalRefresh: Timer fired, refreshing with %ld pending updates", (long)strongSelf.pendingUpdateCount);
            [strongSelf refreshTableIncremental];
            strongSelf.pendingUpdateCount = 0;
        }
        strongSelf.updateTimer = nil;
    }];
}

// Refresh table incrementally (without full sort, just append new rows)
- (void)refreshTableIncremental {
    if (!self.tableView || !self.window || !self.window.isVisible) {
        return;
    }
    
    // Just update the row count and refresh visible rows
    // Don't sort yet - sorting will happen in finalizeChannels
    [self.tableView noteNumberOfRowsChanged];
    
    // Refresh only visible rows for better performance
    NSRange visibleRange = [self.tableView rowsInRect:self.tableView.visibleRect];
    if (visibleRange.length > 0) {
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:visibleRange];
        [self.tableView reloadDataForRowIndexes:indexSet columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.tableView.numberOfColumns)]];
    } else {
        // If no visible rows, just reload all (shouldn't happen often)
        [self.tableView reloadData];
    }
    
    CHLog(@"refreshTableIncremental: Refreshed table with %lu channels", (unsigned long)self.channels.count);
}

- (void)sortChannelsIncremental {
    // 不再使用增量排序，避免频繁占用主线程
    [self sortChannels];
}

- (void)sortChannels {
    // 仅在 LIST 结束或用户显式触发时调用
    // 在后台线程排序，主线程只做一次 UI 刷新，避免频繁卡顿
    __block NSArray *channelsCopy = nil;
    
    // 从主线程复制当前频道数组
    channelsCopy = [[NSArray alloc] initWithArray:self.channels copyItems:NO];
    
    if (!channelsCopy || channelsCopy.count == 0) {
        CHLog(@"ERROR: Failed to copy channels array or array is empty (count: %lu)", (unsigned long)(channelsCopy ? channelsCopy.count : 0));
        return;
    }
    
    // Capture current sort settings
    NSString *sortKey = self.currentSortKey ?: @"userCount";
    BOOL ascending = self.sortAscending;
    
    CHLog(@"sortChannels: Starting sort with %lu channels, sortKey=%@, ascending=%d", (unsigned long)channelsCopy.count, sortKey, ascending);
    
    // Use a dedicated background queue for sorting
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSMutableArray *sortedChannels = [channelsCopy mutableCopy];
            
            if (!sortedChannels) {
                CHLog(@"ERROR: Failed to create mutable copy of channels");
                return;
            }
            
            CHLog(@"sortChannels: Created mutable copy, starting sort...");
            
            // Sort based on current sort key and direction
            [sortedChannels sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
                @try {
                    if (!obj1 || !obj2) {
                        CHLog(@"ERROR: nil object in comparator");
                        return NSOrderedSame;
                    }
                    
                    NSComparisonResult result = NSOrderedSame;
                    
                    if ([sortKey isEqualToString:@"userCount"]) {
                        // Sort by user count
                        NSInteger count1 = [obj1[@"userCount"] integerValue];
                        NSInteger count2 = [obj2[@"userCount"] integerValue];
                        
                        if (count1 > count2) {
                            result = NSOrderedDescending;
                        } else if (count1 < count2) {
                            result = NSOrderedAscending;
                        } else {
                            // If same user count, sort by channel name as secondary
                            NSString *name1 = obj1[@"channel"] ?: @"";
                            NSString *name2 = obj2[@"channel"] ?: @"";
                            result = [name1 caseInsensitiveCompare:name2];
                        }
                    } else if ([sortKey isEqualToString:@"channel"]) {
                        // Sort by channel name
                        NSString *name1 = obj1[@"channel"] ?: @"";
                        NSString *name2 = obj2[@"channel"] ?: @"";
                        result = [name1 caseInsensitiveCompare:name2];
                    } else if ([sortKey isEqualToString:@"topic"]) {
                        // Sort by topic (strip IRC formatting codes for comparison)
                        NSString *topic1 = obj1[@"topic"] ?: @"";
                        NSString *topic2 = obj2[@"topic"] ?: @"";
                        // Strip IRC control codes for fair comparison
                        topic1 = [self stripIRCFormattingCodes:topic1];
                        topic2 = [self stripIRCFormattingCodes:topic2];
                        result = [topic1 caseInsensitiveCompare:topic2];
                    }
                    
                    // Reverse result if ascending (default comparisons give descending for numbers)
                    if ([sortKey isEqualToString:@"userCount"]) {
                        // For numbers: ascending means smaller first
                        return ascending ? result : -result;
                    } else {
                        // For strings: ascending means A-Z
                        return ascending ? result : -result;
                    }
                } @catch (NSException *exception) {
                    CHLog(@"ERROR in comparator: %@", exception);
                    return NSOrderedSame;
                }
            }];
            
            CHLog(@"sortChannels: Sort completed, updating UI");
        
            // Update UI on main thread - this is the ONLY place we reload the table
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    CHLog(@"sortChannels: Updating UI on main thread");
                    CHLog(@"sortChannels: sortedChannels count: %lu", (unsigned long)sortedChannels.count);
                    
                    // Update channels array safely
                    @synchronized(self.channels) {
                        self.channels = sortedChannels;
                    }
                    
                    // Update filtered channels if search is active
                    [self updateFilteredChannels];
                    
                    CHLog(@"sortChannels: Channels array updated, count: %lu", (unsigned long)self.channels.count);
                    CHLog(@"sortChannels: tableView: %@", self.tableView);
                    CHLog(@"sortChannels: window: %@", self.window);
                    CHLog(@"sortChannels: tableView.delegate: %@", self.tableView.delegate);
                    CHLog(@"sortChannels: tableView.dataSource: %@", self.tableView.dataSource);
                    
                    // 只在最终排序时刷新一次表格，避免接收过程中频繁 reload 卡界面
                    if (self.tableView) {
                        [self.tableView noteNumberOfRowsChanged];
                        [self.tableView reloadData];
                        [self.tableView setNeedsDisplay:YES];
                        CHLog(@"sortChannels: Table view reloaded once after final sort");
                    } else {
                        CHLog(@"ERROR: tableView is nil!");
                    }
                    
                    // Update title after sorting（最终结果）
                    [self updateWindowTitle];
                    
                    CHLog(@"Channel list finalized: %lu channels sorted and displayed", (unsigned long)sortedChannels.count);
                } @catch (NSException *exception) {
                    CHLog(@"ERROR updating UI: %@", exception);
                    CHLog(@"Stack trace: %@", [exception callStackSymbols]);
                }
            });
        } @catch (NSException *exception) {
            CHLog(@"ERROR during sorting: %@", exception);
            CHLog(@"Stack trace: %@", [exception callStackSymbols]);
        }
    });
}

// Helper method to strip IRC formatting codes for comparison
- (NSString *)stripIRCFormattingCodes:(NSString *)string {
    if (!string || string.length == 0) {
        return @"";
    }
    
    NSMutableString *result = [[NSMutableString alloc] init];
    NSUInteger index = 0;
    
    while (index < string.length) {
        unichar c = [string characterAtIndex:index];
        
        // Skip control codes
        if (c == 0x02 || c == 0x1D || c == 0x1F || c == 0x1E || c == 0x16 || c == 0x0F) {
            index++;
            continue;
        }
        
        // Skip color codes (0x03 followed by optional digits)
        if (c == 0x03) {
            index++;
            // Skip foreground color digits (up to 2)
            NSInteger digitsConsumed = 0;
            while (index < string.length && digitsConsumed < 2) {
                unichar digitChar = [string characterAtIndex:index];
                if (digitChar >= '0' && digitChar <= '9') {
                    index++;
                    digitsConsumed++;
                } else {
                    break;
                }
            }
            // Skip comma and background color if present
            if (index < string.length && [string characterAtIndex:index] == ',') {
                index++;
                digitsConsumed = 0;
                while (index < string.length && digitsConsumed < 2) {
                    unichar digitChar = [string characterAtIndex:index];
                    if (digitChar >= '0' && digitChar <= '9') {
                        index++;
                        digitsConsumed++;
                    } else {
                        break;
                    }
                }
            }
            continue;
        }
        
        [result appendFormat:@"%C", c];
        index++;
    }
    
    return result;
}

- (void)setChannelList:(NSArray<NSDictionary<NSString *, id> *> *)channels {
    // Set all channels at once (like Go code does)
    // This is called on main thread from ChatViewController when 323 (RPL_LISTEND) is received
    // This replaces ALL channels in the window with the complete list from the server
    CHLog(@"setChannelList: Setting %lu channels at once (complete list from server)", (unsigned long)channels.count);
    
    // Ensure we're on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setChannelList:channels];
        });
        return;
    }
    
    // Ensure window and tableView exist
    if (!self.window) {
        CHLog(@"ERROR: window is nil in setChannelList!");
        return;
    }
    
    if (!self.tableView) {
        CHLog(@"ERROR: tableView is nil in setChannelList!");
        return;
    }
    
    // Validate input
    if (!channels || channels.count == 0) {
        CHLog(@"ERROR: setChannelList called with empty or nil channels array!");
        return;
    }
    
    // Cancel any pending incremental updates (we're replacing everything now)
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    self.pendingUpdateCount = 0;
    
    // Log previous count for comparison
    NSUInteger previousCount = self.channels ? self.channels.count : 0;
    CHLog(@"setChannelList: Previous channel count: %lu, new count: %lu", (unsigned long)previousCount, (unsigned long)channels.count);
    
    // Clear and set channels (replace all existing channels with complete list)
    @synchronized(self.channels) {
        if (!self.channels) {
            CHLog(@"WARNING: channels array is nil, initializing");
            self.channels = [[NSMutableArray alloc] init];
        }
        
        [self.channels removeAllObjects];
        [self.channels addObjectsFromArray:channels];
        CHLog(@"setChannelList: Replaced all channels - added %lu channels to array", (unsigned long)channels.count);
        
        // Verify the count matches
        if (self.channels.count != channels.count) {
            CHLog(@"ERROR: Channel count mismatch! Expected %lu, got %lu", (unsigned long)channels.count, (unsigned long)self.channels.count);
        }
    }
    
    CHLog(@"setChannelList: Set %lu channels, now sorting and refreshing", (unsigned long)self.channels.count);
    CHLog(@"setChannelList: tableView: %@, window: %@, window.isVisible: %@", 
          self.tableView, self.window, self.window.isVisible ? @"YES" : @"NO");
    
    // Update title
    if (self.window) {
        NSString *baseTitle = [NSString stringWithFormat:L(@"channelList.title.sorting", @"Channel List (%lu channels) - Sorting..."), (unsigned long)self.channels.count];
        [self.window setTitle:[self windowTitleWithBase:baseTitle]];
    }
    
    // Sort and refresh immediately (this will trigger a full redraw)
    [self sortChannels];
}

- (void)clearChannels {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.updateTimer invalidate];
        self.updateTimer = nil;
        self.pendingUpdateCount = 0;
        @synchronized(self.channels) {
            [self.channels removeAllObjects];
        }
        // Clear the attributed topic cache
        [self.attributedTopicCache removeAllObjects];
        // Clear search and filtered channels
        self.searchQuery = nil;
        [self.filteredChannels removeAllObjects];
        if (self.searchField) {
            self.searchField.stringValue = @"";
        }
        [self.tableView reloadData];
        [self.joinButton setEnabled:NO];
        [self.window setTitle:[self windowTitleWithBase:L(@"channelList.window.title", @"Channel List")]];
    });
}

- (void)finalizeChannels {
    // This should already be called on main thread from ChatViewController
    CHLog(@"finalizeChannels: Called on thread: %@", [NSThread isMainThread] ? @"main" : @"background");
    CHLog(@"finalizeChannels: channels count: %lu", (unsigned long)self.channels.count);
    CHLog(@"finalizeChannels: window: %@", self.window);
    CHLog(@"finalizeChannels: tableView: %@", self.tableView);
    
    // Ensure we're on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finalizeChannels];
        });
        return;
    }
    
    // Cancel any pending incremental updates
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    self.pendingUpdateCount = 0;
    
    // Refresh any remaining pending updates first
    if (self.channels.count > 0) {
        [self refreshTableIncremental];
    }
    
    NSInteger count = self.channels.count;
    CHLog(@"finalizeChannels: About to sort %lu channels (final)", (unsigned long)count);
    
    // Update title to show we're processing
    if (self.window) {
        NSString *baseTitle = [NSString stringWithFormat:L(@"channelList.title.sorting", @"Channel List (%lu channels) - Sorting..."), (unsigned long)count];
        [self.window setTitle:[self windowTitleWithBase:baseTitle]];
    }
    
    // Final sort - this will reload the table when done
    [self sortChannels];
}

#pragma mark - Search/Filter

- (void)handleSearchChanged:(id)sender {
    NSString *query = self.searchField.stringValue;
    self.searchQuery = (query.length > 0) ? query : nil;
    
    [self updateFilteredChannels];
    [self.tableView reloadData];
    
    // Update title to show filtered count
    [self updateWindowTitle];
}

- (void)updateFilteredChannels {
    [self.filteredChannels removeAllObjects];
    
    if (!self.searchQuery || self.searchQuery.length == 0) {
        // No search query, show all channels
        return;
    }
    
    NSString *lowerQuery = [self.searchQuery lowercaseString];
    
    for (NSDictionary *channelInfo in self.channels) {
        NSString *channel = channelInfo[@"channel"] ?: @"";
        NSString *topic = channelInfo[@"topic"] ?: @"";
        
        // Strip IRC formatting codes from topic for search
        NSString *plainTopic = [self stripIRCFormattingCodes:topic];
        
        // Check if query appears in channel name or topic (case insensitive)
        NSString *lowerChannel = [channel lowercaseString];
        NSString *lowerTopic = [plainTopic lowercaseString];
        
        if ([lowerChannel containsString:lowerQuery] || [lowerTopic containsString:lowerQuery]) {
            [self.filteredChannels addObject:channelInfo];
        }
    }
}

- (NSArray<NSDictionary<NSString *, id> *> *)displayedChannels {
    if (self.searchQuery && self.searchQuery.length > 0) {
        return self.filteredChannels;
    }
    return self.channels;
}

- (void)updateWindowTitle {
    if (!self.window) {
        return;
    }
    
    NSUInteger totalCount = self.channels.count;
    NSUInteger displayedCount = [self displayedChannels].count;
    
    NSString *baseTitle;
    if (self.searchQuery && self.searchQuery.length > 0) {
        // Show filtered count
        baseTitle = [NSString stringWithFormat:L(@"channelList.title.filtered", @"Channel List (%lu of %lu channels)"), (unsigned long)displayedCount, (unsigned long)totalCount];
    } else {
        baseTitle = [NSString stringWithFormat:L(@"channelList.title.count", @"Channel List (%lu channels)"), (unsigned long)totalCount];
    }
    
    [self.window setTitle:[self windowTitleWithBase:baseTitle]];
}

- (void)showWindow {
    CHLog(@"ChannelListWindowController showWindow: Called");
    CHLog(@"ChannelListWindowController showWindow: window = %@", self.window);
    CHLog(@"ChannelListWindowController showWindow: self = %@", self);
    
    if (!self.window) {
        CHLog(@"ERROR: window is nil in showWindow!");
        return;
    }
    
    // Ensure we're on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showWindow];
        });
        return;
    }
    
    [super showWindow:nil];
    
    // Ensure window stays above main window
    [self.window setLevel:NSFloatingWindowLevel];
    
    // Show window but don't make it key window - this allows main window to still receive focus
    // makeKeyAndOrderFront would make this window key and prevent main window from receiving focus
    [self.window orderFront:nil];
    [self.window orderFrontRegardless];
    
    // Don't activate the app - this allows main window to remain active
    // [NSApp activateIgnoringOtherApps:YES]; // Commented out to allow main window interaction
    
    [self.window setTitle:[self windowTitleWithBase:L(@"channelList.title.receivingSimple", @"Channel List (Receiving...)")]];
    // Ensure window is responsive during loading
    [self.window setAcceptsMouseMovedEvents:YES];
    
    // Set collection behavior to allow interaction with windows behind
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorParticipatesInCycle];
    
    CHLog(@"ChannelListWindowController showWindow: Window shown, isVisible = %@", self.window.isVisible ? @"YES" : @"NO");
    CHLog(@"ChannelListWindowController showWindow: tableView = %@", self.tableView);
    CHLog(@"ChannelListWindowController showWindow: Window frame = %@", NSStringFromRect(self.window.frame));
}

- (void)applyLocalization {
    if (self.window) {
        [self updateWindowTitle];
    }
    if (self.channelColumn) {
        self.channelColumn.title = L(@"channelList.column.channel", @"Channel");
    }
    if (self.usersColumn) {
        self.usersColumn.title = L(@"channelList.column.users", @"Users");
    }
    if (self.topicColumn) {
        self.topicColumn.title = L(@"channelList.column.topic", @"Topic");
    }
    if (self.joinButton) {
        [self.joinButton setTitle:L(@"channelList.button.join", @"Join")];
    }
    if (self.closeButton) {
        [self.closeButton setTitle:L(@"channelList.button.close", @"Close")];
    }
    if (self.updateListButton) {
        [self.updateListButton setTitle:L(@"channelList.button.updateList", @"Update List")];
    }
    if (self.searchField) {
        self.searchField.placeholderString = L(@"channelList.search.placeholder", @"Search channels...");
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    // This should always be called on main thread by NSTableView
    NSArray *displayed = [self displayedChannels];
    NSInteger count = displayed ? displayed.count : 0;
    if (count > 0 && count < 100) {
        // Only log for small counts to avoid spam
        CHLog(@"numberOfRowsInTableView: Returning %ld rows", (long)count);
    }
    return count;
}

// Note: objectValueForTableColumn:row: is not needed for view-based tables
// We only implement viewForTableColumn:row: which handles all cell rendering

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSArray *displayed = [self displayedChannels];
    if (row < 0 || row >= displayed.count) {
        return nil;
    }
    
    NSDictionary *channelInfo = displayed[row];
    if (!channelInfo) {
        return nil;
    }
    
    NSString *identifier = tableColumn.identifier;
    BOOL isTopicColumn = [identifier isEqualToString:@"Topic"];
    
    // Create or reuse NSTableCellView
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];
    
    if (!cellView) {
        // Create a new NSTableCellView with a text field
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, tableView.rowHeight)];
        cellView.identifier = identifier;
        
        // Create and configure text field
        NSTextField *textField = [[NSTextField alloc] initWithFrame:cellView.bounds];
        textField.bordered = NO;
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.selectable = NO;
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        
        if (isTopicColumn) {
            // Topic column: allow multi-line wrapping with auto height
            textField.usesSingleLineMode = NO;
            textField.lineBreakMode = NSLineBreakByWordWrapping;
            textField.cell.wraps = YES;
            textField.cell.scrollable = NO;
            textField.cell.truncatesLastVisibleLine = YES;
            textField.maximumNumberOfLines = 0;  // No limit, auto height
            textField.preferredMaxLayoutWidth = tableColumn.width - 4;
        } else {
            // Other columns: single line with truncation
            textField.usesSingleLineMode = YES;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            textField.cell.truncatesLastVisibleLine = YES;
        }
        
        [cellView addSubview:textField];
        cellView.textField = textField;
        
        // Add constraints to fill the cell
        if (isTopicColumn) {
            // Topic column: fill vertically with padding
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:2],
                [textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-2],
                [textField.topAnchor constraintEqualToAnchor:cellView.topAnchor constant:4],
                [textField.bottomAnchor constraintEqualToAnchor:cellView.bottomAnchor constant:-4]
            ]];
        } else {
            // Other columns: center vertically
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:2],
                [textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-2],
                [textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor]
            ]];
        }
    }
    
    NSTextField *textField = cellView.textField;
    
    // Determine if this row is selected
    BOOL isSelected = (tableView.selectedRow == row);
    NSColor *textColor = isSelected ? [NSColor whiteColor] : [NSColor textColor];
    
    if ([identifier isEqualToString:@"Channel"]) {
        NSString *channel = channelInfo[@"channel"] ?: @"";
        textField.stringValue = channel;
        textField.font = [NSFont systemFontOfSize:13];
        textField.textColor = textColor;
    } else if ([identifier isEqualToString:@"Users"]) {
        NSString *users = [NSString stringWithFormat:@"%ld", (long)[channelInfo[@"userCount"] integerValue]];
        textField.stringValue = users;
        textField.font = [NSFont systemFontOfSize:13];
        textField.textColor = textColor;
    } else if ([identifier isEqualToString:@"Topic"]) {
        NSString *topic = channelInfo[@"topic"] ?: @"";
        NSString *channelName = channelInfo[@"channel"] ?: @"";
        
        NSFont *font = [NSFont systemFontOfSize:13];
        NSColor *defaultColor = textColor;
        
        // Parse IRC colors in topic for display (don't use cache for selected row to ensure correct color)
        NSAttributedString *attrTopic;
        if (isSelected) {
            // When selected, use white color for all text (ignore IRC colors)
            NSString *plainTopic = [self stripIRCFormattingCodes:topic];
            attrTopic = [[NSAttributedString alloc] initWithString:plainTopic 
                                                        attributes:@{NSFontAttributeName: font, 
                                                                    NSForegroundColorAttributeName: [NSColor whiteColor]}];
        } else {
            // Use cached or parse IRC colors
            NSAttributedString *cachedAttr = [self.attributedTopicCache objectForKey:channelName];
            if (cachedAttr) {
                attrTopic = cachedAttr;
            } else {
                attrTopic = [self parseIRCFormattingString:topic font:font defaultColor:defaultColor];
                
                // Cache with channel name as key
                if (channelName.length > 0) {
                    [self.attributedTopicCache setObject:attrTopic forKey:channelName];
                }
            }
        }
        
        textField.attributedStringValue = attrTopic;
    }
    
    return cellView;
}

#pragma mark - NSTableViewDelegate

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    // Calculate row height based on topic text length
    NSArray *displayed = [self displayedChannels];
    if (row < 0 || row >= (NSInteger)displayed.count) {
        return 20.0;
    }
    
    NSDictionary *channelInfo = displayed[row];
    NSString *topic = channelInfo[@"topic"] ?: @"";
    
    // Strip IRC formatting codes for length calculation
    NSString *plainTopic = [self stripIRCFormattingCodes:topic];
    
    // Minimum height for single line
    CGFloat minHeight = 20.0;
    
    // If topic is empty or short, use single line height
    if (plainTopic.length == 0) {
        return minHeight;
    }
    
    // Calculate approximate width available for topic column
    CGFloat topicWidth = self.topicColumn.width - 4;  // padding
    if (topicWidth < 100) {
        topicWidth = 400;  // default
    }
    
    // Calculate text height using attributed string
    NSFont *font = [NSFont systemFontOfSize:13];
    NSDictionary *attributes = @{NSFontAttributeName: font};
    NSAttributedString *attrText = [[NSAttributedString alloc] initWithString:plainTopic attributes:attributes];
    
    // Create text container for measuring
    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:attrText];
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(topicWidth, CGFLOAT_MAX)];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    
    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];
    
    textContainer.lineFragmentPadding = 0;
    
    // Force layout
    [layoutManager glyphRangeForTextContainer:textContainer];
    NSRect usedRect = [layoutManager usedRectForTextContainer:textContainer];
    
    // Add padding (top + bottom)
    CGFloat calculatedHeight = ceil(usedRect.size.height) + 8;
    
    // Clamp to reasonable range (min 20, max 80)
    if (calculatedHeight < minHeight) {
        calculatedHeight = minHeight;
    } else if (calculatedHeight > 80) {
        calculatedHeight = 80;
    }
    
    return calculatedHeight;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger selectedRow = self.tableView.selectedRow;
    NSArray *displayed = [self displayedChannels];
    [self.joinButton setEnabled:(selectedRow >= 0 && selectedRow < displayed.count)];
    
    // Reload visible rows to update text color based on selection
    NSRange visibleRows = [self.tableView rowsInRect:self.tableView.visibleRect];
    NSIndexSet *visibleIndexes = [NSIndexSet indexSetWithIndexesInRange:visibleRows];
    NSIndexSet *allColumns = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.tableView.numberOfColumns)];
    [self.tableView reloadDataForRowIndexes:visibleIndexes columnIndexes:allColumns];
    
    // Don't auto-join on single click - wait for double click or join button
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors {
    // Handle column header click for sorting
    NSArray<NSSortDescriptor *> *sortDescriptors = tableView.sortDescriptors;
    if (sortDescriptors.count == 0) {
        return;
    }
    
    NSSortDescriptor *primarySort = sortDescriptors.firstObject;
    NSString *sortKey = primarySort.key;
    BOOL ascending = primarySort.ascending;
    
    CHLog(@"sortDescriptorsDidChange: sortKey=%@, ascending=%d", sortKey, ascending);
    
    // Update sort state
    self.currentSortKey = sortKey;
    self.sortAscending = ascending;
    
    // Re-sort channels if we have any
    if (self.channels.count > 0) {
        [self sortChannels];
    }
}

- (void)doubleClickAction:(id)sender {
    NSInteger selectedRow = self.tableView.selectedRow;
    NSArray *displayed = [self displayedChannels];
    if (selectedRow >= 0 && selectedRow < displayed.count) {
        [self joinSelectedChannel];
    }
}

- (void)joinButtonClicked:(id)sender {
    [self joinSelectedChannel];
}

- (void)joinSelectedChannel {
    NSInteger selectedRow = self.tableView.selectedRow;
    NSArray *displayed = [self displayedChannels];
    if (selectedRow >= 0 && selectedRow < displayed.count) {
        NSDictionary *channelInfo = displayed[selectedRow];
        NSString *channel = channelInfo[@"channel"];
        
        if (channel && channel.length > 0 && self.delegate) {
            [self.delegate channelListWindowController:self didSelectChannel:channel];
        }
    }
}

- (void)closeButtonClicked:(id)sender {
    [self.window close];
}

- (void)updateListButtonClicked:(id)sender {
    // Request delegate to refresh the channel list
    if (self.delegate && [self.delegate respondsToSelector:@selector(channelListWindowControllerDidRequestRefresh:)]) {
        // Clear current channels and show loading state
        [self clearChannels];
        [self.window setTitle:[self windowTitleWithBase:L(@"channelList.title.loading", @"Channel List - Loading...")]];
        
        // Request refresh from delegate
        [self.delegate channelListWindowControllerDidRequestRefresh:self];
    }
}

- (void)windowDidResize:(NSNotification *)notification {
    // Recalculate row heights when window is resized
    // Clear cache since topic column width may have changed
    [self.attributedTopicCache removeAllObjects];
    
    // Update preferredMaxLayoutWidth for topic column cells
    // and reload table to recalculate heights
    if (self.tableView && self.channels.count > 0) {
        [self.tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self displayedChannels].count)]];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    // Clean up timer and clear channels when window closes
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    [self clearChannels];
}

#pragma mark - IRC Color Parsing

- (NSArray<NSColor *> *)buildIRCColorTable {
    NSMutableArray<NSColor *> *colors = [[NSMutableArray alloc] initWithCapacity:100];
    
    // 0-15: mIRC base palette (fixed)
    [colors addObject:[NSColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0]];      // 0 white
    [colors addObject:[NSColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0]];      // 1 black
    [colors addObject:[NSColor colorWithRed:0.0 green:0.0 blue:0.498 alpha:1.0]];    // 2 navy
    [colors addObject:[NSColor colorWithRed:0.0 green:0.576 blue:0.0 alpha:1.0]];    // 3 green
    [colors addObject:[NSColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0]];      // 4 red
    [colors addObject:[NSColor colorWithRed:0.498 green:0.0 blue:0.0 alpha:1.0]];    // 5 brown
    [colors addObject:[NSColor colorWithRed:0.611 green:0.0 blue:0.611 alpha:1.0]];  // 6 purple
    [colors addObject:[NSColor colorWithRed:0.988 green:0.498 blue:0.0 alpha:1.0]];  // 7 orange
    [colors addObject:[NSColor colorWithRed:1.0 green:1.0 blue:0.0 alpha:1.0]];      // 8 yellow
    [colors addObject:[NSColor colorWithRed:0.0 green:0.988 blue:0.0 alpha:1.0]];    // 9 light green
    [colors addObject:[NSColor colorWithRed:0.0 green:0.576 blue:0.576 alpha:1.0]];  // 10 teal
    [colors addObject:[NSColor colorWithRed:0.0 green:1.0 blue:1.0 alpha:1.0]];      // 11 light cyan
    [colors addObject:[NSColor colorWithRed:0.0 green:0.0 blue:0.988 alpha:1.0]];    // 12 blue
    [colors addObject:[NSColor colorWithRed:1.0 green:0.0 blue:1.0 alpha:1.0]];      // 13 pink
    [colors addObject:[NSColor colorWithRed:0.498 green:0.498 blue:0.498 alpha:1.0]];// 14 gray
    [colors addObject:[NSColor colorWithRed:0.824 green:0.824 blue:0.824 alpha:1.0]];// 15 light gray
    
    // 16-99: Extended color palette (6x6x6 color cube)
    NSArray<NSNumber *> *steps = @[@0, @95, @135, @175, @215, @255];
    for (NSInteger idx = 16; idx <= 99; idx++) {
        NSInteger cubeIndex = idx - 16;
        NSInteger r = cubeIndex / 36;
        NSInteger g = (cubeIndex / 6) % 6;
        NSInteger b = cubeIndex % 6;
        CGFloat red = steps[r].doubleValue / 255.0;
        CGFloat green = steps[g].doubleValue / 255.0;
        CGFloat blue = steps[b].doubleValue / 255.0;
        [colors addObject:[NSColor colorWithRed:red green:green blue:blue alpha:1.0]];
    }
    
    return [colors copy];
}

- (NSAttributedString *)parseIRCFormattingString:(NSString *)message font:(NSFont *)font defaultColor:(NSColor *)defaultColor {
    if (!message || message.length == 0) {
        return [[NSAttributedString alloc] initWithString:@"" attributes:@{NSFontAttributeName: font}];
    }
    
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray<NSColor *> *ircColors = self.ircColorTable;
    
    NSColor *currentForeground = defaultColor;
    NSColor *currentBackground = nil;
    BOOL boldEnabled = NO;
    BOOL italicEnabled = NO;
    BOOL underlineEnabled = NO;
    BOOL strikeEnabled = NO;
    
    NSUInteger index = 0;
    while (index < message.length) {
        unichar c = [message characterAtIndex:index];
        
        if (c == 0x02) { // Bold
            boldEnabled = !boldEnabled;
            index++;
            continue;
        }
        if (c == 0x1D) { // Italic
            italicEnabled = !italicEnabled;
            index++;
            continue;
        }
        if (c == 0x1F) { // Underline
            underlineEnabled = !underlineEnabled;
            index++;
            continue;
        }
        if (c == 0x1E) { // Strikethrough
            strikeEnabled = !strikeEnabled;
            index++;
            continue;
        }
        if (c == 0x16) { // Reverse
            NSColor *temp = currentForeground;
            currentForeground = currentBackground ?: defaultColor;
            currentBackground = temp;
            index++;
            continue;
        }
        if (c == 0x03) { // Color code
            NSUInteger start = index + 1;
            NSUInteger consumed = 0;
            NSString *foregroundDigits = @"";
            NSString *backgroundDigits = @"";

            while (start + consumed < message.length && consumed < 2) {
                unichar digitChar = [message characterAtIndex:start + consumed];
                if (digitChar < '0' || digitChar > '9') {
                    break;
                }
                foregroundDigits = [foregroundDigits stringByAppendingFormat:@"%C", digitChar];
                consumed++;
            }

            if (foregroundDigits.length > 0) {
                NSUInteger nextIndex = start + consumed;
                if (nextIndex < message.length && [message characterAtIndex:nextIndex] == ',') {
                    nextIndex++;
                    NSUInteger bgConsumed = 0;
                    while (nextIndex + bgConsumed < message.length && bgConsumed < 2) {
                        unichar digitChar = [message characterAtIndex:nextIndex + bgConsumed];
                        if (digitChar < '0' || digitChar > '9') {
                            break;
                        }
                        backgroundDigits = [backgroundDigits stringByAppendingFormat:@"%C", digitChar];
                        bgConsumed++;
                    }
                    nextIndex += bgConsumed;
                }

                NSInteger fgIndex = foregroundDigits.integerValue;
                if (fgIndex >= 0 && fgIndex < (NSInteger)ircColors.count) {
                    currentForeground = ircColors[fgIndex];
                } else {
                    currentForeground = defaultColor;
                }

                if (backgroundDigits.length > 0) {
                    NSInteger bgIndex = backgroundDigits.integerValue;
                    if (bgIndex >= 0 && bgIndex < (NSInteger)ircColors.count) {
                        currentBackground = ircColors[bgIndex];
                    } else {
                        currentBackground = nil;
                    }
                } else {
                    currentBackground = nil;
                }

                index = nextIndex;
                continue;
            }
            // IRC spec: \x03 with no digits resets colors
            currentForeground = defaultColor;
            currentBackground = nil;
            index++;
            continue;
        }

        if (c == 0x0F) { // Reset all formatting
            currentForeground = defaultColor;
            currentBackground = nil;
            boldEnabled = NO;
            italicEnabled = NO;
            underlineEnabled = NO;
            strikeEnabled = NO;
            index++;
            continue;
        }

        // Build font with traits
        NSFont *resolvedFont = font;
        NSFontTraitMask traits = 0;
        if (boldEnabled) {
            traits |= NSBoldFontMask;
        }
        if (italicEnabled) {
            traits |= NSItalicFontMask;
        }
        if (traits != 0) {
            NSFont *converted = [[NSFontManager sharedFontManager] convertFont:resolvedFont toHaveTrait:traits];
            if (converted) {
                resolvedFont = converted;
            }
        }

        // Build attributes
        NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
        attributes[NSFontAttributeName] = resolvedFont;
        
        // Apply colors with contrast check to ensure readability
        NSColor *effectiveForeground = currentForeground ?: defaultColor;
        NSColor *effectiveBackground = currentBackground;
        
        // Check if foreground and background have sufficient contrast
        if (effectiveBackground && ![self hasSufficientContrastBetween:effectiveForeground and:effectiveBackground]) {
            effectiveBackground = nil;
        }
        
        attributes[NSForegroundColorAttributeName] = effectiveForeground;
        if (effectiveBackground) {
            attributes[NSBackgroundColorAttributeName] = effectiveBackground;
        }
        if (underlineEnabled) {
            attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        }
        if (strikeEnabled) {
            attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
        }
        
        NSString *charString = [NSString stringWithFormat:@"%C", c];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:charString attributes:attributes]];
        index++;
    }

    return result;
}

// Calculate relative luminance using WCAG formula
- (CGFloat)colorLuminance:(NSColor *)color {
    if (!color) {
        return 1.0;
    }
    NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgbColor) {
        rgbColor = color;
    }
    
    CGFloat r = rgbColor.redComponent;
    CGFloat g = rgbColor.greenComponent;
    CGFloat b = rgbColor.blueComponent;
    
    r = (r <= 0.03928) ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4);
    g = (g <= 0.03928) ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4);
    b = (b <= 0.03928) ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4);
    
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

- (BOOL)hasSufficientContrastBetween:(NSColor *)color1 and:(NSColor *)color2 {
    if (!color1 || !color2) {
        return YES;
    }
    
    CGFloat lum1 = [self colorLuminance:color1];
    CGFloat lum2 = [self colorLuminance:color2];
    
    CGFloat lighter = MAX(lum1, lum2);
    CGFloat darker = MIN(lum1, lum2);
    
    CGFloat ratio = (lighter + 0.05) / (darker + 0.05);
    
    return ratio >= 1.5;
}

@end
