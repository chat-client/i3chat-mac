#import "WhoisWindowController.h"
#import "LocalizationManager.h"
#import "DebugLog.h"

@interface WhoisInfoRow : NSObject
@property (nonatomic, strong) NSString *label;
@property (nonatomic, strong) NSString *value;
@property (nonatomic, assign) BOOL isChannel;
@end

@implementation WhoisInfoRow
@end

@interface WhoisWindowController ()

@property (nonatomic, strong, readwrite) NSString *nickname;
@property (nonatomic, strong, readwrite) NSString *server;
@property (nonatomic, strong) NSScrollView *infoScrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTableColumn *labelColumn;
@property (nonatomic, strong) NSTableColumn *valueColumn;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSTextField *channelsLabel;
@property (nonatomic, strong) NSScrollView *channelsScrollView;
@property (nonatomic, strong) NSTableView *channelsTableView;
@property (nonatomic, strong) NSDictionary<NSString *, id> *whoisInfo;
@property (nonatomic, strong) NSMutableArray<WhoisInfoRow *> *infoRows;
@property (nonatomic, strong) NSMutableArray<NSString *> *channelsList;

@end

@implementation WhoisWindowController

- (instancetype)initWithNickname:(NSString *)nickname server:(NSString *)server {
    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSRect windowRect = NSMakeRect(
        (screenRect.size.width - 450) / 2,
        (screenRect.size.height - 350) / 2,
        450,
        350
    );

    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:[NSString stringWithFormat:L(@"whois.window.title", @"WHOIS - %@"), nickname]];
    [window setMinSize:NSMakeSize(350, 200)];
    [window setDelegate:self];
    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    [window setHidesOnDeactivate:NO];

    self = [super initWithWindow:window];
    if (self) {
        _nickname = [nickname copy];
        _server = [server copy];
        _infoRows = [[NSMutableArray alloc] init];
        _channelsList = [[NSMutableArray alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyLocalization)
                                                     name:LocalizationDidChangeNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResize:)
                                                     name:NSWindowDidResizeNotification
                                                   object:window];
        
        [self setupUI];
        [self showLoadingState];
    }
    return self;
}

- (void)windowDidResize:(NSNotification *)notification {
    [self updateLayout];
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    CGFloat windowWidth = contentView.bounds.size.width;
    CGFloat padding = 10;
    CGFloat buttonHeight = 32;
    
    // Close button (bottom right)
    self.closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(windowWidth - 110, padding, 100, buttonHeight)];
    [self.closeButton setTitle:L(@"whois.button.close", @"Close")];
    [self.closeButton setButtonType:NSButtonTypeMomentaryPushIn];
    [self.closeButton setBezelStyle:NSBezelStyleRounded];
    [self.closeButton setTarget:self];
    [self.closeButton setAction:@selector(closeButtonClicked:)];
    [contentView addSubview:self.closeButton];
    
    // Channels table scroll view
    self.channelsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.channelsScrollView.hasVerticalScroller = YES;
    self.channelsScrollView.hasHorizontalScroller = NO;
    self.channelsScrollView.borderType = NSBezelBorder;
    self.channelsScrollView.hidden = YES;
    [contentView addSubview:self.channelsScrollView];
    
    // Channels table view
    self.channelsTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.channelsTableView.delegate = self;
    self.channelsTableView.dataSource = self;
    self.channelsTableView.rowHeight = 22;
    self.channelsTableView.headerView = nil;
    self.channelsTableView.doubleAction = @selector(channelDoubleClicked:);
    self.channelsTableView.target = self;
    
    NSTableColumn *channelColumn = [[NSTableColumn alloc] initWithIdentifier:@"Channel"];
    channelColumn.title = L(@"whois.column.channel", @"Channel");
    channelColumn.width = windowWidth - padding * 2 - 20;
    [self.channelsTableView addTableColumn:channelColumn];
    
    self.channelsScrollView.documentView = self.channelsTableView;
    
    // Channels section label
    self.channelsLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.channelsLabel.editable = NO;
    self.channelsLabel.bezeled = NO;
    self.channelsLabel.drawsBackground = NO;
    self.channelsLabel.font = [NSFont boldSystemFontOfSize:12];
    self.channelsLabel.stringValue = L(@"whois.channels.title", @"Channels (double-click to join):");
    self.channelsLabel.hidden = YES;
    [contentView addSubview:self.channelsLabel];
    
    // Info table scroll view
    self.infoScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.infoScrollView.hasVerticalScroller = YES;
    self.infoScrollView.hasHorizontalScroller = NO;
    self.infoScrollView.borderType = NSBezelBorder;
    [contentView addSubview:self.infoScrollView];

    // Info table view
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 24;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    self.tableView.headerView = nil;
    
    self.labelColumn = [[NSTableColumn alloc] initWithIdentifier:@"Label"];
    self.labelColumn.title = L(@"whois.column.field", @"Field");
    self.labelColumn.width = 100;
    self.labelColumn.minWidth = 80;
    [self.tableView addTableColumn:self.labelColumn];
    
    self.valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"Value"];
    self.valueColumn.title = L(@"whois.column.value", @"Value");
    self.valueColumn.width = windowWidth - 100 - padding * 2 - 20;
    self.valueColumn.minWidth = 150;
    [self.tableView addTableColumn:self.valueColumn];
    
    self.infoScrollView.documentView = self.tableView;
}

