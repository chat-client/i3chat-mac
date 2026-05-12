//
//  SettingsWindowController.m
//  i3Chat
//

#import "SettingsWindowController.h"
#import "DebugLog.h"
#import "LocalizationManager.h"
#import "MessageStorage.h"
#import "StorageConstants.h"

// Legacy keys for migration
static NSString * const LegacyShowLogWindowOnStartupKey = @"ShowLogWindowOnStartup";
static NSString * const LegacyShowChannelColorsKey = @"ShowChannelColors";

@interface SettingsWindowController () <NSWindowDelegate, NSTextFieldDelegate>

@property (nonatomic, strong) NSButton *showLogWindowOnStartupCheckbox;
@property (nonatomic, strong) NSButton *showChannelColorsCheckbox;
@property (nonatomic, strong) NSTextField *maxMessagesLabel;
@property (nonatomic, strong) NSTextField *maxMessagesTextField;
@property (nonatomic, strong) NSStepper *maxMessagesStepper;
@property (nonatomic, strong) NSTextField *lineSpacingLabel;
@property (nonatomic, strong) NSTextField *lineSpacingTextField;
@property (nonatomic, strong) NSStepper *lineSpacingStepper;
@property (nonatomic, strong) NSButton *okButton;
@property (nonatomic, strong) NSButton *cancelButton;

@end

@implementation SettingsWindowController

