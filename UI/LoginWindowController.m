//
//  LoginWindowController.m
//  i3Chat
//

#import "LoginWindowController.h"
#import "IRCConfig.h"
#import "ServerHistoryStorage.h"
#import "LocalizationManager.h"
#import "DebugLog.h"
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat kServerListHeaderIndent = 22.0;

@interface LoginWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSMenuDelegate, NSTextFieldDelegate>

@property (nonatomic, strong, readwrite) NSTextField *serverField;
@property (nonatomic, strong, readwrite) NSTextField *nickField;
@property (nonatomic, strong, readwrite) NSTextField *channelField;
@property (nonatomic, strong, readwrite) NSTextField *realNameField;
@property (nonatomic, strong, readwrite) NSSecureTextField *passwordField;
@property (nonatomic, strong, readwrite) NSButton *savePasswordCheckbox;
@property (nonatomic, strong, readwrite) NSButton *useTLSCheckbox;
@property (nonatomic, strong) NSButton *connectButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *supportLinkButton;
@property (nonatomic, strong) NSTrackingArea *supportLinkTrackingArea;
@property (nonatomic, assign) BOOL supportLinkHovered;
@property (nonatomic, strong) NSTableView *serverListView;
@property (nonatomic, strong) NSTableColumn *serverListColumn;
@property (nonatomic, strong) NSTextField *serverListHeaderLabel;
@property (nonatomic, strong) NSTextField *serverLabel;
@property (nonatomic, strong) NSTextField *nickLabel;
@property (nonatomic, strong) NSTextField *channelLabel;
@property (nonatomic, strong) NSTextField *realNameLabel;
@property (nonatomic, strong) NSTextField *passwordLabel;
@property (nonatomic, strong) NSTextField *languageLabel;
@property (nonatomic, strong) NSPopUpButton *languagePopup;
@property (nonatomic, strong) NSArray<NSString *> *historyServers;
@property (nonatomic, strong) NSArray<NSDictionary *> *defaultServers;
@property (nonatomic, copy) NSString *initialServerValue;
@property (nonatomic, assign) BOOL didLoginSuccessfully;
@property (nonatomic, strong) NSView *leftCard;
@property (nonatomic, strong) NSView *rightCard;

@end

@implementation LoginWindowController

- (NSColor *)brandColor {
    return [NSColor colorWithCalibratedRed:0.10 green:0.55 blue:0.58 alpha:1.0];
}

- (NSColor *)brandTintColor {
    return [NSColor colorWithCalibratedRed:0.10 green:0.55 blue:0.58 alpha:0.12];
}

- (void)styleField:(NSTextField *)field {
    field.bordered = YES;
    field.bezeled = YES;
    field.font = [NSFont systemFontOfSize:14];
    field.focusRingType = NSFocusRingTypeDefault;
    field.wantsLayer = YES;
    field.layer.cornerRadius = 6.0;
    field.layer.masksToBounds = YES;
}

- (void)styleLabel:(NSTextField *)label {
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
}

- (void)updateSupportLinkButtonAppearance {
    if (!self.supportLinkButton) {
        return;
    }
    NSString *title = L(@"login.link.support", @"Support");
    NSColor *linkColor = nil;
    if (self.supportLinkHovered) {
        linkColor = [self brandColor];
    } else if (@available(macOS 10.14, *)) {
        linkColor = [NSColor linkColor];
    } else {
        linkColor = [self brandColor];
    }
    NSDictionary *attributes = @{
        NSForegroundColorAttributeName: linkColor,
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSFontAttributeName: [NSFont systemFontOfSize:13]
    };
    self.supportLinkButton.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:attributes];
}

- (void)configureSupportLinkTracking {
    if (!self.supportLinkButton) {
        return;
    }
    if (self.supportLinkTrackingArea) {
        [self.supportLinkButton removeTrackingArea:self.supportLinkTrackingArea];
    }
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect;
    self.supportLinkTrackingArea = [[NSTrackingArea alloc] initWithRect:self.supportLinkButton.bounds
                                                                 options:options
                                                                   owner:self
                                                                userInfo:nil];
    [self.supportLinkButton addTrackingArea:self.supportLinkTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    if (!self.supportLinkButton) {
        return;
    }
    self.supportLinkHovered = YES;
    [self updateSupportLinkButtonAppearance];
    [[NSCursor pointingHandCursor] set];
}

- (void)mouseExited:(NSEvent *)event {
    if (!self.supportLinkButton) {
        return;
    }
    self.supportLinkHovered = NO;
    [self updateSupportLinkButtonAppearance];
    [[NSCursor arrowCursor] set];
}

- (void)applyCardStyleToView:(NSView *)view {
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:1.0 alpha:0.48] CGColor];
    view.layer.cornerRadius = 14.0;
    view.layer.masksToBounds = NO;
    view.layer.shadowColor = [[NSColor colorWithCalibratedWhite:0 alpha:0.18] CGColor];
    view.layer.shadowOpacity = 0.8;
    view.layer.shadowRadius = 16.0;
    view.layer.shadowOffset = CGSizeMake(0, -2);
}

- (void)configureLanguagePopup {
    if (!self.languagePopup) {
        return;
    }
    [self.languagePopup removeAllItems];
    NSArray<NSString *> *codes = [[LocalizationManager sharedManager] supportedLanguageCodes];
    for (NSString *code in codes) {
        NSString *title = code;
        if ([code isEqualToString:@"en"]) {
            title = L(@"menu.language.english", @"English");
        } else if ([code hasPrefix:@"zh"]) {
            title = L(@"menu.language.chinese", @"Simplified Chinese");
        }
        [self.languagePopup addItemWithTitle:title];
        self.languagePopup.lastItem.representedObject = code;
    }
    NSString *current = [[LocalizationManager sharedManager] currentLanguageCode];
    NSInteger index = [self.languagePopup indexOfItemWithRepresentedObject:current];
    if (index < 0) {
        index = 0;
    }
    [self.languagePopup selectItemAtIndex:index];
}

- (void)languageSelectionChanged:(id)sender {
    NSString *code = self.languagePopup.selectedItem.representedObject;
    if (code.length == 0) {
        code = @"en";
    }
    [[LocalizationManager sharedManager] setLanguageCode:code];
}

- (instancetype)init {
    @try {
        LWLog(@"LoginWindowController init (simple) called");
        return [self initWithServer:@"irc.oftc.net:6667"
                               nick:@""
                            channel:@"#i3chat"
                           realName:L(@"login.defaultRealName", @"macOS IRC Client")
                           password:@""
                       savePassword:NO
                             useTLS:NO];
    } @catch (NSException *exception) {
        LWLog(@"Fatal error in init: %@", exception);
        LWLog(@"Stack trace: %@", [exception callStackSymbols]);
        return nil;
    }
}

