//
//  ChatViewController+UI.m
//  i3Chat
//
//  UI setup and layout methods for ChatViewController
//

#import "ChatViewController+Private.h"

@implementation ChatViewController (UI)

#pragma mark - Visual Theme Helpers

// Fixed light-scheme colors ?? consistent regardless of system appearance.

- (NSColor *)themeBackgroundColor {
    return [NSColor colorWithWhite:0.96 alpha:1.0];
}

- (NSColor *)panelBackgroundColor {
    return [NSColor colorWithWhite:1.00 alpha:1.0];
}

- (NSColor *)panelBorderColor {
    return [NSColor colorWithWhite:0.86 alpha:1.0];
}

- (NSColor *)mutedTextColor {
    return [NSColor colorWithWhite:0.50 alpha:1.0];
}

- (NSFont *)uiFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return [NSFont systemFontOfSize:size weight:weight];
}

- (void)applyPanelStyleToView:(NSView *)view background:(NSColor *)color cornerRadius:(CGFloat)cornerRadius border:(BOOL)border {
    view.wantsLayer = YES;
    if (color) {
        view.layer.backgroundColor = color.CGColor;
    }
    view.layer.cornerRadius = cornerRadius;
    view.layer.masksToBounds = YES;
    view.layer.borderWidth = border ? 0.5 : 0.0;
    view.layer.borderColor = border ? [[self panelBorderColor] CGColor] : nil;
}

static const CGFloat kRightListBottomInset = 40.0;
static const CGFloat kMessageBottomInset = 12.0;
static const CGFloat kInputFieldY = 40.0;

#pragma mark - Main UI Setup

- (void)setupUI {
    // Ensure we're on main thread
    NSAssert([NSThread isMainThread], @"setupUI must be called on main thread");
    
    // Use a reasonable default size - will be resized to fit window
    NSRect frame = NSMakeRect(0, 0, 1200, 800);
    CGFloat windowWidth = frame.size.width;
    CGFloat windowHeight = frame.size.height;
    CGFloat inputHeight = 70; // Space for input + status at bottom
    CGFloat channelBarHeight = 40;
    CGFloat contentHeight = windowHeight - inputHeight - kMessageBottomInset;
    
    // Create main view with modern styling
    ChatView *view = [[ChatView alloc] initWithFrame:frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[self themeBackgroundColor] CGColor];
    // Force Aqua (light) appearance so all subviews use light-scheme system colors
    if (@available(macOS 10.14, *)) {
        view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
    view.chatViewController = self;
    self.view = view;
    
    // Create main horizontal split view: Left (channels) | Middle (chat+log) | Right (users)
    self.mainSplitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth, windowHeight)];
    self.mainSplitView.vertical = YES; // Horizontal split
    self.mainSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    // Divider color customization not supported on older SDKs
    self.mainSplitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [view addSubview:self.mainSplitView];
    
    // Setup left panel (channel list)
    [self setupChannelPanel:windowHeight inputHeight:inputHeight contentHeight:contentHeight];
    
    // Setup middle panel (chat + log)
    [self setupMiddlePanel:windowWidth windowHeight:windowHeight inputHeight:inputHeight contentHeight:contentHeight];
    
    // Setup right panel (user list)
    [self setupUserPanel:windowHeight inputHeight:inputHeight contentHeight:contentHeight];
    
    // Add panels to main split view
    [self.mainSplitView addSubview:self.channelPanel];
    [self.mainSplitView addSubview:self.middleContainer];
    [self.mainSplitView addSubview:self.userPanelContainer];
    
    // Set holding priorities
    [self.mainSplitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];  // Left panel
    [self.mainSplitView setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:1]; // Middle panel (most important)
    [self.mainSplitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:2];  // Right panel
    
    // Set delegate to handle minimum sizes
    self.mainSplitView.delegate = self;
    self.middleSplitView.delegate = self;
    
    // Setup bottom bar
    [self setupBottomBar:view windowWidth:windowWidth inputHeight:inputHeight channelBarHeight:channelBarHeight];
    
    // Force layout first to ensure views are properly sized
    [self.mainSplitView adjustSubviews];
    [self.middleSplitView adjustSubviews];
    
    // Set initial divider positions - use a small delay to ensure layout is complete
    dispatch_async(dispatch_get_main_queue(), ^{
        [self adjustInitialDividerPositions];
    });
    
    CVLog(@"setupUI: Created all UI elements with split views");
    [self loadCustomGroupsFromDefaults];
    [self loadRecentChannelKeysFromDefaults];
    [self applyLocalization];
    [self applyAdaptiveLayerColors];
    
    [self loadPersistedServersAndChannels];
    
    // Apply log window visibility setting from UserDefaults after UI is set up
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyInitialLogWindowVisibility];
    });

    // Delay connection to ensure UI is fully set up
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self connectToServers];
        
        // Select the first configured server from login window
        // This ensures the focus is on the server the user selected when logging in
        if (self.configs.count > 0 && self.configs[0].server.length > 0) {
            NSString *initialServer = self.configs[0].server;
            [self selectServer:initialServer];
            
            // Also set up the server status channel as current
            NSString *statusChannelKey = [self makeChannelKey:initialServer channel:initialServer];
            if (!self.channels[statusChannelKey]) {
                ChannelBuffer *buffer = [[ChannelBuffer alloc] initWithName:initialServer server:initialServer isPrivate:NO];
                self.channels[statusChannelKey] = buffer;
            }
            self.currentChannelKey = statusChannelKey;
            self.currentServer = initialServer;
        }
    });
}

#pragma mark - Panel Setup Helpers