- (instancetype)init {
    // Create window
    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSRect windowRect = NSMakeRect(
        (screenRect.size.width - 560) / 2,
        (screenRect.size.height - 420) / 2,
        560,
        420
    );
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:L(@"settings.window.title", @"Settings")];
    [window setMinSize:NSMakeSize(460, 360)];
    [window setDelegate:self];
    
    // Set window level to floating
    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    [window setHidesOnDeactivate:NO];
    
    self = [super initWithWindow:window];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyLocalization)
                                                     name:LocalizationDidChangeNotification
                                                   object:nil];
        
        [self setupUI];
        [self loadSettings];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    // Ensure contentView is ready for interaction
    if (!contentView) {
        NSLog(@"🔧 [SETTINGS WINDOW] ERROR: contentView is nil!");
        return;
    }
    
    // Create settings container (Auto Layout)
    NSView *settingsContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    settingsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:settingsContainer];
    
    // Show log window on startup checkbox
    self.showLogWindowOnStartupCheckbox = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.showLogWindowOnStartupCheckbox.buttonType = NSButtonTypeSwitch;
    self.showLogWindowOnStartupCheckbox.title = L(@"settings.showLogWindowOnStartup", @"Show log window on startup");
    self.showLogWindowOnStartupCheckbox.target = self;
    self.showLogWindowOnStartupCheckbox.action = @selector(showLogWindowOnStartupChanged:);
    self.showLogWindowOnStartupCheckbox.enabled = YES;
    self.showLogWindowOnStartupCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Show channel colors checkbox
    self.showChannelColorsCheckbox = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.showChannelColorsCheckbox.buttonType = NSButtonTypeSwitch;
    self.showChannelColorsCheckbox.title = L(@"settings.showChannelColors", @"Show channel colors");
    self.showChannelColorsCheckbox.target = self;
    self.showChannelColorsCheckbox.action = @selector(showChannelColorsChanged:);
    self.showChannelColorsCheckbox.enabled = YES;
    self.showChannelColorsCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Max messages per channel label
    self.maxMessagesLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.maxMessagesLabel.bezeled = NO;
    self.maxMessagesLabel.drawsBackground = NO;
    self.maxMessagesLabel.editable = NO;
    self.maxMessagesLabel.selectable = NO;
    self.maxMessagesLabel.stringValue = L(@"settings.maxMessagesPerChannel", @"Max messages per channel:");
    self.maxMessagesLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Max messages text field
    self.maxMessagesTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.maxMessagesTextField.bezeled = YES;
    self.maxMessagesTextField.bezelStyle = NSTextFieldSquareBezel;
    self.maxMessagesTextField.editable = YES;
    self.maxMessagesTextField.enabled = YES;
    self.maxMessagesTextField.delegate = self;
    self.maxMessagesTextField.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Set number formatter
    // Allow 0 to mean "never delete messages" (unlimited)
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimum = @0; // Changed from 100 to 0 to allow unlimited
    formatter.maximum = @50000;
    formatter.allowsFloats = NO;
    self.maxMessagesTextField.formatter = formatter;
    
    // Max messages stepper
    // Allow 0 to mean "never delete messages" (unlimited)
    self.maxMessagesStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    self.maxMessagesStepper.minValue = 0; // Changed from 100 to 0 to allow unlimited
    self.maxMessagesStepper.maxValue = 50000;
    self.maxMessagesStepper.increment = 100;
    self.maxMessagesStepper.valueWraps = NO;
    self.maxMessagesStepper.autorepeat = YES;
    self.maxMessagesStepper.enabled = YES;
    self.maxMessagesStepper.target = self;
    self.maxMessagesStepper.action = @selector(maxMessagesStepperChanged:);
    self.maxMessagesStepper.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Message line spacing label
    self.lineSpacingLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.lineSpacingLabel.bezeled = NO;
    self.lineSpacingLabel.drawsBackground = NO;
    self.lineSpacingLabel.editable = NO;
    self.lineSpacingLabel.selectable = NO;
    self.lineSpacingLabel.stringValue = L(@"settings.messageLineSpacing", @"Message line spacing:");
    self.lineSpacingLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // Message line spacing text field
    self.lineSpacingTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.lineSpacingTextField.bezeled = YES;
    self.lineSpacingTextField.bezelStyle = NSTextFieldSquareBezel;
    self.lineSpacingTextField.editable = YES;
    self.lineSpacingTextField.enabled = YES;
    self.lineSpacingTextField.delegate = self;
    self.lineSpacingTextField.translatesAutoresizingMaskIntoConstraints = NO;
    NSNumberFormatter *spacingFormatter = [[NSNumberFormatter alloc] init];
    spacingFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    spacingFormatter.minimum = @0;
    spacingFormatter.maximum = @20;
    spacingFormatter.allowsFloats = NO;
    self.lineSpacingTextField.formatter = spacingFormatter;
    
    // Message line spacing stepper
    self.lineSpacingStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    self.lineSpacingStepper.minValue = 0;
    self.lineSpacingStepper.maxValue = 20;
    self.lineSpacingStepper.increment = 1;
    self.lineSpacingStepper.valueWraps = NO;
    self.lineSpacingStepper.autorepeat = YES;
    self.lineSpacingStepper.enabled = YES;
    self.lineSpacingStepper.target = self;
    self.lineSpacingStepper.action = @selector(lineSpacingStepperChanged:);
    self.lineSpacingStepper.translatesAutoresizingMaskIntoConstraints = NO;
    
    // OK button
    self.okButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.okButton.buttonType = NSButtonTypeMomentaryPushIn;
    self.okButton.bezelStyle = NSBezelStyleRounded;
    self.okButton.title = L(@"settings.button.ok", @"OK");
    self.okButton.enabled = YES;
    self.okButton.target = self;
    self.okButton.action = @selector(okButtonClicked:);
    self.okButton.keyEquivalent = @"\r";
    self.okButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Cancel button
    self.cancelButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.cancelButton.buttonType = NSButtonTypeMomentaryPushIn;
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.title = L(@"settings.button.cancel", @"Cancel");
    self.cancelButton.enabled = YES;
    self.cancelButton.target = self;
    self.cancelButton.action = @selector(cancelButtonClicked:);
    self.cancelButton.keyEquivalent = @"\e";
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Horizontal stacks for row inputs
    NSStackView *maxMessagesRow = [NSStackView stackViewWithViews:@[
        self.maxMessagesLabel, self.maxMessagesTextField, self.maxMessagesStepper
    ]];
    maxMessagesRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    maxMessagesRow.alignment = NSLayoutAttributeCenterY;
    maxMessagesRow.spacing = 8.0;
    
    NSStackView *lineSpacingRow = [NSStackView stackViewWithViews:@[
        self.lineSpacingLabel, self.lineSpacingTextField, self.lineSpacingStepper
    ]];
    lineSpacingRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    lineSpacingRow.alignment = NSLayoutAttributeCenterY;
    lineSpacingRow.spacing = 8.0;
    
    // Vertical stack for settings
    NSStackView *settingsStack = [NSStackView stackViewWithViews:@[
        self.showLogWindowOnStartupCheckbox,
        self.showChannelColorsCheckbox,
        maxMessagesRow,
        lineSpacingRow
    ]];
    settingsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    settingsStack.alignment = NSLayoutAttributeLeading;
    settingsStack.spacing = 16.0;
    settingsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [settingsContainer addSubview:settingsStack];
    
    // Buttons stack
    NSStackView *buttonsStack = [NSStackView stackViewWithViews:@[self.cancelButton, self.okButton]];
    buttonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonsStack.alignment = NSLayoutAttributeCenterY;
    buttonsStack.spacing = 12.0;
    buttonsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:buttonsStack];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [settingsContainer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20.0],
        [settingsContainer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20.0],
        [settingsContainer.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20.0],
        [settingsContainer.bottomAnchor constraintEqualToAnchor:buttonsStack.topAnchor constant:-20.0],
        
        [settingsStack.leadingAnchor constraintEqualToAnchor:settingsContainer.leadingAnchor],
        [settingsStack.trailingAnchor constraintLessThanOrEqualToAnchor:settingsContainer.trailingAnchor],
        [settingsStack.topAnchor constraintEqualToAnchor:settingsContainer.topAnchor],
        [settingsStack.bottomAnchor constraintLessThanOrEqualToAnchor:settingsContainer.bottomAnchor],
        
        [self.maxMessagesLabel.widthAnchor constraintEqualToConstant:220.0],
        [self.lineSpacingLabel.widthAnchor constraintEqualToConstant:220.0],
        [self.maxMessagesTextField.widthAnchor constraintEqualToConstant:100.0],
        [self.lineSpacingTextField.widthAnchor constraintEqualToConstant:100.0],
        [self.maxMessagesStepper.widthAnchor constraintEqualToConstant:24.0],
        [self.lineSpacingStepper.widthAnchor constraintEqualToConstant:24.0],
        
        [buttonsStack.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [buttonsStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20.0]
    ]];
    
    [self applyLocalization];
}