- (instancetype)initWithServer:(NSString *)server
                          nick:(NSString *)nick
                       channel:(NSString *)channel
                      realName:(NSString *)realName
                      password:(NSString *)password
                  savePassword:(BOOL)savePassword
                        useTLS:(BOOL)useTLS {
    @try {
        LWLog(@"LoginWindowController: Starting initialization");
        // Larger window to accommodate server list on the right
        NSRect screenRect = [[NSScreen mainScreen] frame];
        NSRect windowRect = NSMakeRect(
            (screenRect.size.width - 1000) / 2,
            (screenRect.size.height - 600) / 2,
            1000,
            600
        );
        
        NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                         backing:NSBackingStoreBuffered
                                                           defer:YES];
        if (!window) {
            LWLog(@"Error: Failed to create NSWindow");
            return nil;
        }
        
        [window setTitle:L(@"login.window.title", @"Connect to IRC Server")];
        [window setContentMinSize:NSMakeSize(1000, 600)];
        [window setContentMaxSize:NSMakeSize(1000, 600)];
        [window setDelegate:(id<NSWindowDelegate>)self];
        // Login window has a fixed light beach background; always use Aqua appearance
        // so text colors (labelColor etc.) resolve to dark and remain readable on the light cards.
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        
        LWLog(@"LoginWindowController: Window created");
        
        LWLog(@"LoginWindowController: Before super init");
        self = [super initWithWindow:window];
        LWLog(@"LoginWindowController: After super init, self=%@", self ? @"YES" : @"NO");
        
        if (!self) {
            LWLog(@"Error: Failed to initialize super");
            return nil;
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyLocalization)
                                                     name:LocalizationDidChangeNotification
                                                   object:nil];
        
        LWLog(@"LoginWindowController: Calling setupUIWithServer");
        @autoreleasepool {
            [self setupUIWithServer:server nick:nick channel:channel realName:realName password:password savePassword:savePassword useTLS:useTLS];
        }
        LWLog(@"LoginWindowController: setupUIWithServer completed");
        
        LWLog(@"LoginWindowController: About to return self, self.window=%@", self.window ? @"YES" : @"NO");
        LWLog(@"LoginWindowController: Returning self");
        return self;
    } @catch (NSException *exception) {
        LWLog(@"Fatal error in initWithServer: %@", exception);
        LWLog(@"Stack trace: %@", [exception callStackSymbols]);
        return nil;
    }
}