- (void)setupChannelPanel:(CGFloat)windowHeight inputHeight:(CGFloat)inputHeight contentHeight:(CGFloat)contentHeight {
    CGFloat toolbarWidth = 56.0;
    CGFloat bannerHeight = 32.0;
    CGFloat contentWidth = 220.0 - toolbarWidth;
    
    // channelPanel is a subview of mainSplitView which fills entire window
    self.channelPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, windowHeight)];
    self.channelPanel.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:self.channelPanel background:[self panelBackgroundColor] cornerRadius:0.0 border:NO];

    self.leftToolbarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, toolbarWidth, windowHeight)];
    self.leftToolbarView.autoresizingMask = NSViewHeightSizable;
    [self applyPanelStyleToView:self.leftToolbarView background:[NSColor colorWithWhite:0.93 alpha:1.0] cornerRadius:0.0 border:NO];

    self.channelContentContainer = [[NSView alloc] initWithFrame:NSMakeRect(toolbarWidth, 0, contentWidth, windowHeight)];
    self.channelContentContainer.autoresizingMask = NSViewHeightSizable;
    [self applyPanelStyleToView:self.channelContentContainer background:[self panelBackgroundColor] cornerRadius:0.0 border:NO];

    // channelScrollView：占满广告栏下方的区???
    self.channelScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, inputHeight, contentWidth, contentHeight - bannerHeight)];
    self.channelScrollView.hasVerticalScroller = YES;
    self.channelScrollView.borderType = NSNoBorder;
    self.channelScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:self.channelScrollView background:[self panelBackgroundColor] cornerRadius:0.0 border:YES];
    self.channelScrollView.drawsBackground = YES;
    self.channelScrollView.backgroundColor = [self panelBackgroundColor];
    
    // 广告栏：全宽，贴顶，图片拉伸铺满
    self.channelAdBanner = [[NSView alloc] initWithFrame:NSMakeRect(0, windowHeight - bannerHeight, contentWidth, bannerHeight)];
    self.channelAdBanner.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    self.channelAdBanner.wantsLayer = YES;
    self.channelAdBanner.layer.backgroundColor = [[NSColor colorWithWhite:0.97 alpha:1.0] CGColor];
    self.channelAdBanner.layer.borderWidth = 0.5;
    self.channelAdBanner.layer.borderColor = [[self panelBorderColor] CGColor];
    
    self.channelAdImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, bannerHeight)];
    self.channelAdImageView.imageScaling = NSImageScaleAxesIndependently;
    self.channelAdImageView.animates = YES;
    // 优先使用奔跑黑马图：先尝??? GIF 动态图，再尝试 PNG 静态图
    NSString *horseGif = [[NSBundle mainBundle] pathForResource:@"banner_horse" ofType:@"gif"];
    NSString *horsePng = [[NSBundle mainBundle] pathForResource:@"banner_horse" ofType:@"png"];
    NSString *gifPath = [[NSBundle mainBundle] pathForResource:@"banner" ofType:@"gif"];
    if (horseGif.length) {
        self.channelAdImageView.image = [[NSImage alloc] initWithContentsOfFile:horseGif];
    }
    if (!self.channelAdImageView.image && horsePng.length) {
        self.channelAdImageView.image = [[NSImage alloc] initWithContentsOfFile:horsePng];
    }
    if (!self.channelAdImageView.image && gifPath.length) {
        self.channelAdImageView.image = [[NSImage alloc] initWithContentsOfFile:gifPath];
    }
    if (!self.channelAdImageView.image) {
        self.channelAdImageView.image = [NSImage imageNamed:@"banner"];
    }
    if (!self.channelAdImageView.image) {
        self.channelAdLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 6, contentWidth - 20, bannerHeight - 12)];
        self.channelAdLabel.bezeled = NO;
        self.channelAdLabel.drawsBackground = NO;
        self.channelAdLabel.editable = NO;
        self.channelAdLabel.selectable = NO;
        self.channelAdLabel.font = [self uiFontOfSize:12 weight:NSFontWeightSemibold];
        self.channelAdLabel.textColor = [self mutedTextColor];
        self.channelAdLabel.stringValue = L(@"chat.channel.ad", @"广告???");
        [self.channelAdBanner addSubview:self.channelAdLabel];
    } else {
        [self.channelAdBanner addSubview:self.channelAdImageView];
    }
    
    self.channelAdTargetURL = @"https://github.com/chat-client/i3chat";
    NSClickGestureRecognizer *adClick = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(handleChannelAdClick:)];
    [self.channelAdBanner addGestureRecognizer:adClick];
    
    // Separator line between ad banner and channel list ?? NSBox is dark-mode aware
    NSBox *adLine = [[NSBox alloc] initWithFrame:NSMakeRect(0, windowHeight - bannerHeight - 1.0, contentWidth, 1.0)];
    adLine.boxType = NSBoxSeparator;
    adLine.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    
    [self setupChannelListView];
    [self setupFavoritesPanel:windowHeight toolbarWidth:toolbarWidth];
    
    [self.channelPanel addSubview:self.leftToolbarView];
    [self.channelPanel addSubview:self.channelContentContainer];
    [self.channelContentContainer addSubview:self.channelScrollView];
    [self.channelContentContainer addSubview:adLine];
    [self.channelContentContainer addSubview:self.channelAdBanner];
    [self.channelContentContainer addSubview:self.favoritesPanel];
}

- (void)setupChannelListView {
    // Use FocusableOutlineView to allow focus detection
    Class FocusableOutlineViewClass = NSClassFromString(@"FocusableOutlineView");
    if (FocusableOutlineViewClass) {
        self.channelListView = [[FocusableOutlineViewClass alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    } else {
        // Fallback to regular NSOutlineView if class not found
        self.channelListView = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    }
    NSTableColumn *channelColumn = [[NSTableColumn alloc] initWithIdentifier:@"Channel"];
    channelColumn.title = L(@"chat.channelList.title", @"Channels");
    channelColumn.width = 200;
    [self.channelListView addTableColumn:channelColumn];
    self.channelListView.outlineTableColumn = channelColumn;
    self.channelListView.delegate = self;
    self.channelListView.dataSource = self;
    self.channelListView.headerView = nil;
    self.channelListView.rowHeight = 28;
    self.channelListView.backgroundColor = [NSColor clearColor];
    self.channelListView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.channelListView.intercellSpacing = NSMakeSize(0, 2);
    self.channelListView.indentationPerLevel = 12.0;
    self.channelListView.autoresizesOutlineColumn = YES;
    self.channelListView.allowsEmptySelection = NO;
    self.channelListView.allowsMultipleSelection = NO;
    
    // Make outline view accept first responder so we can detect focus
    // This is needed to properly update text colors based on focus state
    // We'll handle this by checking if first responder is the outline view or its subviews
    // Note: NSOutlineView doesn't automatically accept first responder, but we can make it do so
    
    self.channelListMenu = [[NSMenu alloc] initWithTitle:@"ChannelMenu"];
    self.channelListMenu.delegate = self;
    self.channelListView.menu = self.channelListMenu;
    self.channelScrollView.documentView = self.channelListView;
}

- (void)setupFavoritesPanel:(CGFloat)windowHeight toolbarWidth:(CGFloat)toolbarWidth {
    self.favoritesPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220 - toolbarWidth, windowHeight)];
    self.favoritesPanel.autoresizingMask = NSViewHeightSizable;
    [self applyPanelStyleToView:self.favoritesPanel background:[self panelBackgroundColor] cornerRadius:0.0 border:NO];
    self.favoritesPanel.hidden = YES;
    
    self.favoritesPanelTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220 - toolbarWidth, 40)];
    self.favoritesPanelTitleLabel.editable = NO;
    self.favoritesPanelTitleLabel.bezeled = NO;
    self.favoritesPanelTitleLabel.drawsBackground = NO;
    self.favoritesPanelTitleLabel.stringValue = L(@"chat.favorites.title", @"Favorites");
    self.favoritesPanelTitleLabel.font = [self uiFontOfSize:14 weight:NSFontWeightSemibold];
    self.favoritesPanelTitleLabel.textColor = [NSColor colorWithWhite:0.15 alpha:1.0];
    self.favoritesPanelTitleLabel.alignment = NSTextAlignmentLeft;
    self.favoritesPanelTitleLabel.autoresizingMask = NSViewMinYMargin;
    [self.favoritesPanel addSubview:self.favoritesPanelTitleLabel];


    NSMutableArray<NSButton *> *favoritesButtons = [[NSMutableArray alloc] init];
    NSUInteger buttonIndex = 0;
    for (NSDictionary<NSString *, id> *config in [self favoritesButtonConfigs]) {
        NSString *title = L(config[@"key"], config[@"default"]);
        NSButton *button = [self makeFavoritesButtonWithTitle:title];
        NSNumber *filterValue = config[@"filter"];
        if ([filterValue isKindOfClass:[NSNumber class]]) {
            button.tag = filterValue.integerValue;
        } else {
            button.tag = (NSInteger)buttonIndex;
        }
        
        NSString *iconName = config[@"icon"];
        if (iconName) {
            if (@available(macOS 11.0, *)) {
                NSImage *icon = [NSImage imageWithSystemSymbolName:iconName accessibilityDescription:title];
                if (icon) {
                    icon.size = NSMakeSize(14, 14);
                    icon.template = YES;
                    button.image = icon;
                    button.imagePosition = NSImageLeft;
                    button.imageHugsTitle = YES;
                }
            }
        }
        
        [favoritesButtons addObject:button];
        [self.favoritesPanel addSubview:button];
        buttonIndex++;
    }
    self.favoritesButtons = [favoritesButtons copy];
    [self updateFavoritesButtonStates];
}

- (void)setupMiddlePanel:(CGFloat)windowWidth windowHeight:(CGFloat)windowHeight inputHeight:(CGFloat)inputHeight contentHeight:(CGFloat)contentHeight {
    self.middleContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth - 440, windowHeight)];
    self.middleContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    self.middleSplitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, inputHeight + kMessageBottomInset, windowWidth - 440, contentHeight)];
    self.middleSplitView.vertical = NO;
    self.middleSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    // Divider color customization not supported on older SDKs
    self.middleSplitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [self setupFavoritesMiddleView:windowWidth inputHeight:inputHeight contentHeight:contentHeight];
    [self setupChatArea:windowWidth contentHeight:contentHeight];
    [self setupLogArea:windowWidth contentHeight:contentHeight];
    
    [self.middleSplitView addSubview:self.chatScrollView];
    [self.middleSplitView addSubview:self.logContainer];
    [self.middleSplitView setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:0];
    [self.middleSplitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];
    
    [self.middleContainer addSubview:self.middleSplitView];
    
    // Spacer to fill the gap between message window and input bar
    self.middleBottomSpacer = [[NSView alloc] initWithFrame:NSMakeRect(0, inputHeight, windowWidth - 440, kMessageBottomInset)];
    self.middleBottomSpacer.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.middleBottomSpacer.wantsLayer = YES;
    self.middleBottomSpacer.layer.backgroundColor = [[NSColor colorWithWhite:0.98 alpha:1.0] CGColor];
    [self.middleContainer addSubview:self.middleBottomSpacer];
    [self.middleContainer addSubview:self.favoritesMiddleView];
}