- (void)updateLayout {
    NSView *contentView = self.window.contentView;
    CGFloat windowWidth = contentView.bounds.size.width;
    CGFloat windowHeight = contentView.bounds.size.height;
    CGFloat padding = 10;
    CGFloat buttonHeight = 32;
    CGFloat spacing = 4;
    CGFloat rowHeight = 24;
    CGFloat channelRowHeight = 22;
    CGFloat channelsLabelHeight = 18;
    
    BOOL showChannels = (self.channelsList.count > 0);
    
    // Calculate info table height based on actual rows
    NSInteger infoRowCount = self.infoRows.count;
    CGFloat infoTableContentHeight = infoRowCount * rowHeight + 4;
    
    // Calculate channels table height based on actual channels
    NSInteger channelCount = self.channelsList.count;
    CGFloat channelsContentHeight = showChannels ? MIN(channelCount * channelRowHeight + 4, 88) : 0;
    
    // Layout from bottom to top
    CGFloat currentY = padding;
    
    // Close button at bottom
    self.closeButton.frame = NSMakeRect(windowWidth - 110, currentY, 100, buttonHeight);
    currentY += buttonHeight + spacing;
    
    if (showChannels) {
        // Channels table above button
        self.channelsScrollView.frame = NSMakeRect(padding, currentY, windowWidth - padding * 2, channelsContentHeight);
        self.channelsScrollView.hidden = NO;
        currentY += channelsContentHeight + spacing;
        
        // Channels label above channels table
        self.channelsLabel.frame = NSMakeRect(padding, currentY, windowWidth - padding * 2, channelsLabelHeight);
        self.channelsLabel.hidden = NO;
        currentY += channelsLabelHeight + spacing;
    } else {
        self.channelsScrollView.hidden = YES;
        self.channelsLabel.hidden = YES;
    }
    
    // Info table fills remaining space at top
    CGFloat infoTableHeight = windowHeight - currentY - padding;
    infoTableHeight = MAX(infoTableHeight, rowHeight * 2); // Minimum 2 rows
    self.infoScrollView.frame = NSMakeRect(padding, currentY, windowWidth - padding * 2, infoTableHeight);
}

- (void)showLoadingState {
    [self.infoRows removeAllObjects];
    [self.channelsList removeAllObjects];
    
    WhoisInfoRow *loadingRow = [[WhoisInfoRow alloc] init];
    loadingRow.label = L(@"whois.status", @"Status");
    loadingRow.value = [NSString stringWithFormat:L(@"whois.loading", @"Loading WHOIS information for %@..."), self.nickname];
    [self.infoRows addObject:loadingRow];
    
    [self updateLayout];
    [self.tableView reloadData];
    [self.channelsTableView reloadData];
}

- (void)setWhoisInfo:(NSDictionary<NSString *, id> *)info {
    _whoisInfo = [info copy];
    [self updateDisplay];
}

