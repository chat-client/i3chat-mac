//
//  HistoryWindowController.m
//  i3Chat
//

#import "HistoryWindowController.h"
#import "MessageStorage.h"
#import "DebugLog.h"
#import "LocalizationManager.h"

@interface HistoryWindowController ()

@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSButton *searchButton;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSDatePicker *startDatePicker;
@property (nonatomic, strong) NSDatePicker *endDatePicker;
@property (nonatomic, strong) NSTextField *startDateLabel;
@property (nonatomic, strong) NSTextField *endDateLabel;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTableColumn *timeColumn;
@property (nonatomic, strong) NSTableColumn *senderColumn;
@property (nonatomic, strong) NSTableColumn *contentColumn;
@property (nonatomic, strong) NSArray<Message *> *messages;
@property (nonatomic, strong) NSString *currentWindowKey;
@property (nonatomic, strong) NSString *currentDisplayName;
@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@property (nonatomic, strong) NSArray<NSColor *> *ircColorTable;
@property (nonatomic, strong) NSMutableSet<NSString *> *highlightedSenders;

@end

@implementation HistoryWindowController

- (instancetype)init {
    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSRect windowRect = NSMakeRect(
        (screenRect.size.width - 900) / 2,
        (screenRect.size.height - 650) / 2,
        900,
        650
    );

    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:L(@"history.window.title", @"Local History")];
    [window setMinSize:NSMakeSize(750, 500)];
    [window setDelegate:self];
    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    [window setHidesOnDeactivate:NO];

    self = [super initWithWindow:window];
    if (self) {
        _messages = @[];
        _timeFormatter = [[NSDateFormatter alloc] init];
        [_timeFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        _highlightedSenders = [[NSMutableSet alloc] init];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyLocalization)
                                                     name:LocalizationDidChangeNotification
                                                   object:nil];

        NSView *contentView = window.contentView;
        contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        CGFloat padding = 12.0;
        CGFloat rowHeight = 28.0;
        CGFloat buttonWidth = 70.0;
        CGFloat clearButtonWidth = 70.0;
        CGFloat closeButtonWidth = 70.0;
        CGFloat labelWidth = 70.0;
        CGFloat datePickerWidth = 140.0;

        NSRect bounds = contentView.bounds;
        CGFloat topRowY = bounds.size.height - rowHeight - padding;
        CGFloat secondRowY = topRowY - rowHeight - 8;

        // === First row: Search field + Search button + Clear button + Close button ===
        CGFloat searchFieldWidth = bounds.size.width - padding * 5 - buttonWidth - clearButtonWidth - closeButtonWidth;
        NSRect searchFieldFrame = NSMakeRect(padding, topRowY, searchFieldWidth, rowHeight);
        self.searchField = [[NSSearchField alloc] initWithFrame:searchFieldFrame];
        self.searchField.placeholderString = L(@"history.search.placeholder", @"Search chat history");
        self.searchField.target = self;
        self.searchField.action = @selector(handleSearchAction:);
        self.searchField.delegate = self;
        self.searchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [contentView addSubview:self.searchField];

        NSRect searchButtonFrame = NSMakeRect(NSMaxX(searchFieldFrame) + padding, topRowY, buttonWidth, rowHeight);
        self.searchButton = [[NSButton alloc] initWithFrame:searchButtonFrame];
        [self.searchButton setTitle:L(@"history.button.search", @"Search")];
        [self.searchButton setButtonType:NSButtonTypeMomentaryPushIn];
        [self.searchButton setBezelStyle:NSBezelStyleRounded];
        [self.searchButton setTarget:self];
        [self.searchButton setAction:@selector(handleSearchAction:)];
        self.searchButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
        [contentView addSubview:self.searchButton];

        NSRect clearButtonFrame = NSMakeRect(NSMaxX(searchButtonFrame) + padding, topRowY, clearButtonWidth, rowHeight);
        self.clearButton = [[NSButton alloc] initWithFrame:clearButtonFrame];
        [self.clearButton setTitle:L(@"history.button.clear", @"Clear")];
        [self.clearButton setButtonType:NSButtonTypeMomentaryPushIn];
        [self.clearButton setBezelStyle:NSBezelStyleRounded];
        [self.clearButton setTarget:self];
        [self.clearButton setAction:@selector(clearFiltersClicked:)];
        self.clearButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
        [contentView addSubview:self.clearButton];

        NSRect closeButtonFrame = NSMakeRect(NSMaxX(clearButtonFrame) + padding, topRowY, closeButtonWidth, rowHeight);
        self.closeButton = [[NSButton alloc] initWithFrame:closeButtonFrame];
        [self.closeButton setTitle:L(@"history.button.close", @"Close")];
        [self.closeButton setButtonType:NSButtonTypeMomentaryPushIn];
        [self.closeButton setBezelStyle:NSBezelStyleRounded];
        [self.closeButton setTarget:self];
        [self.closeButton setAction:@selector(closeButtonClicked:)];
        self.closeButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
        [contentView addSubview:self.closeButton];

        // === Second row: Date range filters ===
        CGFloat currentX = padding;
        CGFloat datePickerHeight = 22.0;
        CGFloat labelHeight = 17.0;
        // Vertical offset to center labels with date pickers
        CGFloat labelYOffset = (datePickerHeight - labelHeight) / 2.0;
        
        // Start date label
        self.startDateLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(currentX, secondRowY + labelYOffset, labelWidth, labelHeight)];
        self.startDateLabel.stringValue = L(@"history.label.startDate", @"From:");
        self.startDateLabel.editable = NO;
        self.startDateLabel.bezeled = NO;
        self.startDateLabel.drawsBackground = NO;
        self.startDateLabel.alignment = NSTextAlignmentRight;
        self.startDateLabel.font = [NSFont systemFontOfSize:12];
        self.startDateLabel.autoresizingMask = NSViewMinYMargin;
        [contentView addSubview:self.startDateLabel];
        currentX += labelWidth + 4;

        // Start date picker
        self.startDatePicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(currentX, secondRowY, datePickerWidth, datePickerHeight)];
        self.startDatePicker.datePickerStyle = NSDatePickerStyleTextField;
        self.startDatePicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
        self.startDatePicker.dateValue = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitMonth value:-1 toDate:[NSDate date] options:0];
        self.startDatePicker.target = self;
        self.startDatePicker.action = @selector(datePickerChanged:);
        self.startDatePicker.autoresizingMask = NSViewMinYMargin;
        [contentView addSubview:self.startDatePicker];
        currentX += datePickerWidth + padding * 2;

        // End date label
        self.endDateLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(currentX, secondRowY + labelYOffset, labelWidth, labelHeight)];
        self.endDateLabel.stringValue = L(@"history.label.endDate", @"To:");
        self.endDateLabel.editable = NO;
        self.endDateLabel.bezeled = NO;
        self.endDateLabel.drawsBackground = NO;
        self.endDateLabel.alignment = NSTextAlignmentRight;
        self.endDateLabel.font = [NSFont systemFontOfSize:12];
        self.endDateLabel.autoresizingMask = NSViewMinYMargin;
        [contentView addSubview:self.endDateLabel];
        currentX += labelWidth + 4;

        // End date picker
        self.endDatePicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(currentX, secondRowY, datePickerWidth, datePickerHeight)];
        self.endDatePicker.datePickerStyle = NSDatePickerStyleTextField;
        self.endDatePicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
        self.endDatePicker.dateValue = [NSDate date];
        self.endDatePicker.target = self;
        self.endDatePicker.action = @selector(datePickerChanged:);
        self.endDatePicker.autoresizingMask = NSViewMinYMargin;
        [contentView addSubview:self.endDatePicker];

        // === Table view ===
        CGFloat tableTop = padding;
        CGFloat tableHeight = secondRowY - padding - tableTop;
        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(padding,
                                                                                  tableTop,
                                                                                  bounds.size.width - padding * 2,
                                                                                  tableHeight)];
        scrollView.hasVerticalScroller = YES;
        scrollView.hasHorizontalScroller = YES;
        scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scrollView.borderType = NSBezelBorder;
        [contentView addSubview:scrollView];

        self.tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, scrollView.contentSize.width, scrollView.contentSize.height)];
        self.tableView.delegate = self;
        self.tableView.dataSource = self;
        self.tableView.allowsMultipleSelection = NO;
        self.tableView.usesAlternatingRowBackgroundColors = NO;
        self.tableView.rowHeight = 22;
        self.tableView.target = self;
        self.tableView.action = @selector(tableViewClicked:);

        self.timeColumn = [[NSTableColumn alloc] initWithIdentifier:@"Time"];
        self.timeColumn.title = L(@"history.column.time", @"Time");
        self.timeColumn.width = 160;
        self.timeColumn.minWidth = 140;
        [self.tableView addTableColumn:self.timeColumn];

        self.senderColumn = [[NSTableColumn alloc] initWithIdentifier:@"Sender"];
        self.senderColumn.title = L(@"history.column.sender", @"Sender");
        self.senderColumn.width = 160;
        self.senderColumn.minWidth = 120;
        [self.tableView addTableColumn:self.senderColumn];

        self.contentColumn = [[NSTableColumn alloc] initWithIdentifier:@"Content"];
        self.contentColumn.title = L(@"history.column.content", @"Content");
        self.contentColumn.width = 520;
        self.contentColumn.minWidth = 200;
        [self.tableView addTableColumn:self.contentColumn];

        scrollView.documentView = self.tableView;
    }
    return self;
}