- (void)setupFavoritesMiddleView:(CGFloat)windowWidth inputHeight:(CGFloat)inputHeight contentHeight:(CGFloat)contentHeight {
    self.favoritesMiddleView = [[NSView alloc] initWithFrame:NSMakeRect(0, inputHeight + kMessageBottomInset, windowWidth - 440, contentHeight)];
    self.favoritesMiddleView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:self.favoritesMiddleView background:[self panelBackgroundColor] cornerRadius:0.0 border:NO];
    self.favoritesMiddleView.hidden = YES;

    self.favoritesTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, contentHeight - 50, windowWidth - 480, 28)];
    self.favoritesTitleLabel.editable = NO;
    self.favoritesTitleLabel.bezeled = NO;
    self.favoritesTitleLabel.drawsBackground = NO;
    self.favoritesTitleLabel.stringValue = L(@"chat.favorites.title", @"Favorites");
    self.favoritesTitleLabel.font = [self uiFontOfSize:16 weight:NSFontWeightSemibold];
    self.favoritesTitleLabel.textColor = [NSColor colorWithWhite:0.15 alpha:1.0];
    [self.favoritesMiddleView addSubview:self.favoritesTitleLabel];

    self.favoritesScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth - 440, contentHeight - 70)];
    self.favoritesScrollView.hasVerticalScroller = YES;
    self.favoritesScrollView.borderType = NSNoBorder;
    self.favoritesScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:self.favoritesScrollView background:[self panelBackgroundColor] cornerRadius:0.0 border:YES];
    self.favoritesScrollView.drawsBackground = YES;
    self.favoritesScrollView.backgroundColor = [self panelBackgroundColor];

    self.favoritesTableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth - 460, contentHeight - 60)];
    NSTableColumn *favoritesColumn = [[NSTableColumn alloc] initWithIdentifier:@"Favorite"];
    favoritesColumn.title = L(@"chat.favorites.title", @"Favorites");
    favoritesColumn.width = windowWidth - 460;
    [self.favoritesTableView addTableColumn:favoritesColumn];
    self.favoritesTableView.delegate = self;
    self.favoritesTableView.dataSource = self;
    self.favoritesTableView.headerView = nil;
    self.favoritesTableView.rowHeight = 36;
    self.favoritesTableView.backgroundColor = [NSColor clearColor];
    self.favoritesTableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.favoritesTableView.intercellSpacing = NSMakeSize(0, 4);
    self.favoritesMenu = [[NSMenu alloc] initWithTitle:@"FavoritesMenu"];
    self.favoritesMenu.delegate = self;
    self.favoritesTableView.menu = self.favoritesMenu;
    self.favoritesScrollView.documentView = self.favoritesTableView;
    [self.favoritesMiddleView addSubview:self.favoritesScrollView];

    self.favoritesEmptyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, contentHeight / 2.0, windowWidth - 480, 24)];
    self.favoritesEmptyLabel.editable = NO;
    self.favoritesEmptyLabel.bezeled = NO;
    self.favoritesEmptyLabel.drawsBackground = NO;
    self.favoritesEmptyLabel.alignment = NSTextAlignmentCenter;
    self.favoritesEmptyLabel.stringValue = L(@"chat.favorites.empty", @"No favorites yet");
    self.favoritesEmptyLabel.font = [self uiFontOfSize:13 weight:NSFontWeightRegular];
    self.favoritesEmptyLabel.textColor = [self mutedTextColor];
    [self.favoritesMiddleView addSubview:self.favoritesEmptyLabel];
}

- (void)setupChatArea:(CGFloat)windowWidth contentHeight:(CGFloat)contentHeight {
    self.chatScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth - 440, contentHeight * 0.75)];
    self.chatScrollView.hasVerticalScroller = YES;
    self.chatScrollView.scrollerStyle = NSScrollerStyleOverlay; // Modern overlay scrollers
    self.chatScrollView.borderType = NSNoBorder;
    self.chatScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:self.chatScrollView background:[self panelBackgroundColor] cornerRadius:0.0 border:NO];
    // Background color set adaptively by applyAdaptiveLayerColors
    self.chatScrollView.drawsBackground = YES;
    self.chatScrollView.backgroundColor = [self panelBackgroundColor];
    
    self.chatTextView = [[ChatTextView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth - 460, contentHeight * 0.75)];
    self.chatTextView.editable = NO;
    self.chatTextView.selectable = YES;
    self.chatTextView.delegate = self;
    self.chatTextView.richText = YES;
    self.chatTextView.importsGraphics = NO;
    self.chatTextView.usesRuler = NO;
    self.chatTextView.usesFontPanel = NO;
    self.chatTextView.allowsImageEditing = NO;
    if ([self.chatTextView isKindOfClass:[ChatTextView class]]) {
        ((ChatTextView *)self.chatTextView).chatViewController = self;
    }
    self.chatTextView.font = [NSFont fontWithName:@"Menlo" size:13] ?: [NSFont systemFontOfSize:13];
    self.chatTextView.string = L(@"chat.initial.text", @"i3Chat IRC Client\n\nConnecting to server...\n\n");
    self.chatTextView.backgroundColor = [self panelBackgroundColor];
    self.chatTextView.drawsBackground = YES;
    self.chatTextView.textColor = [NSColor colorWithWhite:0.15 alpha:1.0];
    self.chatTextView.linkTextAttributes = @{
        NSForegroundColorAttributeName: [NSColor systemBlueColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSCursorAttributeName: [NSCursor pointingHandCursor]
    };
    self.chatTextView.textContainerInset = NSMakeSize(12, 12);
    self.chatTextView.textContainer.lineFragmentPadding = 0;
    self.chatTextView.allowsUndo = NO;
    
    // Performance optimizations for large text
    [self.chatTextView.layoutManager setAllowsNonContiguousLayout:YES];  // Don't layout entire document
    self.chatTextView.textContainer.widthTracksTextView = YES;
    self.chatTextView.textContainer.heightTracksTextView = NO;
    
    // PERFORMANCE OPTIMIZATION: Configure text container for better performance
    // Set maximum width to avoid unnecessary layout calculations
    self.chatTextView.textContainer.containerSize = NSMakeSize(self.chatTextView.frame.size.width, CGFLOAT_MAX);
    // Use fixed line fragment padding for consistent layout
    self.chatTextView.textContainer.lineFragmentPadding = 0;
    // Optimize for vertical scrolling (most common case)
    self.chatTextView.textContainer.lineBreakMode = NSLineBreakByWordWrapping;
    
    [self.chatTextView setAutomaticSpellingCorrectionEnabled:NO];
    [self.chatTextView setAutomaticTextReplacementEnabled:NO];
    [self.chatTextView setAutomaticQuoteSubstitutionEnabled:NO];
    [self.chatTextView setAutomaticDashSubstitutionEnabled:NO];
    [self.chatTextView setAutomaticLinkDetectionEnabled:NO];  // We do this manually
    [self.chatTextView setContinuousSpellCheckingEnabled:NO];
    [self.chatTextView setGrammarCheckingEnabled:NO];
    
    // Additional performance optimizations
    self.chatTextView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    [self.chatTextView.layoutManager setBackgroundLayoutEnabled:YES];  // Layout in background thread
    
    // PERFORMANCE OPTIMIZATION: Disable unnecessary text view features
    // These can cause performance issues with large documents
    if ([self.chatTextView respondsToSelector:@selector(setUsesFindBar:)]) {
        [self.chatTextView setUsesFindBar:NO];
    }
    if ([self.chatTextView respondsToSelector:@selector(setUsesInspectorBar:)]) {
        [self.chatTextView setUsesInspectorBar:NO];
    }
    
    // Don't set menu directly - let ChatTextView.menuForEvent: handle it
    self.chatScrollView.documentView = self.chatTextView;
    
    // Add scroll notification to track user scrolling
    self.chatScrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(chatScrollViewBoundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:self.chatScrollView.contentView];
}