- (void)setupUIWithServer:(NSString *)server
                      nick:(NSString *)nick
                   channel:(NSString *)channel
                  realName:(NSString *)realName
                  password:(NSString *)password
              savePassword:(BOOL)savePassword
                    useTLS:(BOOL)useTLS {
    @try {
        LWLog(@"setupUIWithServer: Starting");
        if (!self.window) {
            LWLog(@"Error: self.window is nil");
            return;
        }
        
        NSView *contentView = self.window.contentView;
        if (!contentView) {
            LWLog(@"Error: window contentView is nil");
            return;
        }
        LWLog(@"setupUIWithServer: Got contentView");
        
        NSRect contentBounds = contentView.bounds;
    CGFloat windowHeight = contentBounds.size.height;
    CGFloat windowWidth = contentBounds.size.width;
    
    // Background image (if provided), else fallback to drawn sky + sea + sand
    NSView *backgroundView = [[NSView alloc] initWithFrame:contentBounds];
    backgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    backgroundView.wantsLayer = YES;
    NSString *bgPath = [[NSBundle mainBundle] pathForResource:@"background" ofType:@"png"];
    NSImage *bgImage = bgPath ? [[NSImage alloc] initWithContentsOfFile:bgPath] : nil;
    if (bgImage) {
        NSImageView *bgImageView = [[NSImageView alloc] initWithFrame:backgroundView.bounds];
        bgImageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        bgImageView.image = bgImage;
        bgImageView.imageScaling = NSImageScaleAxesIndependently;
        [backgroundView addSubview:bgImageView];
    } else {
        CAGradientLayer *skyGradient = [CAGradientLayer layer];
        skyGradient.frame = backgroundView.bounds;
        skyGradient.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        skyGradient.colors = @[
            (id)[[NSColor colorWithCalibratedRed:0.66 green:0.84 blue:0.97 alpha:1.0] CGColor],
            (id)[[NSColor colorWithCalibratedRed:0.74 green:0.89 blue:0.98 alpha:1.0] CGColor],
            (id)[[NSColor colorWithCalibratedRed:0.86 green:0.95 blue:1.0 alpha:1.0] CGColor]
        ];
        skyGradient.locations = @[@0.0, @0.40, @0.65];
        skyGradient.startPoint = CGPointMake(0.0, 1.0);
        skyGradient.endPoint = CGPointMake(0.0, 0.0);
        [backgroundView.layer addSublayer:skyGradient];

        CALayer *seaBand = [CALayer layer];
        seaBand.frame = CGRectMake(0, windowHeight * 0.36, windowWidth, windowHeight * 0.08);
        seaBand.backgroundColor = [[NSColor colorWithCalibratedRed:0.20 green:0.60 blue:0.85 alpha:1.0] CGColor];
        [backgroundView.layer addSublayer:seaBand];

        CAGradientLayer *seaGradient = [CAGradientLayer layer];
        seaGradient.frame = CGRectMake(0, windowHeight * 0.16, windowWidth, windowHeight * 0.26);
        seaGradient.colors = @[
            (id)[[NSColor colorWithCalibratedRed:0.24 green:0.66 blue:0.87 alpha:1.0] CGColor],
            (id)[[NSColor colorWithCalibratedRed:0.58 green:0.84 blue:0.95 alpha:1.0] CGColor]
        ];
        seaGradient.startPoint = CGPointMake(0.0, 1.0);
        seaGradient.endPoint = CGPointMake(0.0, 0.0);
        [backgroundView.layer addSublayer:seaGradient];

        CAGradientLayer *sandGradient = [CAGradientLayer layer];
        sandGradient.frame = CGRectMake(0, 0, windowWidth, windowHeight * 0.30);
        sandGradient.colors = @[
            (id)[[NSColor colorWithCalibratedRed:0.83 green:0.74 blue:0.54 alpha:1.0] CGColor],
            (id)[[NSColor colorWithCalibratedRed:0.91 green:0.84 blue:0.66 alpha:1.0] CGColor]
        ];
        sandGradient.startPoint = CGPointMake(0.0, 0.0);
        sandGradient.endPoint = CGPointMake(0.0, 1.0);
        [backgroundView.layer addSublayer:sandGradient];

        CAShapeLayer *cloudLayer = [CAShapeLayer layer];
        cloudLayer.frame = backgroundView.bounds;
        cloudLayer.fillColor = [[NSColor colorWithCalibratedWhite:1.0 alpha:0.55] CGColor];
        CGMutablePathRef cloudPath = CGPathCreateMutable();
        CGPathAddEllipseInRect(cloudPath, NULL, CGRectMake(40, windowHeight - 120, 140, 60));
        CGPathAddEllipseInRect(cloudPath, NULL, CGRectMake(120, windowHeight - 135, 160, 70));
        CGPathAddEllipseInRect(cloudPath, NULL, CGRectMake(220, windowHeight - 120, 140, 60));
        cloudLayer.path = cloudPath;
        CGPathRelease(cloudPath);
        [backgroundView.layer addSublayer:cloudLayer];

        CAShapeLayer *waveLayer = [CAShapeLayer layer];
        waveLayer.frame = backgroundView.bounds;
        waveLayer.fillColor = [[NSColor colorWithCalibratedWhite:1.0 alpha:0.55] CGColor];
        CGMutablePathRef wavePath = CGPathCreateMutable();
        CGFloat waveY = windowHeight * 0.26;
        CGPathMoveToPoint(wavePath, NULL, 0, waveY);
        CGPathAddCurveToPoint(wavePath, NULL, windowWidth * 0.25, waveY + 10, windowWidth * 0.35, waveY - 10, windowWidth * 0.5, waveY);
        CGPathAddCurveToPoint(wavePath, NULL, windowWidth * 0.65, waveY + 10, windowWidth * 0.75, waveY - 10, windowWidth, waveY);
        CGPathAddLineToPoint(wavePath, NULL, windowWidth, 0);
        CGPathAddLineToPoint(wavePath, NULL, 0, 0);
        CGPathCloseSubpath(wavePath);
        waveLayer.path = wavePath;
        CGPathRelease(wavePath);
        [backgroundView.layer addSublayer:waveLayer];

        CAShapeLayer *foamLayer = [CAShapeLayer layer];
        foamLayer.frame = backgroundView.bounds;
        foamLayer.strokeColor = [[NSColor colorWithCalibratedWhite:1.0 alpha:0.85] CGColor];
        foamLayer.fillColor = nil;
        foamLayer.lineWidth = 4.0;
        CGMutablePathRef foamPath = CGPathCreateMutable();
        CGFloat foamY = windowHeight * 0.20;
        CGPathMoveToPoint(foamPath, NULL, 0, foamY);
        CGPathAddCurveToPoint(foamPath, NULL, windowWidth * 0.30, foamY + 8, windowWidth * 0.45, foamY - 8, windowWidth * 0.6, foamY);
        CGPathAddCurveToPoint(foamPath, NULL, windowWidth * 0.75, foamY + 8, windowWidth * 0.85, foamY - 6, windowWidth, foamY);
        foamLayer.path = foamPath;
        CGPathRelease(foamPath);
        [backgroundView.layer addSublayer:foamLayer];
    }
    
    [contentView addSubview:backgroundView positioned:NSWindowBelow relativeTo:nil];
    
    // Left panel: Input form - manual layout
    CGFloat leftPanelWidth = 600;
    NSView *leftPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, leftPanelWidth, windowHeight)];
    leftPanel.autoresizingMask = NSViewHeightSizable;
    [contentView addSubview:leftPanel];
    LWLog(@"setupUIWithServer: Created leftPanel at (0, 0) size (%f, %f)", leftPanelWidth, windowHeight);
    
    CGFloat cardInset = 26;
    CGFloat leftCardWidth = leftPanelWidth - (cardInset * 2);
    CGFloat leftCardHeight = windowHeight - (cardInset * 2);
    self.leftCard = [[NSView alloc] initWithFrame:NSMakeRect(cardInset, cardInset, leftCardWidth, leftCardHeight)];
    self.leftCard.autoresizingMask = NSViewHeightSizable;
    [leftPanel addSubview:self.leftCard];
    [self applyCardStyleToView:self.leftCard];
    
    // Calculate positions from bottom (macOS uses bottom-left origin)
    CGFloat fieldHeight = 28;
    CGFloat labelHeight = 18;
    CGFloat spacing = 42;
    CGFloat outerPadding = 32;
    CGFloat labelWidth = 110;
    CGFloat fieldWidth = leftCardWidth - labelWidth - (outerPadding * 2) - 10;
    CGFloat headerHeight = 28;
    CGFloat headerY = leftCardHeight - outerPadding - headerHeight;
    
    NSTextField *headerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding, headerY, leftCardWidth - (outerPadding * 2), headerHeight)];
    headerLabel.bezeled = NO;
    headerLabel.drawsBackground = NO;
    headerLabel.editable = NO;
    headerLabel.selectable = NO;
    headerLabel.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
    headerLabel.textColor = [NSColor labelColor];
    headerLabel.stringValue = L(@"login.window.title", @"Connect to IRC Server");
    [self.leftCard addSubview:headerLabel];
    
    NSView *headerAccent = [[NSView alloc] initWithFrame:NSMakeRect(outerPadding, headerY - 6, 40, 4)];
    headerAccent.wantsLayer = YES;
    headerAccent.layer.backgroundColor = [[self brandColor] CGColor];
    headerAccent.layer.cornerRadius = 2.0;
    [self.leftCard addSubview:headerAccent];
    
    CGFloat startY = headerY - 20;
    
    // Server field (top) - macOS coordinates: y=0 is bottom
    CGFloat labelY = startY - labelHeight;
    CGFloat fieldY = startY - fieldHeight;
    
    self.serverLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding, labelY, labelWidth, labelHeight)];
    self.serverLabel.stringValue = L(@"login.label.server", @"Server:");
    [self styleLabel:self.serverLabel];
    [self.leftCard addSubview:self.serverLabel];
    LWLog(@"setupUIWithServer: Added serverLabel at y=%f (windowHeight=%f)", labelY, windowHeight);
    
    self.initialServerValue = server ?: @"";
    self.serverField = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding + labelWidth, fieldY, fieldWidth, fieldHeight)];
    self.serverField.stringValue = server ?: @"";
    self.serverField.placeholderString = L(@"login.placeholder.server", @"irc.example.net:6667, irc.libera.chat:6697");
    [self styleField:self.serverField];
    self.serverField.delegate = self;
    [self.leftCard addSubview:self.serverField];
    LWLog(@"setupUIWithServer: Added serverField at y=%f", fieldY);
    
    startY -= spacing;
    
    // Nick field
    startY -= spacing;
    labelY = startY - labelHeight;
    fieldY = startY - fieldHeight;
    
    self.nickLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding, labelY, labelWidth, labelHeight)];
    self.nickLabel.stringValue = L(@"login.label.nick", @"Nickname:");
    [self styleLabel:self.nickLabel];
    [self.leftCard addSubview:self.nickLabel];
    
    self.nickField = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding + labelWidth, fieldY, fieldWidth, fieldHeight)];
    self.nickField.stringValue = nick ?: @"";
    [self styleField:self.nickField];
    [self.leftCard addSubview:self.nickField];
    
    // Channel field
    startY -= spacing;
    labelY = startY - labelHeight;
    fieldY = startY - fieldHeight;
    
    self.channelLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding, labelY, labelWidth, labelHeight)];
    self.channelLabel.stringValue = L(@"login.label.channel", @"Channel:");
    [self styleLabel:self.channelLabel];
    [self.leftCard addSubview:self.channelLabel];
    
    self.channelField = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding + labelWidth, fieldY, fieldWidth, fieldHeight)];
    self.channelField.stringValue = channel ?: @"";
    [self styleField:self.channelField];
    [self.leftCard addSubview:self.channelField];
    
    // Real name field
    startY -= spacing;
    labelY = startY - labelHeight;
    fieldY = startY - fieldHeight;
    
    self.realNameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding, labelY, labelWidth, labelHeight)];
    self.realNameLabel.stringValue = L(@"login.label.realName", @"Real Name:");
    [self styleLabel:self.realNameLabel];
    [self.leftCard addSubview:self.realNameLabel];
    
    self.realNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding + labelWidth, fieldY, fieldWidth, fieldHeight)];
    self.realNameField.stringValue = realName ?: @"";
    [self styleField:self.realNameField];
    [self.leftCard addSubview:self.realNameField];
    
    // Language selector
    startY -= spacing;
    labelY = startY - labelHeight;
    fieldY = startY - fieldHeight;
    
    self.languageLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding, labelY, labelWidth, labelHeight)];
    self.languageLabel.stringValue = L(@"login.label.language", @"Language:");
    [self styleLabel:self.languageLabel];
    [self.leftCard addSubview:self.languageLabel];
    
    self.languagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(outerPadding + labelWidth, fieldY, fieldWidth, fieldHeight) pullsDown:NO];
    self.languagePopup.font = [NSFont systemFontOfSize:13];
    [self.languagePopup setTarget:self];
    [self.languagePopup setAction:@selector(languageSelectionChanged:)];
    [self.leftCard addSubview:self.languagePopup];
    [self configureLanguagePopup];
    
    // Password field
    startY -= spacing;
    labelY = startY - labelHeight;
    fieldY = startY - fieldHeight;
    
    self.passwordLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(outerPadding, labelY, labelWidth, labelHeight)];
    self.passwordLabel.stringValue = L(@"login.label.password", @"Password:");
    [self styleLabel:self.passwordLabel];
    [self.leftCard addSubview:self.passwordLabel];
    
    self.passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(outerPadding + labelWidth, fieldY, fieldWidth, fieldHeight)];
    self.passwordField.stringValue = password ?: @"";
    [self styleField:self.passwordField];
    [self.leftCard addSubview:self.passwordField];
    
    // Save password checkbox
    startY -= spacing;
    CGFloat checkboxY = startY - 20;
    
    self.savePasswordCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(outerPadding + labelWidth, checkboxY, 260, 20)];
    self.savePasswordCheckbox.buttonType = NSButtonTypeSwitch;
    self.savePasswordCheckbox.title = L(@"login.checkbox.savePassword", @"Save Password");
    self.savePasswordCheckbox.state = savePassword ? NSControlStateValueOn : NSControlStateValueOff;
    [self.leftCard addSubview:self.savePasswordCheckbox];
    
    // Use TLS checkbox
    startY -= spacing;
    checkboxY = startY - 20;
    
    self.useTLSCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(outerPadding + labelWidth, checkboxY, 260, 20)];
    self.useTLSCheckbox.buttonType = NSButtonTypeSwitch;
    self.useTLSCheckbox.title = L(@"login.checkbox.useTLS", @"Use TLS/SSL");
    self.useTLSCheckbox.state = useTLS ? NSControlStateValueOn : NSControlStateValueOff;
    [self.leftCard addSubview:self.useTLSCheckbox];
    if (server.length > 0) {
        [self updateTLSCheckboxFromServerAddress:server];
    }
    
    // Connect and Cancel buttons at bottom (with more space)
    // Position from bottom of leftPanel (macOS coordinates: y=0 is bottom)
    CGFloat buttonY = 24;
    CGFloat buttonHeight = 34;
    CGFloat buttonWidth = 104;
    CGFloat buttonShiftLeft = 120;
    CGFloat connectX = leftCardWidth - outerPadding - (buttonWidth * 2) - 12 - buttonShiftLeft;
    CGFloat cancelX = leftCardWidth - outerPadding - buttonWidth - buttonShiftLeft;
    self.connectButton = [[NSButton alloc] initWithFrame:NSMakeRect(connectX, buttonY, buttonWidth, buttonHeight)];
    self.connectButton.title = L(@"login.button.connect", @"Connect");
    self.connectButton.bezelStyle = NSBezelStyleRounded;
    [self.connectButton setTarget:self];
    [self.connectButton setAction:@selector(connect:)];
    self.connectButton.keyEquivalent = @"\r";
    if ([self.connectButton respondsToSelector:@selector(setContentTintColor:)]) {
        self.connectButton.contentTintColor = [self brandColor];
    }
    [self.leftCard addSubview:self.connectButton];
    LWLog(@"setupUIWithServer: Added connectButton at y=%f", buttonY);
    
    self.cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(cancelX, buttonY, buttonWidth, buttonHeight)];
    self.cancelButton.title = L(@"login.button.cancel", @"Cancel");
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    [self.cancelButton setTarget:self];
    [self.cancelButton setAction:@selector(cancel:)];
    self.cancelButton.keyEquivalent = @"\e";
    [self.leftCard addSubview:self.cancelButton];
    LWLog(@"setupUIWithServer: Added cancelButton at y=%f", buttonY);

    CGFloat supportX = NSMaxX(self.cancelButton.frame) + 12;
    CGFloat supportY = buttonY + 8;
    self.supportLinkButton = [[NSButton alloc] initWithFrame:NSMakeRect(supportX, supportY, 72, 18)];
    self.supportLinkButton.bordered = NO;
    self.supportLinkButton.buttonType = NSButtonTypeMomentaryPushIn;
    self.supportLinkButton.title = @"";
    [self.supportLinkButton setTarget:self];
    [self.supportLinkButton setAction:@selector(openSupportPage:)];
    self.supportLinkHovered = NO;
    [self updateSupportLinkButtonAppearance];
    [self configureSupportLinkTracking];
    [self.leftCard addSubview:self.supportLinkButton];
    
    // Make sure leftPanel is properly sized
    leftPanel.frame = NSMakeRect(0, 0, leftPanelWidth, windowHeight);
    
    // Right panel: Server list - manual layout on the right side
    CGFloat rightPanelX = leftPanelWidth;
    CGFloat rightPanelWidth = windowWidth - rightPanelX;
    
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSMakeRect(rightPanelX, 0, rightPanelWidth, windowHeight)];
    rightPanel.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:rightPanel];
    
    CGFloat rightCardInset = 26;
    CGFloat rightCardWidth = rightPanelWidth - (rightCardInset * 2);
    CGFloat rightCardHeight = windowHeight - (rightCardInset * 2);
    self.rightCard = [[NSView alloc] initWithFrame:NSMakeRect(rightCardInset, rightCardInset, rightCardWidth, rightCardHeight)];
    self.rightCard.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [rightPanel addSubview:self.rightCard];
    [self applyCardStyleToView:self.rightCard];
    
    CGFloat rightPadding = kServerListHeaderIndent;
    CGFloat rightHeaderHeight = 22;
    CGFloat rightHeaderGap = 10;
    
    NSScrollView *serverScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(rightPadding, rightPadding, rightCardWidth - (rightPadding * 2), rightCardHeight - rightPadding - rightHeaderHeight - rightHeaderGap - 8)];
    serverScrollView.hasVerticalScroller = YES;
    serverScrollView.borderType = NSNoBorder;
    serverScrollView.drawsBackground = YES;
    serverScrollView.backgroundColor = [NSColor textBackgroundColor];
    serverScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    serverScrollView.wantsLayer = YES;
    serverScrollView.layer.cornerRadius = 8.0;
    [self.rightCard addSubview:serverScrollView];
    
    self.serverListHeaderLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(rightPadding, rightCardHeight - rightPadding - rightHeaderHeight, rightCardWidth - (rightPadding * 2), rightHeaderHeight)];
    self.serverListHeaderLabel.bezeled = NO;
    self.serverListHeaderLabel.drawsBackground = NO;
    self.serverListHeaderLabel.editable = NO;
    self.serverListHeaderLabel.selectable = NO;
    self.serverListHeaderLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    self.serverListHeaderLabel.textColor = [self brandColor];
    self.serverListHeaderLabel.stringValue = L(@"login.serverList.title", @"Server List");
    self.serverListHeaderLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.rightCard addSubview:self.serverListHeaderLabel positioned:NSWindowAbove relativeTo:serverScrollView];
    
    // Server list table view
    LWLog(@"setupUIWithServer: Creating NSTableView");
    self.serverListView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, rightCardWidth - (rightPadding * 2), 100)];
    if (self.serverListView) {
        self.serverListColumn = [[NSTableColumn alloc] initWithIdentifier:@"Server"];
        if (self.serverListColumn) {
            self.serverListColumn.title = L(@"login.serverList.title", @"Server List");
            self.serverListColumn.width = rightCardWidth - (rightPadding * 2) - 20;
            [self.serverListView addTableColumn:self.serverListColumn];
        }
        self.serverListView.headerView = nil;
        self.serverListView.rowHeight = 26;
        self.serverListView.usesAlternatingRowBackgroundColors = YES;
        serverScrollView.documentView = self.serverListView;
        
        // Setup right-click context menu
        NSMenu *contextMenu = [[NSMenu alloc] initWithTitle:@""];
        contextMenu.delegate = self;
        self.serverListView.menu = contextMenu;
        
        // Set delegate and dataSource after a delay to ensure everything is ready
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                if (self.serverListView) {
                    self.serverListView.delegate = self;
                    self.serverListView.dataSource = self;
                    [self.serverListView reloadData];
                }
            } @catch (NSException *exception) {
                LWLog(@"Error setting table view delegate: %@", exception);
            }
        });
    }
    
    // Initialize with empty array - load history later
    self.historyServers = @[];
    
    // Load server history asynchronously to avoid blocking (with delay)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self refreshServerHistoryAndDefaultServer];
    });

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleServerHistoryUpdated:)
                                                 name:ServerHistoryDidUpdateNotification
                                               object:nil];
    
    // Default servers
    [self refreshDefaultServers];
    
    // Keep panel backgrounds transparent; cards provide structure.
    leftPanel.wantsLayer = YES;
    leftPanel.layer.backgroundColor = [[NSColor clearColor] CGColor];
    
    // Delay reloadData to ensure everything is initialized
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if (self.serverListView) {
                [self.serverListView reloadData];
            }
            // Force layout update
            [contentView setNeedsLayout:YES];
            [contentView layoutSubtreeIfNeeded];
        } @catch (NSException *exception) {
            LWLog(@"Error reloading server list: %@", exception);
        }
    });
    
    // Force display update
    [contentView setNeedsDisplay:YES];
    [leftPanel setNeedsDisplay:YES];
    [rightPanel setNeedsDisplay:YES];
    LWLog(@"setupUIWithServer: Completed successfully - leftPanel has %lu subviews", (unsigned long)leftPanel.subviews.count);
    [self applyLocalization];
    } @catch (NSException *exception) {
        LWLog(@"Error in setupUIWithServer: %@", exception);
        LWLog(@"Stack trace: %@", [exception callStackSymbols]);
    }
}