- (void)applyLocalization {
    if (self.window) {
        NSString *title = self.currentDisplayName.length > 0
            ? [NSString stringWithFormat:L(@"history.window.title.format", @"Local History - %@"), self.currentDisplayName]
            : L(@"history.window.title", @"Local History");
        [self.window setTitle:title];
    }
    if (self.searchField) {
        self.searchField.placeholderString = L(@"history.search.placeholder", @"Search chat history");
    }
    if (self.searchButton) {
        [self.searchButton setTitle:L(@"history.button.search", @"Search")];
    }
    if (self.clearButton) {
        [self.clearButton setTitle:L(@"history.button.clear", @"Clear")];
    }
    if (self.closeButton) {
        [self.closeButton setTitle:L(@"history.button.close", @"Close")];
    }
    if (self.startDateLabel) {
        self.startDateLabel.stringValue = L(@"history.label.startDate", @"From:");
    }
    if (self.endDateLabel) {
        self.endDateLabel.stringValue = L(@"history.label.endDate", @"To:");
    }
    if (self.timeColumn) {
        self.timeColumn.title = L(@"history.column.time", @"Time");
    }
    if (self.senderColumn) {
        self.senderColumn.title = L(@"history.column.sender", @"Sender");
    }
    if (self.contentColumn) {
        self.contentColumn.title = L(@"history.column.content", @"Content");
    }
}