- (void)setupLogArea:(CGFloat)windowWidth contentHeight:(CGFloat)contentHeight {
    self.logContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth - 440, contentHeight * 0.25)];
    self.logContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.logContainer.wantsLayer = YES;
    self.logContainer.layer.backgroundColor = [[NSColor clearColor] CGColor];
    
    CGFloat logBottomInset = 0.0;
    self.logScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, logBottomInset, windowWidth - 440, contentHeight * 0.25 - logBottomInset)];
    self.logScrollView.hasVerticalScroller = YES;
    self.logScrollView.borderType = NSNoBorder;
    self.logScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:self.logScrollView background:[NSColor colorWithWhite:0.98 alpha:1.0] cornerRadius:0.0 border:NO];
    self.logScrollView.drawsBackground = YES;
    self.logScrollView.backgroundColor = [NSColor colorWithWhite:0.98 alpha:1.0];
    
    self.logTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth - 460, contentHeight * 0.25)];
    self.logTextView.editable = NO;
    self.logTextView.font = [NSFont fontWithName:@"Menlo" size:10] ?: [NSFont systemFontOfSize:10];
    self.logTextView.string = L(@"chat.log.title", @"System Log\n");
    self.logTextView.backgroundColor = [NSColor colorWithWhite:0.98 alpha:1.0];
    self.logTextView.drawsBackground = YES;
    self.logTextView.textColor = [NSColor colorWithWhite:0.25 alpha:1.0];
    self.logTextView.textContainerInset = NSMakeSize(8, 8);
    self.logTextView.textContainer.lineFragmentPadding = 0;
    self.logScrollView.documentView = self.logTextView;
    [self.logContainer addSubview:self.logScrollView];
    
    // Track log scroll to avoid auto-scroll when user reads history
    self.logScrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(logScrollViewBoundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:self.logScrollView.contentView];
}

- (void)setupUserPanel:(CGFloat)windowHeight inputHeight:(CGFloat)inputHeight contentHeight:(CGFloat)contentHeight {
    self.userPanelContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, windowHeight)];
    self.userPanelContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:self.userPanelContainer background:[self panelBackgroundColor] cornerRadius:0.0 border:NO];
    
    self.userPanelContent = [[NSView alloc] initWithFrame:NSMakeRect(0, inputHeight, 220, contentHeight)];
    self.userPanelContent.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:self.userPanelContent background:[self panelBackgroundColor] cornerRadius:0.0 border:YES];
    
    // User count label
    self.userCountLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, contentHeight - 30, 220, 30)];
    self.userCountLabel.editable = NO;
    self.userCountLabel.bezeled = NO;
    self.userCountLabel.drawsBackground = YES;
    self.userCountLabel.backgroundColor = [NSColor colorWithWhite:0.97 alpha:1.0];
    self.userCountLabel.stringValue = [NSString stringWithFormat:L(@"chat.userCount.format", @"Users: %ld"), 0L];
    self.userCountLabel.font = [self uiFontOfSize:12 weight:NSFontWeightSemibold];
    self.userCountLabel.textColor = [NSColor colorWithWhite:0.15 alpha:1.0];
    self.userCountLabel.alignment = NSTextAlignmentCenter;
    self.userCountLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    self.userCountLabel.wantsLayer = YES;
    self.userCountLabel.layer.borderWidth = 0.0;
    self.userCountLabel.layer.borderColor = nil;
    [self.userPanelContent addSubview:self.userCountLabel];

    // User search field
    self.userSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(10, contentHeight - 58, 200, 24)];
    self.userSearchField.placeholderString = L(@"chat.userSearch.placeholder", @"Search users");
    self.userSearchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    self.userSearchField.target = self;
    self.userSearchField.action = @selector(handleUserSearchChanged:);
    self.userSearchField.font = [self uiFontOfSize:12 weight:NSFontWeightRegular];
    [self.userPanelContent addSubview:self.userSearchField];

    // User list scroll view
    NSScrollView *userScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 220, contentHeight - 58)];
    userScrollView.hasVerticalScroller = YES;
    userScrollView.borderType = NSNoBorder;
    userScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self applyPanelStyleToView:userScrollView background:[self panelBackgroundColor] cornerRadius:0.0 border:YES];
    
    self.userListView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    NSTableColumn *userColumn = [[NSTableColumn alloc] initWithIdentifier:@"User"];
    userColumn.title = L(@"chat.userList.title", @"Users");
    userColumn.width = 200;
    [self.userListView addTableColumn:userColumn];
    self.userListView.delegate = self;
    self.userListView.dataSource = self;
    self.userListView.headerView = nil;
    self.userListView.rowHeight = 28;
    self.userListView.backgroundColor = [NSColor clearColor];
    self.userListView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.userListView.intercellSpacing = NSMakeSize(0, 2);
    self.userListView.doubleAction = @selector(userListDoubleClickAction:);
    self.userListView.target = self;
    self.userListMenu = [[NSMenu alloc] initWithTitle:@"UserMenu"];
    self.userListMenu.delegate = self;
    self.userListView.menu = self.userListMenu;
    userScrollView.documentView = self.userListView;
    [self.userPanelContent addSubview:userScrollView];
    
    [self.userPanelContainer addSubview:self.userPanelContent];
}