- (void)handleServerHistoryUpdated:(NSNotification *)notification {
    [self refreshServerHistoryAndDefaultServer];
}

- (void)refreshDefaultServers {
    self.defaultServers = @[
        // Top 10 most popular IRC networks worldwide + TLS variants
        @{@"name": L(@"login.defaultServer.libera", @"1. Libera.Chat - Open Source Community"), @"addr": @"irc.libera.chat:6667"},
        @{@"name": L(@"login.defaultServer.liberaTLS", @"   Libera.Chat (TLS/SSL)"), @"addr": @"irc.libera.chat:6697"},
        @{@"name": L(@"login.defaultServer.oftc", @"2. OFTC - Free Software Community"), @"addr": @"irc.oftc.net:6667"},
        @{@"name": L(@"login.defaultServer.oftcTLS", @"   OFTC (TLS/SSL)"), @"addr": @"irc.oftc.net:6697"},
        @{@"name": L(@"login.defaultServer.efnet", @"3. EFnet - Original IRC Network"), @"addr": @"irc.efnet.org:6667"},
        @{@"name": L(@"login.defaultServer.undernet", @"4. Undernet - Second Oldest Network"), @"addr": @"irc.undernet.org:6667"},
        @{@"name": L(@"login.defaultServer.dalnet", @"5. DALnet - Classic IRC Network"), @"addr": @"irc.dal.net:6667"},
        @{@"name": L(@"login.defaultServer.dalnetTLS", @"   DALnet (TLS/SSL)"), @"addr": @"irc.dal.net:6697"},
        @{@"name": L(@"login.defaultServer.quakenet", @"6. QuakeNet - Gaming Community"), @"addr": @"irc.quakenet.org:6667"},
        @{@"name": L(@"login.defaultServer.ircnet", @"7. IRCnet - European Network"), @"addr": @"irc.ircnet.com:6667"},
        @{@"name": L(@"login.defaultServer.rizon", @"8. Rizon - Anime & East Asian Community"), @"addr": @"irc.rizon.net:6667"},
        @{@"name": L(@"login.defaultServer.snoonet", @"9. Snoonet - Reddit Community"), @"addr": @"irc.snoonet.org:6667"},
        @{@"name": L(@"login.defaultServer.hackint", @"10. hackint - Hacker Community"), @"addr": @"irc.hackint.org:6667"},
    ];
}