- (void)applyLocalization {
    if (self.window) {
        [self.window setTitle:L(@"settings.window.title", @"Settings")];
    }
    if (self.showLogWindowOnStartupCheckbox) {
        self.showLogWindowOnStartupCheckbox.title = L(@"settings.showLogWindowOnStartup", @"Show log window on startup");
    }
    if (self.showChannelColorsCheckbox) {
        self.showChannelColorsCheckbox.title = L(@"settings.showChannelColors", @"Show channel colors");
    }
    if (self.maxMessagesLabel) {
        self.maxMessagesLabel.stringValue = L(@"settings.maxMessagesPerChannel", @"Max messages per channel:");
    }
    if (self.lineSpacingLabel) {
        self.lineSpacingLabel.stringValue = L(@"settings.messageLineSpacing", @"Message line spacing:");
    }
    if (self.okButton) {
        self.okButton.title = L(@"settings.button.ok", @"OK");
    }
    if (self.cancelButton) {
        self.cancelButton.title = L(@"settings.button.cancel", @"Cancel");
    }
}

- (void)migrateSettingsFromUserDefaultsIfNeeded {
    MessageStorage *storage = [MessageStorage sharedStorage];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Migrate show log window on startup
    if (![storage getSettingForKey:kSettingShowLogWindowOnStartup]) {
        id legacyValue = [defaults objectForKey:LegacyShowLogWindowOnStartupKey];
        if (legacyValue) {
            [storage setSettingForKey:kSettingShowLogWindowOnStartup value:[legacyValue boolValue] ? @"1" : @"0"];
            [defaults removeObjectForKey:LegacyShowLogWindowOnStartupKey];
        }
    }
    
    // Migrate show channel colors
    if (![storage getSettingForKey:kSettingShowChannelColors]) {
        id legacyValue = [defaults objectForKey:LegacyShowChannelColorsKey];
        if (legacyValue) {
            [storage setSettingForKey:kSettingShowChannelColors value:[legacyValue boolValue] ? @"1" : @"0"];
            [defaults removeObjectForKey:LegacyShowChannelColorsKey];
        }
    }
    
    [defaults synchronize];
}