- (void)setupBottomBar:(NSView *)view windowWidth:(CGFloat)windowWidth inputHeight:(CGFloat)inputHeight channelBarHeight:(CGFloat)channelBarHeight {
    CGFloat toolbarWidth = 56.0;
    CGFloat inputControlPadding = 12.0;
    
    self.bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, windowWidth, inputHeight)];
    self.bottomBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.bottomBar.wantsLayer = YES;
    self.bottomBar.layer.backgroundColor = [[NSColor colorWithWhite:0.98 alpha:1.0] CGColor];
    // No separator here; keep the message/input boundary clean.
    [view addSubview:self.bottomBar];
    
    self.channelBottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220 - toolbarWidth, channelBarHeight)];
    self.channelBottomBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.channelBottomBar.wantsLayer = YES;
    self.channelBottomBar.layer.backgroundColor = [[NSColor colorWithWhite:0.99 alpha:1.0] CGColor];
    self.channelBottomBar.layer.zPosition = 1.0;
    NSBox *channelBarSeparator = [[NSBox alloc] initWithFrame:NSMakeRect(0, channelBarHeight - 1, 220 - toolbarWidth, 1)];
    channelBarSeparator.boxType = NSBoxSeparator;
    channelBarSeparator.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.channelBottomBar addSubview:channelBarSeparator];
    [self.channelContentContainer addSubview:self.channelBottomBar positioned:NSWindowAbove relativeTo:self.channelScrollView];
    
    self.inputBar = [[NSView alloc] initWithFrame:NSMakeRect(220, 0, windowWidth - 220, inputHeight)];
    self.inputBar.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.bottomBar addSubview:self.inputBar];
    
    // Add button (+ button for join server/channel menu)
    self.addButton = [NSButton buttonWithTitle:@"" target:self action:@selector(handleAddButtonClicked:)];
    self.addButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.addButton.controlSize = NSControlSizeSmall;
    self.addButton.toolTip = L(@"chat.button.add.tooltip", @"Join Server or Channel");
    NSImage *addImage = nil;
    if (@available(macOS 11.0, *)) {
        addImage = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:L(@"chat.button.add.tooltip", @"Join Server or Channel")];
    }
    if (addImage) {
        self.addButton.image = addImage;
        self.addButton.imagePosition = NSImageOnly;
    } else {
        self.addButton.title = @"+";
    }

    // Channel list mode buttons
    self.channelModeButton = [self makeChannelListModeButtonWithSymbol:@"sidebar.left"
                                                       fallbackTitle:L(@"chat.list.mode.channels", @"Channels")
                                                                  tag:ChannelListModeChannels];
    self.groupModeButton = [self makeChannelListModeButtonWithSymbol:@"rectangle.3.group"
                                                     fallbackTitle:L(@"chat.list.mode.groups", @"Groups")
                                                                tag:ChannelListModeGroups];
    self.recentModeButton = [self makeChannelListModeButtonWithSymbol:@"clock"
                                                      fallbackTitle:L(@"chat.list.mode.recent", @"Recent")
                                                                 tag:ChannelListModeRecent];
    
    self.channelListModeStackView = [[NSStackView alloc] initWithFrame:NSMakeRect(8, 7, 204, 22)];
    self.channelListModeStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.channelListModeStackView.alignment = NSLayoutAttributeCenterY;
    self.channelListModeStackView.spacing = 6.0;
    self.channelListModeStackView.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.channelListModeStackView addArrangedSubview:self.addButton];
    [self.channelListModeStackView addArrangedSubview:self.channelModeButton];
    [self.channelListModeStackView addArrangedSubview:self.groupModeButton];
    [self.channelListModeStackView addArrangedSubview:self.recentModeButton];
    [self updateChannelListModeButtonStates];
    [self.channelBottomBar addSubview:self.channelListModeStackView];

    // Sidebar toolbar buttons
    self.messagesToolbarButton = [self makeSidebarButtonWithSymbol:@"bubble.left.and.bubble.right"
                                                    fallbackTitle:L(@"chat.sidebar.messages", @"Messages")
                                                               tag:SidebarModeMessages];
    self.favoritesToolbarButton = [self makeSidebarButtonWithSymbol:@"star"
                                                     fallbackTitle:L(@"chat.sidebar.favorites", @"Favorites")
                                                                tag:SidebarModeFavorites];

    self.leftToolbarStackView = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, toolbarWidth, 120)];
    self.leftToolbarStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.leftToolbarStackView.alignment = NSLayoutAttributeCenterX;
    self.leftToolbarStackView.spacing = 10.0;
    [self.leftToolbarStackView addArrangedSubview:self.messagesToolbarButton];
    [self.leftToolbarStackView addArrangedSubview:self.favoritesToolbarButton];
    [self.leftToolbarView addSubview:self.leftToolbarStackView];
    [self updateSidebarButtonStates];
    
    // Input and status fields
    CGFloat inputBarWidth = MAX(0.0, windowWidth - 220);
    CGFloat inputTextWidth = MAX(0.0, inputBarWidth - inputControlPadding * 2);
    
    self.statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(inputControlPadding, 0, inputTextWidth, 22)];
    self.statusField.editable = NO;
    self.statusField.bezeled = NO;
    self.statusField.drawsBackground = NO;
    self.statusField.stringValue = L(@"chat.status.initializing", @"Status: Initializing...");
    self.statusField.font = [self uiFontOfSize:11 weight:NSFontWeightRegular];
    self.statusField.textColor = [NSColor colorWithWhite:0.50 alpha:1.0];
    self.statusField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.statusField.wantsLayer = YES;
    self.statusField.layer.borderWidth = 0.0;
    self.statusField.layer.borderColor = nil;
    [self.inputBar addSubview:self.statusField];
    
    self.inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(inputControlPadding, kInputFieldY, inputTextWidth, 32)];
    self.inputField.delegate = self;
    self.inputField.placeholderString = L(@"chat.input.placeholder", @"Type message here and press Enter...");
    self.inputField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.inputField.bezeled = YES;
    self.inputField.bordered = YES;
    self.inputField.wantsLayer = YES;
    self.inputField.drawsBackground = YES;
    self.inputField.backgroundColor = [self panelBackgroundColor];
    self.inputField.textColor = [NSColor colorWithWhite:0.15 alpha:1.0];
    self.inputField.font = [self uiFontOfSize:14 weight:NSFontWeightRegular];
    self.inputField.layer.borderWidth = 0.0;
    self.inputField.layer.borderColor = nil;
    self.inputField.layer.cornerRadius = 6.0;
    [self.inputBar addSubview:self.inputField];
    
    [self.inputBar addSubview:self.inputField positioned:NSWindowAbove relativeTo:nil];
    [self.inputBar addSubview:self.statusField positioned:NSWindowAbove relativeTo:nil];
    
    [self updateSidebarModeUI];
}

#pragma mark - Divider Position Helpers

- (void)adjustInitialDividerPositions {
    CGFloat leftPanelWidth = 220;
    CGFloat rightPanelWidth = 220;
    CGFloat splitViewWidth = self.mainSplitView.bounds.size.width;
    
    if (splitViewWidth > leftPanelWidth + rightPanelWidth + 300) {
        [self.mainSplitView setPosition:leftPanelWidth ofDividerAtIndex:0];
        [self.mainSplitView setPosition:splitViewWidth - rightPanelWidth ofDividerAtIndex:1];
    } else {
        CGFloat leftSize = splitViewWidth * 0.2;
        CGFloat rightSize = splitViewWidth * 0.2;
        [self.mainSplitView setPosition:leftSize ofDividerAtIndex:0];
        [self.mainSplitView setPosition:splitViewWidth - rightSize ofDividerAtIndex:1];
    }
    
    CGFloat splitViewHeight = self.middleSplitView.bounds.size.height;
    if (splitViewHeight > 0) {
        if (!self.logWindowVisible) {
            [self.middleSplitView setPosition:splitViewHeight ofDividerAtIndex:0];
        } else {
            [self.middleSplitView setPosition:splitViewHeight * 0.75 ofDividerAtIndex:0];
        }
    }
    [self.middleSplitView adjustSubviews];
    
    if (self.logContainer) {
        if (!self.logWindowVisible) {
            [self.middleSplitView setPosition:splitViewHeight ofDividerAtIndex:0];
            self.logContainer.hidden = YES;
        } else {
            self.logContainer.hidden = NO;
        }
    }
}

- (void)applyInitialLogWindowVisibility {
    NSLog(@"🔧 [SETUP] Applying initial log window visibility: %@", self.logWindowVisible ? @"YES" : @"NO");
    if (self.middleSplitView && self.logContainer) {
        self.logContainer.hidden = !self.logWindowVisible;
        
        CGFloat contentHeight = self.middleSplitView.bounds.size.height;
        if (!self.logWindowVisible) {
            NSLog(@"🔧 [SETUP] Hiding log window initially, setting divider to %f", contentHeight);
            [self.middleSplitView setPosition:contentHeight ofDividerAtIndex:0];
        } else {
            NSLog(@"🔧 [SETUP] Showing log window initially, setting divider to %f", contentHeight * 0.75);
            [self.middleSplitView setPosition:contentHeight * 0.75 ofDividerAtIndex:0];
        }
        [self.middleSplitView adjustSubviews];
        self.logContainer.hidden = !self.logWindowVisible;
        NSLog(@"🔧 [SETUP] After initial adjustSubviews: logContainer.hidden = %@", self.logContainer.hidden ? @"YES" : @"NO");
    }
}

#pragma mark - Layout Updates