- (void)applyLocalization {
    if (self.window) {
        [self.window setTitle:L(@"login.window.title", @"Connect to IRC Server")];
    }
    if (self.serverLabel) {
        self.serverLabel.stringValue = L(@"login.label.server", @"Server:");
    }
    if (self.nickLabel) {
        self.nickLabel.stringValue = L(@"login.label.nick", @"Nickname:");
    }
    if (self.channelLabel) {
        self.channelLabel.stringValue = L(@"login.label.channel", @"Channel:");
    }
    if (self.realNameLabel) {
        self.realNameLabel.stringValue = L(@"login.label.realName", @"Real Name:");
    }
    if (self.languageLabel) {
        self.languageLabel.stringValue = L(@"login.label.language", @"Language:");
    }
    if (self.passwordLabel) {
        self.passwordLabel.stringValue = L(@"login.label.password", @"Password:");
    }
    if (self.serverField) {
        self.serverField.placeholderString = L(@"login.placeholder.server", @"irc.example.net:6667, irc.libera.chat:6697");
    }
    if (self.savePasswordCheckbox) {
        self.savePasswordCheckbox.title = L(@"login.checkbox.savePassword", @"Save Password");
    }
    if (self.useTLSCheckbox) {
        self.useTLSCheckbox.title = L(@"login.checkbox.useTLS", @"Use TLS/SSL");
    }
    if (self.connectButton) {
        self.connectButton.title = L(@"login.button.connect", @"Connect");
    }
    if (self.cancelButton) {
        self.cancelButton.title = L(@"login.button.cancel", @"Cancel");
    }
    [self updateSupportLinkButtonAppearance];
    if (self.serverListColumn) {
        self.serverListColumn.title = L(@"login.serverList.title", @"Server List");
    }
    if (self.serverListHeaderLabel) {
        self.serverListHeaderLabel.stringValue = L(@"login.serverList.title", @"Server List");
    }
    [self configureLanguagePopup];
    [self refreshDefaultServers];
    if (self.serverListView) {
        [self.serverListView reloadData];
    }
}