- (void)showHistoryForWindowKey:(NSString *)windowKey displayName:(NSString *)displayName {
    if (!windowKey || windowKey.length == 0) {
        return;
    }
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showHistoryForWindowKey:windowKey displayName:displayName];
        });
        return;
    }

    self.currentWindowKey = windowKey;
    self.currentDisplayName = displayName ?: @"";

    NSString *title = self.currentDisplayName.length > 0
        ? [NSString stringWithFormat:L(@"history.window.title.format", @"Local History - %@"), self.currentDisplayName]
        : L(@"history.window.title", @"Local History");
    [self.window setTitle:title];

    // Reset date pickers to default range (last month to today)
    self.startDatePicker.dateValue = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitMonth value:-1 toDate:[NSDate date] options:0];
    self.endDatePicker.dateValue = [NSDate date];

    [super showWindow:nil];
    [self.window setLevel:NSFloatingWindowLevel];
    [self.window orderFrontRegardless];

    [self performSearch];
}

- (void)handleSearchAction:(id)sender {
    [self performSearch];
}

- (void)datePickerChanged:(id)sender {
    [self performSearch];
}

- (void)clearFiltersClicked:(id)sender {
    // Clear search field
    self.searchField.stringValue = @"";
    
    // Reset date pickers to default range
    self.startDatePicker.dateValue = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitMonth value:-1 toDate:[NSDate date] options:0];
    self.endDatePicker.dateValue = [NSDate date];
    
    // Clear highlights
    [self.highlightedSenders removeAllObjects];
    
    // Perform search
    [self performSearch];
}

- (void)performSearch {
    NSString *keyword = self.searchField.stringValue ?: @"";
    NSDate *startDate = self.startDatePicker.dateValue;
    NSDate *endDate = self.endDatePicker.dateValue;
    
    [self handleSearchWithKeyword:keyword startDate:startDate endDate:endDate];
}