- (void)updateSidePanelLayouts {
    CGFloat inputHeight = (self.bottomBar && !self.bottomBar.hidden) ? 70.0 : 0.0;
    CGFloat messageInset = kMessageBottomInset;
    CGFloat channelBarHeight = 40.0;
    
    // middleSplitView needs to start at y=inputHeight to avoid overlapping bottomBar
    if (self.middleContainer && self.middleSplitView) {
        NSRect containerBounds = self.middleContainer.bounds;
        NSRect middleFrame = self.middleSplitView.frame;
        middleFrame.origin.x = 0;
        middleFrame.origin.y = inputHeight + messageInset;
        middleFrame.size.width = containerBounds.size.width;
        middleFrame.size.height = MAX(0.0, containerBounds.size.height - inputHeight - messageInset);
        self.middleSplitView.frame = middleFrame;
        if (!self.logWindowVisible) {
            [self.middleSplitView setPosition:self.middleSplitView.bounds.size.height ofDividerAtIndex:0];
            if (self.logContainer) {
                self.logContainer.hidden = YES;
                self.logContainer.frame = NSMakeRect(0, 0, self.middleSplitView.bounds.size.width, 0);
            }
            [self.middleSplitView adjustSubviews];
        }
    }
    
    if (self.middleBottomSpacer) {
        CGFloat spacerHeight = self.logWindowVisible ? 0.0 : messageInset;
        self.middleBottomSpacer.hidden = (spacerHeight <= 0.0);
        NSRect spacerFrame = NSMakeRect(0, inputHeight, self.middleContainer.bounds.size.width, spacerHeight);
        self.middleBottomSpacer.frame = spacerFrame;
    }

    if (self.middleContainer && self.favoritesMiddleView) {
        NSRect containerBounds = self.middleContainer.bounds;
        NSRect favoritesFrame = self.favoritesMiddleView.frame;
        favoritesFrame.origin.x = 0;
        favoritesFrame.origin.y = inputHeight + messageInset;
        favoritesFrame.size.width = containerBounds.size.width;
        favoritesFrame.size.height = MAX(0.0, containerBounds.size.height - inputHeight - messageInset);
        self.favoritesMiddleView.frame = favoritesFrame;
        if (self.favoritesTitleLabel) {
            NSRect labelFrame = self.favoritesTitleLabel.frame;
            labelFrame.origin.x = 20;
            labelFrame.origin.y = MAX(0.0, favoritesFrame.size.height - 50);
            labelFrame.size.width = MAX(0.0, favoritesFrame.size.width - 40);
            labelFrame.size.height = 28;
            self.favoritesTitleLabel.frame = labelFrame;
        }
        if (self.favoritesScrollView) {
            NSRect scrollFrame = self.favoritesScrollView.frame;
            scrollFrame.origin.x = 0;
            scrollFrame.origin.y = 0;
            scrollFrame.size.width = favoritesFrame.size.width;
            scrollFrame.size.height = MAX(0.0, favoritesFrame.size.height - 60);
            self.favoritesScrollView.frame = scrollFrame;
        }
        if (self.favoritesEmptyLabel) {
            NSRect emptyFrame = self.favoritesEmptyLabel.frame;
            emptyFrame.origin.x = 20;
            emptyFrame.origin.y = MAX(0.0, favoritesFrame.size.height / 2.0);
            emptyFrame.size.width = MAX(0.0, favoritesFrame.size.width - 40);
            self.favoritesEmptyLabel.frame = emptyFrame;
        }
    }
    
    // User panel should sit slightly above bottom, aligned to input field bottom
    if (self.userPanelContainer && self.userPanelContent) {
        NSRect containerBounds = self.userPanelContainer.bounds;
        CGFloat bottomInset = kRightListBottomInset;
        NSRect contentFrame = self.userPanelContent.frame;
        contentFrame.origin.x = 0;
        contentFrame.origin.y = bottomInset;
        contentFrame.size.width = containerBounds.size.width;
        contentFrame.size.height = MAX(0.0, containerBounds.size.height - bottomInset);
        self.userPanelContent.frame = contentFrame;
    }
    
    if (self.channelBottomBar) {
        NSRect bottomFrame = self.channelBottomBar.frame;
        bottomFrame.size.height = channelBarHeight;
        self.channelBottomBar.frame = bottomFrame;
    }
}

- (void)updateChannelPanelLayout {
    if (!self.channelPanel || !self.channelScrollView) {
        return;
    }
    
    // If channel panel is hidden, don't update layout
    if (self.mainSplitView && self.mainSplitView.subviews.count > 0) {
        NSView *leftPanel = self.mainSplitView.subviews[0];
        if (leftPanel.hidden) {
            return;
        }
    }
    
    CGFloat defaultBottomBarHeight = 40.0;
    CGFloat bannerHeight = 32.0;
    CGFloat bottomBarHeight = (self.channelBottomBar && !self.channelBottomBar.hidden)
        ? MAX(self.channelBottomBar.frame.size.height, defaultBottomBarHeight)
        : 0.0;
    NSRect panelBounds = self.channelPanel.bounds;
    CGFloat toolbarWidth = self.leftToolbarView ? self.leftToolbarView.frame.size.width : 56.0;

    if (self.leftToolbarView) {
        NSRect toolbarFrame = self.leftToolbarView.frame;
        toolbarFrame.origin.x = 0;
        toolbarFrame.origin.y = 0;
        toolbarFrame.size.width = toolbarWidth;
        toolbarFrame.size.height = panelBounds.size.height;
        self.leftToolbarView.frame = toolbarFrame;
    }

    // Calculate content width once based on panel bounds
    CGFloat contentWidth = MAX(0.0, panelBounds.size.width - toolbarWidth);
    
    if (self.channelContentContainer) {
        // Set frame explicitly to prevent any auto-resize accumulation
        NSRect contentFrame = NSMakeRect(toolbarWidth, 0, contentWidth, panelBounds.size.height);
        // Only update if the frame actually changed to avoid unnecessary updates
        if (!NSEqualRects(self.channelContentContainer.frame, contentFrame)) {
            self.channelContentContainer.frame = contentFrame;
        }
    }

    // Use the calculated contentWidth directly, not from bounds which might have accumulated
    NSRect contentBounds = NSMakeRect(0, 0, contentWidth, panelBounds.size.height);
    
    if (self.channelScrollView) {
        NSRect scrollFrame = NSMakeRect(0, bottomBarHeight, contentWidth, MAX(0.0, contentBounds.size.height - bottomBarHeight - bannerHeight));
        if (!NSEqualRects(self.channelScrollView.frame, scrollFrame)) {
            self.channelScrollView.frame = scrollFrame;
        }
    }

    if (self.channelAdBanner) {
        NSRect bannerFrame = NSMakeRect(0, MAX(0.0, contentBounds.size.height - bannerHeight), contentWidth, bannerHeight);
        if (!NSEqualRects(self.channelAdBanner.frame, bannerFrame)) {
            self.channelAdBanner.frame = bannerFrame;
        }
        if (self.channelAdImageView) {
            self.channelAdImageView.frame = NSMakeRect(0, 0, contentWidth, bannerHeight);
        }
        if (self.channelAdLabel) {
            self.channelAdLabel.frame = NSMakeRect(10, 6, MAX(0.0, contentWidth - 20), bannerHeight - 12);
        }
    }

    if (self.channelBottomBar) {
        NSRect bottomFrame = NSMakeRect(0, 0, contentWidth, bottomBarHeight);
        if (!NSEqualRects(self.channelBottomBar.frame, bottomFrame)) {
            self.channelBottomBar.frame = bottomFrame;
        }
    }

    if (self.favoritesPanel) {
        // Explicitly set frame using calculated width to prevent accumulation
        NSRect favoritesFrame = NSMakeRect(0, bottomBarHeight, contentWidth, MAX(0.0, contentBounds.size.height - bottomBarHeight - bannerHeight));
        // Only update if the frame actually changed to avoid unnecessary updates
        if (!NSEqualRects(self.favoritesPanel.frame, favoritesFrame)) {
            self.favoritesPanel.frame = favoritesFrame;
        }
        [self layoutFavoritesButtonsInPanel];
    }

    if (self.leftToolbarStackView) {
        CGFloat padding = 12.0;
        CGFloat buttonHeight = 32.0;
        CGFloat spacing = 10.0;
        CGFloat stackHeight = buttonHeight * 2 + spacing;
        CGFloat maxWidth = MAX(0.0, toolbarWidth);
        CGFloat originY = MAX(padding, panelBounds.size.height - padding - stackHeight);
        self.leftToolbarStackView.frame = NSMakeRect(0, originY, maxWidth, stackHeight);
    }
}