- (void)refreshServerHistoryAndDefaultServer {
    LWLog(@"refreshServerHistoryAndDefaultServer: Starting");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            ServerHistoryStorage *storage = [ServerHistoryStorage sharedStorage];
            LWLog(@"refreshServerHistoryAndDefaultServer: Got storage: %@", storage ? @"YES" : @"NO");
            NSArray<NSString *> *history = storage ? [storage getServerHistoryWithLimit:10] : @[];
            LWLog(@"refreshServerHistoryAndDefaultServer: Got %lu history servers", (unsigned long)history.count);
            for (NSString *server in history) {
                LWLog(@"refreshServerHistoryAndDefaultServer: History server: %@", server);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    self.historyServers = history ?: @[];
                    LWLog(@"refreshServerHistoryAndDefaultServer: Set historyServers count: %lu", (unsigned long)self.historyServers.count);
                    if (self.serverListView) {
                        [self.serverListView reloadData];
                        LWLog(@"refreshServerHistoryAndDefaultServer: Reloaded server list view");
                    }
                    if (self.historyServers.count > 0 && self.serverField) {
                        BOOL shouldUpdateDefault = (self.serverField.currentEditor == nil);
                        NSString *currentValue = self.serverField.stringValue ?: @"";
                        if (self.initialServerValue.length > 0 && currentValue.length > 0 &&
                            ![currentValue isEqualToString:self.initialServerValue]) {
                            shouldUpdateDefault = NO;
                        }
                        if (shouldUpdateDefault) {
                            NSString *addr = self.historyServers[0];
                            self.serverField.stringValue = addr;
                            [self updateTLSCheckboxFromServerAddress:addr];
                            LWLog(@"refreshServerHistoryAndDefaultServer: Set server field to %@", addr);
                        }
                    }
                } @catch (NSException *exception) {
                    LWLog(@"Error updating server list: %@", exception);
                }
            });
        } @catch (NSException *exception) {
            LWLog(@"Error loading server history: %@", exception);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.historyServers = @[];
                if (self.serverListView) {
                    [self.serverListView reloadData];
                }
            });
        }
    });
}

#pragma mark - NSTableViewDataSource

- (NSInteger)serverListRowTypeForRow:(NSInteger)row historyCount:(NSInteger)historyCount defaultCount:(NSInteger)defaultCount {
    if (historyCount > 0) {
        if (row == 0) return 0; // history header
        if (row <= historyCount) return 2; // history item
        if (row == historyCount + 1) return 1; // spacer
        if (row == historyCount + 2) return 0; // recommended header
        return 3; // default item
    }
    if (row == 0) return 0; // recommended header
    return 3; // default item
}