- (void)updateDisplay {
    [self.infoRows removeAllObjects];
    [self.channelsList removeAllObjects];
    
    if (!self.whoisInfo) {
        [self.tableView reloadData];
        [self.channelsTableView reloadData];
        return;
    }
    
    // Nickname
    NSString *nick = self.whoisInfo[@"nick"] ?: self.nickname;
    [self addInfoRowWithLabel:L(@"whois.field.nickname", @"Nickname") value:nick];
    
    // User info (user@host)
    NSString *user = self.whoisInfo[@"user"];
    NSString *host = self.whoisInfo[@"host"];
    if (user.length > 0 || host.length > 0) {
        NSString *hostmask = [NSString stringWithFormat:@"%@@%@", user ?: @"", host ?: @""];
        [self addInfoRowWithLabel:L(@"whois.field.hostmask", @"Hostmask") value:hostmask];
    }
    
    // Real name
    NSString *realName = self.whoisInfo[@"realName"];
    if (realName.length > 0) {
        [self addInfoRowWithLabel:L(@"whois.field.realname", @"Real Name") value:realName];
    }
    
    // Server
    NSString *server = self.whoisInfo[@"server"];
    NSString *serverInfo = self.whoisInfo[@"serverInfo"];
    if (server.length > 0) {
        NSString *serverValue = serverInfo.length > 0 
            ? [NSString stringWithFormat:@"%@ (%@)", server, serverInfo]
            : server;
        [self addInfoRowWithLabel:L(@"whois.field.server", @"Server") value:serverValue];
    }
    
    // Is IRC Operator
    NSNumber *isOperator = self.whoisInfo[@"isOperator"];
    if ([isOperator boolValue]) {
        NSString *operatorInfo = self.whoisInfo[@"operatorInfo"];
        NSString *opValue = operatorInfo.length > 0 ? operatorInfo : L(@"whois.value.yes", @"Yes");
        [self addInfoRowWithLabel:L(@"whois.field.operator", @"IRC Operator") value:opValue];
    }
    
    // Away message
    NSString *awayMessage = self.whoisInfo[@"awayMessage"];
    if (awayMessage.length > 0) {
        [self addInfoRowWithLabel:L(@"whois.field.away", @"Away") value:awayMessage];
    }
    
    // Idle time
    NSNumber *idleSeconds = self.whoisInfo[@"idleSeconds"];
    if (idleSeconds) {
        NSString *idleStr = [self formatIdleTime:[idleSeconds integerValue]];
        [self addInfoRowWithLabel:L(@"whois.field.idle", @"Idle Time") value:idleStr];
    }
    
    // Signon time
    NSNumber *signonTime = self.whoisInfo[@"signonTime"];
    if (signonTime && [signonTime integerValue] > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[signonTime doubleValue]];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterMediumStyle;
        [self addInfoRowWithLabel:L(@"whois.field.signon", @"Signon Time") value:[formatter stringFromDate:date]];
    }
    
    // Error message (if any)
    NSString *error = self.whoisInfo[@"error"];
    if (error.length > 0) {
        [self addInfoRowWithLabel:L(@"whois.field.error", @"Error") value:error];
    }
    
    // Parse channels
    NSString *channels = self.whoisInfo[@"channels"];
    if (channels.length > 0) {
        NSArray *channelArray = [channels componentsSeparatedByString:@" "];
        for (NSString *ch in channelArray) {
            NSString *trimmed = [ch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                // Remove mode prefixes like @, +, etc.
                NSString *cleanChannel = trimmed;
                while (cleanChannel.length > 0 && ![cleanChannel hasPrefix:@"#"] && ![cleanChannel hasPrefix:@"&"]) {
                    cleanChannel = [cleanChannel substringFromIndex:1];
                }
                if (cleanChannel.length > 0) {
                    [self.channelsList addObject:trimmed]; // Keep original with prefix for display
                }
            }
        }
    }
    
    // Update layout based on channels visibility
    [self updateLayout];
    
    [self.tableView reloadData];
    [self.channelsTableView reloadData];
}