- (void)handleChannelAdClick:(id)sender {
    NSString *urlString = self.channelAdTargetURL ?: @"https://github.com/chat-client/i3chat";
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)updateInputLayoutForWidth:(CGFloat)windowWidth {
    CGFloat inputControlPadding = 12.0;
    CGFloat leftWidth = self.channelPanel ? self.channelPanel.frame.size.width : 0.0;
    CGFloat rightWidth = 0.0;
    if (self.mainSplitView && self.mainSplitView.subviews.count > 0) {
        leftWidth = self.mainSplitView.subviews[0].frame.size.width;
        if (self.mainSplitView.subviews.count > 2) {
            NSView *rightPanel = self.mainSplitView.subviews[2];
            if (!rightPanel.hidden && self.userListVisible) {
                rightWidth = rightPanel.frame.size.width;
            }
        }
    }
    if (self.channelPanel && self.channelPanel.hidden) {
        leftWidth = 0.0;
    }
    
    if (self.bottomBar && self.inputBar) {
        NSRect bottomFrame = self.bottomBar.frame;
        bottomFrame.origin.x = leftWidth;
        bottomFrame.origin.y = 0;
        bottomFrame.size.width = MAX(0.0, windowWidth - leftWidth - rightWidth);
        bottomFrame.size.height = self.bottomBar.bounds.size.height;
        self.bottomBar.frame = bottomFrame;
        
        NSRect inputFrame = self.inputBar.frame;
        inputFrame.origin.x = 0;
        inputFrame.size.width = bottomFrame.size.width;
        inputFrame.size.height = bottomFrame.size.height;
        self.inputBar.frame = inputFrame;
    }
    
    if (self.channelListModeStackView && self.channelBottomBar && !self.channelBottomBar.hidden) {
        CGFloat padding = 8.0;
        CGFloat controlsHeight = 22.0;
        NSRect controlsFrame = self.channelListModeStackView.frame;
        controlsFrame.origin.x = padding;
        controlsFrame.origin.y = (self.channelBottomBar.bounds.size.height - controlsHeight) / 2.0;
        controlsFrame.size.height = controlsHeight;
        self.channelListModeStackView.frame = controlsFrame;
    }
    
    CGFloat inputBarWidth = self.inputBar ? self.inputBar.bounds.size.width : 0.0;
    CGFloat inputTextWidth = MAX(0.0, inputBarWidth - inputControlPadding * 2);
    
    if (self.statusField) {
        NSRect statusFrame = self.statusField.frame;
        statusFrame.origin.x = inputControlPadding;
        statusFrame.origin.y = 0;
        statusFrame.size.width = inputTextWidth;
        self.statusField.frame = statusFrame;
    }
    
    if (self.inputField) {
        NSRect inputFieldFrame = self.inputField.frame;
        inputFieldFrame.origin.x = inputControlPadding;
        inputFieldFrame.origin.y = kInputFieldY;
        inputFieldFrame.size.width = inputTextWidth;
        self.inputField.frame = inputFieldFrame;
    }
    
}

#pragma mark - Button Creation Helpers

- (NSButton *)makeChannelListModeButtonWithSymbol:(NSString *)symbolName fallbackTitle:(NSString *)fallbackTitle tag:(NSInteger)tag {
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(handleChannelListModeChanged:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.controlSize = NSControlSizeSmall;
    button.buttonType = NSButtonTypeToggle;
    button.tag = tag;
    
    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:fallbackTitle];
    }
    if (image) {
        button.image = image;
        button.imagePosition = NSImageOnly;
        button.title = @"";
    } else {
        button.title = fallbackTitle ?: @"";
    }
    return button;
}

- (NSButton *)makeSidebarButtonWithSymbol:(NSString *)symbolName fallbackTitle:(NSString *)fallbackTitle tag:(NSInteger)tag {
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(handleSidebarModeChanged:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.controlSize = NSControlSizeRegular;
    button.buttonType = NSButtonTypeToggle;
    button.tag = tag;

    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:fallbackTitle];
    }
    if (image) {
        button.image = image;
        button.imagePosition = NSImageOnly;
        button.title = @"";
    } else {
        button.title = fallbackTitle ?: @"";
    }
    return button;
}

#pragma mark - Button State Updates

- (void)updateChannelListModeButtonStates {
    self.channelModeButton.state = (self.channelListMode == ChannelListModeChannels) ? NSControlStateValueOn : NSControlStateValueOff;
    self.groupModeButton.state = (self.channelListMode == ChannelListModeGroups) ? NSControlStateValueOn : NSControlStateValueOff;
    self.recentModeButton.state = (self.channelListMode == ChannelListModeRecent) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)updateChannelListModeButtonTooltips {
    if (self.channelModeButton) {
        self.channelModeButton.toolTip = L(@"chat.list.mode.channels.tooltip", @"Show all channels by server");
    }
    if (self.groupModeButton) {
        self.groupModeButton.toolTip = L(@"chat.list.mode.groups.tooltip", @"Show custom groups");
    }
    if (self.recentModeButton) {
        self.recentModeButton.toolTip = L(@"chat.list.mode.recent.tooltip", @"Show recently visited channels");
    }
}

- (void)updateSidebarButtonStates {
    // Just update button state - let system handle the visual appearance
    self.messagesToolbarButton.state = (self.leftSidebarMode == SidebarModeMessages) ? NSControlStateValueOn : NSControlStateValueOff;
    self.favoritesToolbarButton.state = (self.leftSidebarMode == SidebarModeFavorites) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)updateSidebarButtonTooltips {
    if (self.messagesToolbarButton) {
        self.messagesToolbarButton.toolTip = L(@"chat.sidebar.messages.tooltip", @"Show messages");
    }
    if (self.favoritesToolbarButton) {
        self.favoritesToolbarButton.toolTip = L(@"chat.sidebar.favorites.tooltip", @"Show favorites");
    }
}

#pragma mark - Sidebar Mode Handling

- (void)handleSidebarModeChanged:(NSButton *)sender {
    if (!sender) {
        return;
    }
    SidebarMode mode = (SidebarMode)sender.tag;
    if (self.leftSidebarMode == mode) {
        return;
    }
    self.leftSidebarMode = mode;
    [self updateSidebarButtonStates];
    [self updateSidebarModeUI];
}

- (void)updateSidebarModeUI {
    BOOL showMessages = (self.leftSidebarMode == SidebarModeMessages);
    
    // Save channel panel width before any layout changes
    if (self.channelPanel && self.mainSplitView && self.mainSplitView.subviews.count > 0) {
        NSView *leftPanel = self.mainSplitView.subviews[0];
        if (!leftPanel.hidden) {
            self.savedChannelPanelWidth = leftPanel.frame.size.width;
        }
    }
    
    if (self.channelScrollView) {
        self.channelScrollView.hidden = !showMessages;
    }
    if (self.channelBottomBar) {
        self.channelBottomBar.hidden = !showMessages;
    }
    if (self.favoritesPanel) {
        self.favoritesPanel.hidden = showMessages;
    }
    if (self.middleSplitView) {
        self.middleSplitView.hidden = !showMessages;
    }
    if (self.favoritesMiddleView) {
        self.favoritesMiddleView.hidden = showMessages;
    }
    if (self.bottomBar) {
        self.bottomBar.hidden = !showMessages;
    }
    
    // Handle user list panel visibility
    if (self.userPanelContainer) {
        if (showMessages) {
            if (self.userListWasVisibleBeforeFavorites) {
                self.userPanelContainer.hidden = NO;
                self.userListVisible = YES;
                self.userListWasVisibleBeforeFavorites = NO;
                
                if (self.mainSplitView && self.mainSplitView.subviews.count >= 3) {
                    CGFloat totalWidth = self.mainSplitView.bounds.size.width;
                    NSView *leftPanel = self.mainSplitView.subviews[0];
                    CGFloat leftWidth = leftPanel.hidden ? 0.0 : leftPanel.frame.size.width;
                    CGFloat restoredWidth = self.lastRightPanelWidth > 0.0 ? self.lastRightPanelWidth : 220.0;
                    CGFloat maxRightWidth = totalWidth - leftWidth - 300.0;
                    maxRightWidth = MAX(maxRightWidth, 150.0);
                    restoredWidth = MIN(restoredWidth, maxRightWidth);
                    [self.mainSplitView setPosition:(totalWidth - restoredWidth) ofDividerAtIndex:1];
                    [self.mainSplitView adjustSubviews];
                }
            }
        } else {
            BOOL isCurrentlyVisible = !self.userPanelContainer.hidden && self.userListVisible;
            if (isCurrentlyVisible) {
                self.userListWasVisibleBeforeFavorites = YES;
                self.userPanelContainer.hidden = YES;
                
                if (self.mainSplitView && self.mainSplitView.subviews.count >= 3) {
                    CGFloat totalWidth = self.mainSplitView.bounds.size.width;
                    [self.mainSplitView setPosition:totalWidth ofDividerAtIndex:1];
                    [self.mainSplitView adjustSubviews];
                }
            } else {
                self.userListWasVisibleBeforeFavorites = NO;
            }
        }
    }
    
    // Update title bar buttons visibility
    if (self.view.window && [self.view.window.windowController isKindOfClass:NSClassFromString(@"MainWindowController")]) {
        MainWindowController *mainWindowController = (MainWindowController *)self.view.window.windowController;
        if ([mainWindowController respondsToSelector:@selector(updateTitleBarButtonsForFavoritesMode:)]) {
            [mainWindowController updateTitleBarButtonsForFavoritesMode:!showMessages];
        }
    }
    
    if (!showMessages) {
        [self updateFavoritesButtonStates];
        [self reloadFavoritesTable];
    }
    
    // Restore channel panel width
    if (self.channelPanel && self.mainSplitView && self.mainSplitView.subviews.count > 0) {
        NSView *leftPanel = self.mainSplitView.subviews[0];
        if (!leftPanel.hidden && self.savedChannelPanelWidth > 0) {
            CGFloat totalWidth = self.mainSplitView.bounds.size.width;
            CGFloat currentWidth = leftPanel.frame.size.width;
            if (ABS(currentWidth - self.savedChannelPanelWidth) > 1.0) {
                CGFloat restoredWidth = self.savedChannelPanelWidth;
                restoredWidth = MAX(150.0, MIN(restoredWidth, totalWidth - 300.0));
                [self.mainSplitView setPosition:restoredWidth ofDividerAtIndex:0];
            }
        }
    }
    
    [self updateChannelPanelLayout];
    [self updateInputLayoutForWidth:self.view.bounds.size.width];
    [self updateSidePanelLayouts];
}