- (BOOL)isServerListHeaderRow:(NSInteger)row historyCount:(NSInteger)historyCount defaultCount:(NSInteger)defaultCount {
    return [self serverListRowTypeForRow:row historyCount:historyCount defaultCount:defaultCount] == 0;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    @try {
        NSInteger historyCount = self.historyServers ? self.historyServers.count : 0;
        NSInteger defaultCount = self.defaultServers ? self.defaultServers.count : 0;
        return historyCount + (historyCount > 0 ? 2 : 1) + defaultCount; // +2 for headers, +1 if no history
    } @catch (NSException *exception) {
        LWLog(@"Error in numberOfRowsInTableView: %@", exception);
        return 0;
    }
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    @try {
        NSInteger historyCount = self.historyServers ? self.historyServers.count : 0;
        NSInteger defaultCount = self.defaultServers ? self.defaultServers.count : 0;
        
        if (historyCount > 0) {
            if (row == 0) {
                return L(@"login.serverList.historyHeader", @"History Servers");
            } else if (row <= historyCount) {
                return self.historyServers[row - 1];
            } else if (row == historyCount + 1) {
                return @"";
            } else if (row == historyCount + 2) {
                return L(@"login.serverList.recommendedHeader", @"Recommended Servers");
            } else {
                NSInteger defaultIndex = row - historyCount - 3;
                if (defaultIndex >= 0 && defaultIndex < defaultCount) {
                    return self.defaultServers[defaultIndex][@"name"];
                }
            }
        } else {
            if (row == 0) {
                return L(@"login.serverList.recommendedHeader", @"Recommended Servers");
            } else {
                NSInteger defaultIndex = row - 1;
                if (defaultIndex >= 0 && defaultIndex < defaultCount) {
                    return self.defaultServers[defaultIndex][@"name"];
                }
            }
        }
        
        return @"";
    } @catch (NSException *exception) {
        LWLog(@"Error in objectValueForTableColumn: %@", exception);
        return @"";
    }
}

#pragma mark - NSTableViewDelegate

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSInteger historyCount = self.historyServers ? self.historyServers.count : 0;
    NSInteger defaultCount = self.defaultServers ? self.defaultServers.count : 0;
    NSInteger rowType = [self serverListRowTypeForRow:row historyCount:historyCount defaultCount:defaultCount];
    if (rowType == 0) {
        return 24;
    }
    if (rowType == 1) {
        return 14;
    }
    return 28;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    NSInteger historyCount = self.historyServers ? self.historyServers.count : 0;
    NSInteger defaultCount = self.defaultServers ? self.defaultServers.count : 0;
    NSInteger rowType = [self serverListRowTypeForRow:row historyCount:historyCount defaultCount:defaultCount];
    return rowType == 2 || rowType == 3;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSInteger historyCount = self.historyServers ? self.historyServers.count : 0;
    NSInteger defaultCount = self.defaultServers ? self.defaultServers.count : 0;
    NSInteger rowType = [self serverListRowTypeForRow:row historyCount:historyCount defaultCount:defaultCount];
    
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"ServerCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 28)];
        cell.identifier = @"ServerCell";
        
        NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(8, 5, 16, 16)];
        iconView.imageScaling = NSImageScaleProportionallyDown;
        iconView.tag = 1001;
        [cell addSubview:iconView];
        
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(30, 3, tableView.bounds.size.width - 36, 22)];
        textField.bezeled = NO;
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.selectable = NO;
        textField.tag = 1002;
        [cell addSubview:textField];
        
        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(kServerListHeaderIndent, 12, tableView.bounds.size.width - kServerListHeaderIndent - 12, 1)];
        separator.boxType = NSBoxSeparator;
        separator.hidden = YES;
        [cell addSubview:separator];
    }
    
    NSImageView *iconView = [cell viewWithTag:1001];
    NSTextField *textField = [cell viewWithTag:1002];
    NSBox *separator = nil;
    for (NSView *subview in cell.subviews) {
        if ([subview isKindOfClass:[NSBox class]]) {
            separator = (NSBox *)subview;
            break;
        }
    }
    iconView.hidden = NO;
    if (separator) {
        separator.hidden = YES;
    }
    
    if (rowType == 1) {
        textField.stringValue = @"";
        iconView.hidden = YES;
        textField.frame = NSMakeRect(kServerListHeaderIndent, 3, tableView.bounds.size.width - kServerListHeaderIndent - 6, 22);
        if (separator) {
            separator.hidden = NO;
            separator.frame = NSMakeRect(kServerListHeaderIndent, 12, tableView.bounds.size.width - kServerListHeaderIndent - 12, 1);
        }
        return cell;
    }
    
    if (rowType == 0) {
        NSString *headerTitle = @"";
        if (historyCount > 0) {
            if (row == 0) headerTitle = L(@"login.serverList.historyHeader", @"History Servers");
            else headerTitle = L(@"login.serverList.recommendedHeader", @"Recommended Servers");
        } else {
            headerTitle = L(@"login.serverList.recommendedHeader", @"Recommended Servers");
        }
        textField.stringValue = headerTitle;
        textField.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        textField.textColor = [NSColor secondaryLabelColor];
        iconView.hidden = YES;
        textField.frame = NSMakeRect(kServerListHeaderIndent, 3, tableView.bounds.size.width - kServerListHeaderIndent - 6, 22);
        return cell;
    }
    
    NSString *title = @"";
    if (rowType == 2) {
        title = self.historyServers[row - 1] ?: @"";
    } else {
        NSInteger defaultIndex = (historyCount > 0) ? (row - historyCount - 3) : (row - 1);
        if (defaultIndex >= 0 && defaultIndex < defaultCount) {
            title = self.defaultServers[defaultIndex][@"name"] ?: @"";
        }
    }
    
    textField.stringValue = title;
    textField.font = [NSFont systemFontOfSize:13];
    textField.textColor = [NSColor labelColor];
    textField.frame = NSMakeRect(30, 3, tableView.bounds.size.width - 36, 22);
    
    NSImage *icon = nil;
    if (@available(macOS 11.0, *)) {
        if ([title rangeOfString:@"TLS" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [title rangeOfString:@"SSL" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            icon = [NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:nil];
        } else if (rowType == 2) {
            icon = [NSImage imageWithSystemSymbolName:@"clock.fill" accessibilityDescription:nil];
        } else {
            icon = [NSImage imageWithSystemSymbolName:@"sparkles" accessibilityDescription:nil];
        }
    }
    iconView.image = icon;
    if ([iconView respondsToSelector:@selector(setContentTintColor:)]) {
        iconView.contentTintColor = [self brandColor];
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    @try {
        if (!self.serverListView || !self.serverField) {
            return;
        }
        
        NSInteger selectedRow = self.serverListView.selectedRow;
        if (selectedRow < 0) {
            return;
        }
        
        NSInteger historyCount = self.historyServers ? self.historyServers.count : 0;
        NSInteger defaultCount = self.defaultServers ? self.defaultServers.count : 0;
        NSString *serverAddr = nil;
        
        if (historyCount > 0) {
            if (selectedRow > 0 && selectedRow <= historyCount) {
                // History server
                serverAddr = self.historyServers[selectedRow - 1];
            } else if (selectedRow > historyCount + 2) {
                // Default server
                NSInteger defaultIndex = selectedRow - historyCount - 3;
                if (defaultIndex >= 0 && defaultIndex < defaultCount) {
                    serverAddr = self.defaultServers[defaultIndex][@"addr"];
                }
            }
        } else {
            if (selectedRow > 0) {
                // Default server
                NSInteger defaultIndex = selectedRow - 1;
                if (defaultIndex >= 0 && defaultIndex < defaultCount) {
                    serverAddr = self.defaultServers[defaultIndex][@"addr"];
                }
            }
        }
        
        if (serverAddr && self.serverField) {
            self.serverField.stringValue = serverAddr;
            [self updateTLSCheckboxFromServerAddress:serverAddr];
            [self.window makeFirstResponder:self.serverField];
        }
    } @catch (NSException *exception) {
        LWLog(@"Error in tableViewSelectionDidChange: %@", exception);
    }
}

#pragma mark - NSMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    
    if (menu != self.serverListView.menu) {
        return;
    }
    
    // Get the clicked row
    NSPoint clickPoint = [self.serverListView convertPoint:[self.serverListView.window mouseLocationOutsideOfEventStream] fromView:nil];
    NSInteger clickedRow = [self.serverListView rowAtPoint:clickPoint];
    
    if (clickedRow < 0) {
        return;
    }
    
    // Check if this is a history server row (not header, not default servers)
    NSInteger historyCount = self.historyServers ? self.historyServers.count : 0;
    
    // Row 0 is "History Servers" header, rows 1 to historyCount are history servers
    if (historyCount > 0 && clickedRow > 0 && clickedRow <= historyCount) {
        NSString *serverAddr = self.historyServers[clickedRow - 1];
        
        // Select the row
        [self.serverListView selectRowIndexes:[NSIndexSet indexSetWithIndex:clickedRow] byExtendingSelection:NO];
        
        // Add delete menu item
        NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:L(@"login.menu.deleteServer", @"Delete from History")
                                                            action:@selector(deleteServerFromHistory:)
                                                     keyEquivalent:@""];
        deleteItem.target = self;
        deleteItem.representedObject = serverAddr;
        [menu addItem:deleteItem];
    }
}