- (void)loadSettings {
    NSLog(@"🔧 [SETTINGS WINDOW] loadSettings called");
    [self migrateSettingsFromUserDefaultsIfNeeded];
    
    MessageStorage *storage = [MessageStorage sharedStorage];
    
    // Load show log window on startup (default: NO for first install)
    NSString *showLogValue = [storage getSettingForKey:kSettingShowLogWindowOnStartup];
    NSLog(@"🔧 [SETTINGS WINDOW] loadSettings - showLogValue from DB: '%@'", showLogValue);
    BOOL showLogWindowOnStartup = (showLogValue == nil) ? NO : [showLogValue boolValue];
    NSLog(@"🔧 [SETTINGS WINDOW] loadSettings - showLogWindowOnStartup: %@", showLogWindowOnStartup ? @"YES" : @"NO");
    self.showLogWindowOnStartupCheckbox.state = showLogWindowOnStartup ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Load show channel colors (default: YES)
    NSString *showColorsValue = [storage getSettingForKey:kSettingShowChannelColors];
    NSLog(@"🔧 [SETTINGS WINDOW] loadSettings - showColorsValue from DB: '%@'", showColorsValue);
    BOOL showChannelColors = (showColorsValue == nil) ? YES : [showColorsValue boolValue];
    self.showChannelColorsCheckbox.state = showChannelColors ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Load max messages per channel (default: 2000)
    // 0 means unlimited (never delete messages)
    NSString *maxMessagesValue = [storage getSettingForKey:kSettingMaxMessagesPerChannel];
    NSInteger maxMessages = (maxMessagesValue == nil) ? kDefaultMaxMessagesPerChannel : [maxMessagesValue integerValue];
    if (maxMessages < 0) maxMessages = 0; // Changed from 100 to 0 to allow unlimited
    if (maxMessages > 50000) maxMessages = 50000;
    self.maxMessagesTextField.integerValue = maxMessages;
    self.maxMessagesStepper.integerValue = maxMessages;
    NSLog(@"🔧 [SETTINGS WINDOW] loadSettings - maxMessages: %ld", (long)maxMessages);

    // Load message line spacing (default: 2)
    NSString *lineSpacingValue = [storage getSettingForKey:kSettingMessageLineSpacing];
    NSInteger lineSpacing = (lineSpacingValue == nil) ? kDefaultMessageLineSpacing : [lineSpacingValue integerValue];
    if (lineSpacing < 0) lineSpacing = 0;
    if (lineSpacing > 20) lineSpacing = 20;
    self.lineSpacingTextField.integerValue = lineSpacing;
    self.lineSpacingStepper.integerValue = lineSpacing;
    NSLog(@"🔧 [SETTINGS WINDOW] loadSettings - messageLineSpacing: %ld", (long)lineSpacing);
    
    NSLog(@"🔧 [SETTINGS WINDOW] loadSettings completed");
}