- (void)handleSearchWithKeyword:(NSString *)keyword startDate:(NSDate *)startDate endDate:(NSDate *)endDate {
    if (!self.currentWindowKey || self.currentWindowKey.length == 0) {
        return;
    }

    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *query = trimmed.length > 0 ? trimmed : nil;
    NSString *windowKey = [self.currentWindowKey copy];
    
    // Copy dates for use in block
    NSDate *start = [startDate copy];
    NSDate *end = [endDate copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSArray<Message *> *results = [[MessageStorage sharedStorage] searchMessagesForWindowKey:windowKey
                                                                                             keyword:query
                                                                                           startDate:start
                                                                                             endDate:end
                                                                                               limit:5000];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.messages = results ?: @[];
                [self.tableView reloadData];
            });
        } @catch (NSException *exception) {
            SLog(@"History search failed: %@", exception);
        }
    });
}

- (void)closeButtonClicked:(id)sender {
    [self.window close];
}

- (void)windowWillClose:(NSNotification *)notification {
    self.messages = @[];
    [self.highlightedSenders removeAllObjects];
    [self.tableView reloadData];
}

#pragma mark - Sender Highlight

- (void)tableViewClicked:(id)sender {
    NSInteger clickedRow = self.tableView.clickedRow;
    NSInteger clickedColumn = self.tableView.clickedColumn;
    
    if (clickedRow < 0 || clickedRow >= (NSInteger)self.messages.count) {
        // Clicked outside rows - clear all highlights
        if (self.highlightedSenders.count > 0) {
            [self.highlightedSenders removeAllObjects];
            [self.tableView reloadData];
        }
        return;
    }
    
    // Get the column identifier
    NSTableColumn *column = self.tableView.tableColumns[clickedColumn];
    
    // Only toggle highlight when clicking on Sender column
    if ([column.identifier isEqualToString:@"Sender"]) {
        Message *message = self.messages[clickedRow];
        NSString *sender = message.sender;
        
        if (sender.length > 0) {
            [self toggleHighlightForSender:sender];
        }
    } else {
        // Clicking on other columns clears highlights
        if (self.highlightedSenders.count > 0) {
            [self.highlightedSenders removeAllObjects];
            [self.tableView reloadData];
        }
    }
}

- (void)toggleHighlightForSender:(NSString *)sender {
    if (!sender || sender.length == 0) {
        return;
    }
    
    // Check if this sender is already highlighted (case-insensitive)
    NSString *existingSender = nil;
    for (NSString *highlightedSender in self.highlightedSenders) {
        if ([highlightedSender caseInsensitiveCompare:sender] == NSOrderedSame) {
            existingSender = highlightedSender;
            break;
        }
    }
    
    if (existingSender) {
        // Remove from highlighted set
        [self.highlightedSenders removeObject:existingSender];
    } else {
        // Add to highlighted set
        [self.highlightedSenders addObject:sender];
    }
    
    // Reload table to apply highlight changes
    [self.tableView reloadData];
}