- (void)handleChannelListModeChanged:(NSButton *)sender {
    if (!sender) {
        return;
    }
    
    ChannelListMode mode = (ChannelListMode)sender.tag;
    if (self.channelListMode == mode) {
        return;
    }
    self.channelListMode = mode;
    [self updateChannelListModeButtonStates];
    [self reloadChannelListForMode];
}

#pragma mark - Add Button Menu

- (void)handleAddButtonClicked:(NSButton *)sender {
    if (!sender) {
        return;
    }
    
    // Create popup menu
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"AddMenu"];
    menu.autoenablesItems = NO;
    
    // Join Server menu item
    NSMenuItem *joinServerItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.joinServer", @"Join Server")
                                                            action:@selector(handleJoinServerFromMenu:)
                                                     keyEquivalent:@""];
    joinServerItem.target = self;
    [menu addItem:joinServerItem];
    
    // Join Channel menu item
    NSMenuItem *joinChannelItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.joinChannel", @"Join Channel")
                                                             action:@selector(handleAddMenuJoinChannel:)
                                                      keyEquivalent:@""];
    joinChannelItem.target = self;
    
    // Enable Join Channel only if current server is connected and registered
    BOOL canJoinChannel = NO;
    if (self.currentServer.length > 0) {
        IRCClient *client = [self clientForServer:self.currentServer];
        canJoinChannel = client && client.isConnected && client.isRegistered;
    }
    joinChannelItem.enabled = canJoinChannel;
    [menu addItem:joinChannelItem];
    
    // Show menu below the button
    NSRect buttonFrame = sender.frame;
    NSPoint menuLocation = NSMakePoint(0, buttonFrame.size.height + 2);
    [menu popUpMenuPositioningItem:nil atLocation:menuLocation inView:sender];
}

- (void)handleAddMenuJoinChannel:(id)sender {
    if (self.currentServer.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:self.currentServer];
    if (!client || !client.isConnected || !client.isRegistered) {
        return;
    }
    
    NSString *channel = [self promptForInputWithTitle:L(@"prompt.joinChannel.title", @"Join Channel")
                                              message:L(@"prompt.joinChannel.message", @"Enter channel name:")
                                          placeholder:L(@"prompt.joinChannel.placeholder", @"#channel")];
    if (channel.length > 0) {
        if (![channel hasPrefix:@"#"] && ![channel hasPrefix:@"&"]) {
            channel = [@"#" stringByAppendingString:channel];
        }
        [client joinChannel:channel];
    }
}

#pragma mark - Fixed Light-Scheme Colors

// All panels use fixed light colors regardless of system appearance.
// The chat view itself forces NSAppearanceNameAqua so system controls also stay light.

- (void)applyAdaptiveLayerColors {
    if (!self.view.layer) return;

    // Fixed light palette
    NSColor *sidebarBg   = [NSColor colorWithWhite:0.94 alpha:1.0];
    NSColor *panelBg     = [NSColor colorWithWhite:1.00 alpha:1.0];
    NSColor *toolbarBg   = [NSColor colorWithWhite:0.98 alpha:1.0];
    NSColor *bannerBg    = [NSColor colorWithWhite:0.97 alpha:1.0];
    NSColor *borderColor = [NSColor colorWithWhite:0.86 alpha:1.0];
    NSColor *chatBg      = [NSColor colorWithWhite:1.00 alpha:1.0];
    NSColor *logBg       = [NSColor colorWithWhite:0.98 alpha:1.0];
    NSColor *mainBg      = [NSColor colorWithWhite:0.96 alpha:1.0];

    if (self.view.layer)
        self.view.layer.backgroundColor = mainBg.CGColor;
    if (self.channelPanel.layer)
        self.channelPanel.layer.backgroundColor = sidebarBg.CGColor;
    if (self.channelContentContainer.layer)
        self.channelContentContainer.layer.backgroundColor = sidebarBg.CGColor;
    if (self.channelScrollView.layer)
        self.channelScrollView.layer.backgroundColor = sidebarBg.CGColor;
    if (self.favoritesPanel.layer)
        self.favoritesPanel.layer.backgroundColor = sidebarBg.CGColor;
    if (self.leftToolbarView.layer)
        self.leftToolbarView.layer.backgroundColor = [NSColor colorWithWhite:0.93 alpha:1.0].CGColor;
    if (self.userPanelContainer.layer)
        self.userPanelContainer.layer.backgroundColor = panelBg.CGColor;
    if (self.userPanelContent.layer)
        self.userPanelContent.layer.backgroundColor = panelBg.CGColor;
    if (self.channelAdBanner.layer) {
        self.channelAdBanner.layer.backgroundColor = bannerBg.CGColor;
        self.channelAdBanner.layer.borderColor = borderColor.CGColor;
    }
    if (self.bottomBar.layer)
        self.bottomBar.layer.backgroundColor = toolbarBg.CGColor;
    if (self.channelBottomBar.layer)
        self.channelBottomBar.layer.backgroundColor = toolbarBg.CGColor;
    if (self.middleBottomSpacer.layer)
        self.middleBottomSpacer.layer.backgroundColor = toolbarBg.CGColor;

    // Chat / log: set on both scroll view and text view so clipView stays in sync
    if (self.chatScrollView) {
        self.chatScrollView.backgroundColor = chatBg;
        self.chatScrollView.contentView.backgroundColor = chatBg;
    }
    if (self.chatTextView)
        self.chatTextView.backgroundColor = chatBg;
    if (self.logScrollView) {
        self.logScrollView.backgroundColor = logBg;
        self.logScrollView.contentView.backgroundColor = logBg;
    }
    if (self.logTextView)
        self.logTextView.backgroundColor = logBg;

    // Refresh border colors
    for (NSView *v in @[self.channelScrollView, self.userPanelContent,
                        self.favoritesScrollView, self.chatScrollView]) {
        if (v.layer && v.layer.borderWidth > 0.0)
            v.layer.borderColor = borderColor.CGColor;
    }
}

@end