- (void)saveSettings {
    NSLog(@"🔧 [SETTINGS WINDOW] saveSettings called");
    MessageStorage *storage = [MessageStorage sharedStorage];
    
    BOOL showLogWindowOnStartup = (self.showLogWindowOnStartupCheckbox.state == NSControlStateValueOn);
    NSLog(@"🔧 [SETTINGS WINDOW] showLogWindowOnStartup checkbox state: %@", showLogWindowOnStartup ? @"YES" : @"NO");
    NSString *valueToSave = showLogWindowOnStartup ? @"1" : @"0";
    BOOL success1 = [storage setSettingForKey:kSettingShowLogWindowOnStartup value:valueToSave];
    NSLog(@"🔧 [SETTINGS WINDOW] Saved showLogWindowOnStartup: key=%@, value=%@, success=%@", kSettingShowLogWindowOnStartup, valueToSave, success1 ? @"YES" : @"NO");
    
    // Verify immediately after save
    NSString *verifyValue = [storage getSettingForKey:kSettingShowLogWindowOnStartup];
    NSLog(@"🔧 [SETTINGS WINDOW] Verify after save: read back value='%@'", verifyValue);
    
    BOOL showChannelColors = (self.showChannelColorsCheckbox.state == NSControlStateValueOn);
    NSString *colorValue = showChannelColors ? @"1" : @"0";
    BOOL success2 = [storage setSettingForKey:kSettingShowChannelColors value:colorValue];
    NSLog(@"🔧 [SETTINGS WINDOW] Saved showChannelColors: key=%@, value=%@, success=%@", kSettingShowChannelColors, colorValue, success2 ? @"YES" : @"NO");
    
    // Save max messages per channel
    // 0 means unlimited (never delete messages)
    NSInteger maxMessages = self.maxMessagesTextField.integerValue;
    if (maxMessages < 0) maxMessages = 0; // Changed from 100 to 0 to allow unlimited
    if (maxMessages > 50000) maxMessages = 50000;
    NSString *maxMessagesValue = [NSString stringWithFormat:@"%ld", (long)maxMessages];
    BOOL success3 = [storage setSettingForKey:kSettingMaxMessagesPerChannel value:maxMessagesValue];
    NSLog(@"🔧 [SETTINGS WINDOW] Saved maxMessagesPerChannel: key=%@, value=%@, success=%@", kSettingMaxMessagesPerChannel, maxMessagesValue, success3 ? @"YES" : @"NO");

    // Save message line spacing
    NSInteger lineSpacing = self.lineSpacingTextField.integerValue;
    if (lineSpacing < 0) lineSpacing = 0;
    if (lineSpacing > 20) lineSpacing = 20;
    NSString *lineSpacingValue = [NSString stringWithFormat:@"%ld", (long)lineSpacing];
    BOOL success4 = [storage setSettingForKey:kSettingMessageLineSpacing value:lineSpacingValue];
    NSLog(@"🔧 [SETTINGS WINDOW] Saved messageLineSpacing: key=%@, value=%@, success=%@", kSettingMessageLineSpacing, lineSpacingValue, success4 ? @"YES" : @"NO");
    
    NSLog(@"🔧 [SETTINGS WINDOW] Settings saved to SQLite database");
    
    // Notify delegate
    NSLog(@"🔧 [SETTINGS WINDOW] Delegate: %@", self.delegate ? @"exists" : @"nil");
    if (self.delegate) {
        if ([self.delegate respondsToSelector:@selector(settingsWindowController:didChangeShowLogWindowOnStartup:)]) {
            NSLog(@"🔧 [SETTINGS WINDOW] Calling delegate method didChangeShowLogWindowOnStartup");
            [self.delegate settingsWindowController:self didChangeShowLogWindowOnStartup:showLogWindowOnStartup];
        } else {
            NSLog(@"🔧 [SETTINGS WINDOW] ERROR: Delegate does not respond to didChangeShowLogWindowOnStartup");
        }
        if ([self.delegate respondsToSelector:@selector(settingsWindowController:didChangeShowChannelColors:)]) {
            [self.delegate settingsWindowController:self didChangeShowChannelColors:showChannelColors];
        }
        if ([self.delegate respondsToSelector:@selector(settingsWindowController:didChangeMaxMessagesPerChannel:)]) {
            [self.delegate settingsWindowController:self didChangeMaxMessagesPerChannel:maxMessages];
        }
        if ([self.delegate respondsToSelector:@selector(settingsWindowController:didChangeMessageLineSpacing:)]) {
            [self.delegate settingsWindowController:self didChangeMessageLineSpacing:lineSpacing];
        }
    }
    NSLog(@"🔧 [SETTINGS WINDOW] saveSettings completed");
}

- (void)showLogWindowOnStartupChanged:(id)sender {
    // Settings are saved when OK is clicked
}

- (void)showChannelColorsChanged:(id)sender {
    // Settings are saved when OK is clicked
}

- (void)maxMessagesStepperChanged:(id)sender {
    self.maxMessagesTextField.integerValue = self.maxMessagesStepper.integerValue;
}

- (void)lineSpacingStepperChanged:(id)sender {
    self.lineSpacingTextField.integerValue = self.lineSpacingStepper.integerValue;
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.maxMessagesTextField) {
        NSInteger value = self.maxMessagesTextField.integerValue;
        if (value < 0) value = 0; // Changed from 100 to 0 to allow unlimited
        if (value > 50000) value = 50000;
        self.maxMessagesStepper.integerValue = value;
        return;
    }
    if (notification.object == self.lineSpacingTextField) {
        NSInteger value = self.lineSpacingTextField.integerValue;
        if (value < 0) value = 0;
        if (value > 20) value = 20;
        self.lineSpacingStepper.integerValue = value;
    }
}

- (void)okButtonClicked:(id)sender {
    NSLog(@"🔧 [SETTINGS WINDOW] okButtonClicked called");
    [self saveSettings];
    NSLog(@"🔧 [SETTINGS WINDOW] saveSettings returned, closing window");
    [self.window close];
    NSLog(@"🔧 [SETTINGS WINDOW] Window closed");
}

- (void)cancelButtonClicked:(id)sender {
    [self loadSettings]; // Restore original values
    [self.window close];
}

- (void)showWindow:(id)sender {
    // Reload settings from database each time window is shown
    [self loadSettings];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    // Settings are saved when OK is clicked, so no need to save here
}

@end