- (void)addInfoRowWithLabel:(NSString *)label value:(NSString *)value {
    WhoisInfoRow *row = [[WhoisInfoRow alloc] init];
    row.label = label;
    row.value = value;
    [self.infoRows addObject:row];
}

- (NSString *)formatIdleTime:(NSInteger)seconds {
    if (seconds < 60) {
        return [NSString stringWithFormat:L(@"whois.idle.seconds", @"%ld seconds"), (long)seconds];
    } else if (seconds < 3600) {
        NSInteger minutes = seconds / 60;
        NSInteger secs = seconds % 60;
        return [NSString stringWithFormat:L(@"whois.idle.minutes", @"%ld min %ld sec"), (long)minutes, (long)secs];
    } else if (seconds < 86400) {
        NSInteger hours = seconds / 3600;
        NSInteger minutes = (seconds % 3600) / 60;
        return [NSString stringWithFormat:L(@"whois.idle.hours", @"%ld hr %ld min"), (long)hours, (long)minutes];
    } else {
        NSInteger days = seconds / 86400;
        NSInteger hours = (seconds % 86400) / 3600;
        return [NSString stringWithFormat:L(@"whois.idle.days", @"%ld days %ld hr"), (long)days, (long)hours];
    }
}

- (void)channelDoubleClicked:(id)sender {
    NSInteger row = self.channelsTableView.clickedRow;
    if (row < 0 || row >= (NSInteger)self.channelsList.count) {
        return;
    }
    
    NSString *channelWithPrefix = self.channelsList[row];
    // Extract clean channel name (remove mode prefixes like @, +, %, ~, etc.)
    NSString *channel = channelWithPrefix;
    while (channel.length > 0 && ![channel hasPrefix:@"#"] && ![channel hasPrefix:@"&"]) {
        channel = [channel substringFromIndex:1];
    }
    
    if (channel.length > 0 && self.delegate && [self.delegate respondsToSelector:@selector(whoisWindowController:didRequestJoinChannel:)]) {
        [self.delegate whoisWindowController:self didRequestJoinChannel:channel];
    }
}

- (void)closeButtonClicked:(id)sender {
    [self.window close];
}

- (void)windowWillClose:(NSNotification *)notification {
    // Cleanup if needed
}

- (void)applyLocalization {
    if (self.window) {
        [self.window setTitle:[NSString stringWithFormat:L(@"whois.window.title", @"WHOIS - %@"), self.nickname]];
    }
    if (self.closeButton) {
        [self.closeButton setTitle:L(@"whois.button.close", @"Close")];
    }
    if (self.channelsLabel) {
        self.channelsLabel.stringValue = L(@"whois.channels.title", @"Channels (double-click to join):");
    }
    // Re-render the display with new localization
    if (self.whoisInfo) {
        [self updateDisplay];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.tableView) {
        return self.infoRows.count;
    } else if (tableView == self.channelsTableView) {
        return self.channelsList.count;
    }
    return 0;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    if (!cell) {
        cell = [[NSTextField alloc] initWithFrame:NSZeroRect];
        cell.identifier = tableColumn.identifier;
        cell.bordered = NO;
        cell.editable = NO;
        cell.drawsBackground = NO;
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    
    if (tableView == self.tableView) {
        if (row < 0 || row >= (NSInteger)self.infoRows.count) {
            cell.stringValue = @"";
            return cell;
        }
        
        WhoisInfoRow *infoRow = self.infoRows[row];
        if ([tableColumn.identifier isEqualToString:@"Label"]) {
            cell.stringValue = infoRow.label ?: @"";
            cell.font = [NSFont boldSystemFontOfSize:12];
            cell.textColor = [NSColor secondaryLabelColor];
        } else {
            cell.stringValue = infoRow.value ?: @"";
            cell.font = [NSFont systemFontOfSize:12];
            cell.textColor = [NSColor labelColor];
        }
    } else if (tableView == self.channelsTableView) {
        if (row < 0 || row >= (NSInteger)self.channelsList.count) {
            cell.stringValue = @"";
            return cell;
        }
        
        cell.stringValue = self.channelsList[row];
        cell.font = [NSFont systemFontOfSize:12];
        cell.textColor = [NSColor linkColor];
    }
    
    return cell;
}

@end