- (void)deleteServerFromHistory:(NSMenuItem *)sender {
    NSString *serverAddr = sender.representedObject;
    if (!serverAddr || serverAddr.length == 0) {
        return;
    }
    
    // Confirm deletion
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = L(@"login.alert.deleteServer.title", @"Delete Server");
    alert.informativeText = [NSString stringWithFormat:L(@"login.alert.deleteServer.message", @"Are you sure you want to delete \"%@\" from history?"), serverAddr];
    [alert addButtonWithTitle:L(@"common.delete", @"Delete")];
    [alert addButtonWithTitle:L(@"common.cancel", @"Cancel")];
    alert.alertStyle = NSAlertStyleWarning;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        // Delete from storage
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL success = [[ServerHistoryStorage sharedStorage] deleteServerFromHistory:serverAddr];
            if (success) {
                LWLog(@"Successfully deleted server %@ from history", serverAddr);
                // Refresh will happen via notification
            } else {
                LWLog(@"Failed to delete server %@ from history", serverAddr);
            }
        });
    }
}

- (void)updateTLSCheckboxFromServerAddress:(NSString *)addr {
    if (!addr || addr.length == 0 || !self.useTLSCheckbox) return;
    if ([addr hasSuffix:@":6697"]) {
        self.useTLSCheckbox.state = NSControlStateValueOn;
    } else if ([addr hasSuffix:@":6667"]) {
        self.useTLSCheckbox.state = NSControlStateValueOff;
    }
}

- (BOOL)useTLSFromServerAddress:(NSString *)addr defaultFromCheckbox:(BOOL)checkboxValue {
    if (!addr || addr.length == 0) return checkboxValue;
    if ([addr hasSuffix:@":6697"]) return YES;
    if ([addr hasSuffix:@":6667"]) return NO;
    return checkboxValue;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.serverField && self.serverField.stringValue.length > 0) {
        [self updateTLSCheckboxFromServerAddress:self.serverField.stringValue];
    }
}

- (void)connect:(id)sender {
    NSString *serverInput = [self.serverField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *nick = [self.nickField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *channel = [self.channelField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *realName = [self.realNameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *password = self.passwordField.stringValue;
    BOOL savePassword = (self.savePasswordCheckbox.state == NSControlStateValueOn);
    BOOL checkboxTLS = (self.useTLSCheckbox.state == NSControlStateValueOn);
    
    if (serverInput.length == 0 || nick.length == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = L(@"login.alert.invalidInput.title", @"Invalid Input");
        alert.informativeText = L(@"login.alert.requiredFields", @"Server and Nickname are required.");
        [alert runModal];
        return;
    }
    
    if (channel.length == 0) {
        channel = @"#i3chat";
    }
    if (realName.length == 0) {
        realName = L(@"login.defaultRealName", @"macOS IRC Client");
    }
    
    NSArray<NSString *> *rawServers = [serverInput componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",;\n\t "]];
    NSMutableArray<NSString *> *servers = [[NSMutableArray alloc] init];
    for (NSString *rawServer in rawServers) {
        NSString *trimmed = [rawServer stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0 && ![servers containsObject:trimmed]) {
            [servers addObject:trimmed];
        }
    }
    
    if (servers.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = L(@"login.alert.invalidInput.title", @"Invalid Input");
        alert.informativeText = L(@"login.alert.noServer", @"Please provide at least one server.");
        [alert runModal];
        return;
    }
    
    NSMutableArray<IRCConfig *> *configs = [[NSMutableArray alloc] initWithCapacity:servers.count];
    for (NSString *server in servers) {
        BOOL useTLS = [self useTLSFromServerAddress:server defaultFromCheckbox:checkboxTLS];
        IRCConfig *config = [[IRCConfig alloc] initWithServer:server
                                                         nick:nick
                                                         user:@"macirc"
                                                     realName:realName
                                                      channel:channel
                                                     password:password.length > 0 ? password : nil
                                                       useTLS:useTLS];
        [configs addObject:config];
        
        [[ServerHistoryStorage sharedStorage] saveLoginHistoryWithServer:server
                                                                     nick:nick
                                                                  channel:channel
                                                                 realName:realName
                                                                 password:password
                                                             savePassword:savePassword
                                                                   useTLS:useTLS];
    }
    
    if ([self.delegate respondsToSelector:@selector(loginWindowController:didLoginWithConfigs:)]) {
        self.didLoginSuccessfully = YES;
        [self.delegate loginWindowController:self didLoginWithConfigs:configs];
    }
}

- (void)cancel:(id)sender {
    [NSApp terminate:nil];
}

- (void)openSupportPage:(id)sender {
    NSURL *supportURL = [NSURL URLWithString:@"https://github.com/chat-client/i3chat"];
    if (!supportURL) {
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:supportURL];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    // When login window is closed (via close button), terminate the app
    // But only if user hasn't successfully logged in
    if (notification.object == self.window && !self.didLoginSuccessfully) {
        [NSApp terminate:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