- (BOOL)isSenderHighlighted:(NSString *)sender {
    if (!sender || sender.length == 0) {
        return NO;
    }
    
    for (NSString *highlightedSender in self.highlightedSenders) {
        if ([highlightedSender caseInsensitiveCompare:sender] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - IRC Color Parsing

- (NSArray<NSColor *> *)ircColorTable {
    if (!_ircColorTable) {
        NSMutableArray<NSColor *> *colors = [[NSMutableArray alloc] initWithCapacity:100];
        // 0-15: mIRC base palette
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

        // 16-99: Extended color cube
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
        _ircColorTable = [colors copy];
    }
    return _ircColorTable;
}

- (NSAttributedString *)parseIRCFormattingString:(NSString *)message font:(NSFont *)font defaultColor:(NSColor *)defaultColor {
    if (!message || message.length == 0) {
        return [[NSAttributedString alloc] initWithString:@"" attributes:@{NSFontAttributeName: font}];
    }
    
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray<NSColor *> *ircColors = [self ircColorTable];
    
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

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.messages.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    // This method is still needed for non-Content columns
    if (row < 0 || row >= (NSInteger)self.messages.count) {
        return @"";
    }
    Message *message = self.messages[row];
    if ([tableColumn.identifier isEqualToString:@"Time"]) {
        return [self.timeFormatter stringFromDate:message.timestamp] ?: @"";
    }
    if ([tableColumn.identifier isEqualToString:@"Sender"]) {
        return message.sender ?: @"";
    }
    if ([tableColumn.identifier isEqualToString:@"Content"]) {
        return message.content ?: @"";
    }
    return @"";
}

#pragma mark - NSTableViewDelegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    NSTableRowView *rowView = [[NSTableRowView alloc] init];
    
    if (row >= 0 && row < (NSInteger)self.messages.count) {
        Message *message = self.messages[row];
        BOOL hasHighlight = (self.highlightedSenders.count > 0);
        BOOL isHighlighted = [self isSenderHighlighted:message.sender];
        
        if (hasHighlight) {
            if (isHighlighted) {
                // Bright yellow background for highlighted messages
                rowView.backgroundColor = [NSColor colorWithRed:1.0 green:0.95 blue:0.6 alpha:1.0];
            } else {
                // Dimmed background for non-highlighted messages
                rowView.backgroundColor = [NSColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
            }
        } else {
            // Alternating row colors when no highlight is active
            if (row % 2 == 0) {
                rowView.backgroundColor = [NSColor controlBackgroundColor];
            } else {
                rowView.backgroundColor = [NSColor colorWithRed:0.97 green:0.97 blue:0.98 alpha:1.0];
            }
        }
    }
    
    return rowView;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.messages.count) {
        return nil;
    }
    
    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];
    
    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, tableView.rowHeight)];
        cellView.identifier = identifier;
        
        NSTextField *textField = [[NSTextField alloc] initWithFrame:cellView.bounds];
        textField.editable = NO;
        textField.selectable = YES;
        textField.bezeled = NO;
        textField.drawsBackground = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        cellView.textField = textField;
        [cellView addSubview:textField];
    }
    
    Message *message = self.messages[row];
    NSTextField *textField = cellView.textField;
    
    // Check highlight state
    BOOL hasHighlight = (self.highlightedSenders.count > 0);
    BOOL isHighlighted = [self isSenderHighlighted:message.sender];
    
    // Colors for different states
    NSColor *highlightTextColor = [NSColor colorWithWhite:0.10 alpha:1.0];
    NSColor *highlightSenderColor = [NSColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0];
    NSColor *dimmedTextColor = [NSColor colorWithWhite:0.60 alpha:1.0];
    NSColor *normalTextColor = [NSColor labelColor];
    NSColor *normalSecondaryColor = [NSColor secondaryLabelColor];
    NSColor *senderClickableColor = [NSColor colorWithRed:0.0 green:0.4 blue:0.8 alpha:1.0];
    
    if ([identifier isEqualToString:@"Time"]) {
        textField.stringValue = [self.timeFormatter stringFromDate:message.timestamp] ?: @"";
        textField.font = [NSFont systemFontOfSize:12];
        if (hasHighlight) {
            textField.textColor = isHighlighted ? highlightTextColor : dimmedTextColor;
        } else {
            textField.textColor = normalSecondaryColor;
        }
    } else if ([identifier isEqualToString:@"Sender"]) {
        textField.stringValue = message.sender ?: @"";
        textField.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        if (hasHighlight) {
            textField.textColor = isHighlighted ? highlightSenderColor : dimmedTextColor;
        } else {
            // Make sender clickable appearance (blue with underline)
            NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:message.sender ?: @""];
            [attrStr addAttribute:NSForegroundColorAttributeName value:senderClickableColor range:NSMakeRange(0, attrStr.length)];
            [attrStr addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:NSMakeRange(0, attrStr.length)];
            [attrStr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium] range:NSMakeRange(0, attrStr.length)];
            textField.attributedStringValue = attrStr;
        }
    } else if ([identifier isEqualToString:@"Content"]) {
        // Parse IRC formatting for content column
        NSString *content = message.content ?: @"";
        NSFont *font = [NSFont systemFontOfSize:12];
        NSColor *defaultColor;
        if (hasHighlight) {
            defaultColor = isHighlighted ? highlightTextColor : dimmedTextColor;
        } else {
            defaultColor = normalTextColor;
        }
        NSAttributedString *attrStr = [self parseIRCFormattingString:content font:font defaultColor:defaultColor];
        
        // If dimmed, override all colors
        if (hasHighlight && !isHighlighted) {
            NSMutableAttributedString *mutableAttr = [attrStr mutableCopy];
            [mutableAttr addAttribute:NSForegroundColorAttributeName value:dimmedTextColor range:NSMakeRange(0, mutableAttr.length)];
            textField.attributedStringValue = mutableAttr;
        } else {
            textField.attributedStringValue = attrStr;
        }
    }
    
    return cellView;
}

@end
