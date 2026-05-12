//
//  ChatViewController+Favorites.m
//  i3Chat
//
//  Favorites functionality for ChatViewController
//  All data stored in SQLite database at ~/.i3chat/i3chat.db
//

#import "ChatViewController+Private.h"
#import "StorageConstants.h"
#import "MessageStorage.h"
#import "DebugLog.h"

@implementation ChatViewController (Favorites)

#pragma mark - Button Configuration

- (NSArray<NSDictionary<NSString *, id> *> *)favoritesButtonConfigs {
    return @[
        @{@"key": @"chat.favorites.all", @"default": @"All Favorites", @"filter": @(FavoritesFilterAll), @"icon": @"star.fill"},
        @{@"key": @"chat.favorites.recent", @"default": @"Recent", @"filter": @(FavoritesFilterRecent), @"icon": @"clock.fill"},
        @{@"key": @"chat.favorites.links", @"default": @"Links", @"filter": @(FavoritesFilterLinks), @"icon": @"link"},
        @{@"key": @"chat.favorites.media", @"default": @"Images & Videos", @"filter": @(FavoritesFilterMedia), @"icon": @"photo.fill"},
        @{@"key": @"chat.favorites.files", @"default": @"Files", @"filter": @(FavoritesFilterFiles), @"icon": @"doc.fill"},
        @{@"key": @"chat.favorites.history", @"default": @"Chat History", @"filter": @(FavoritesFilterHistory), @"icon": @"message.fill"}
    ];
}

- (NSButton *)makeFavoritesButtonWithTitle:(NSString *)title {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(handleFavoritesButtonClicked:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.controlSize = NSControlSizeRegular;
    button.buttonType = NSButtonTypeToggle;
    button.alignment = NSTextAlignmentLeft;
    
    // Modern button styling
    button.wantsLayer = YES;
    button.layer.cornerRadius = 6.0;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    
    // Set initial appearance (will be updated in updateFavoritesButtonStates)
    NSColor *normalBgColor = [NSColor colorWithRed:0.98 green:0.98 blue:0.99 alpha:1.0];
    NSColor *normalTextColor = [NSColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
    NSMutableAttributedString *normalTitle = [[NSMutableAttributedString alloc] initWithString:title];
    [normalTitle addAttribute:NSForegroundColorAttributeName value:normalTextColor range:NSMakeRange(0, title.length)];
    [normalTitle addAttribute:NSFontAttributeName value:button.font range:NSMakeRange(0, title.length)];
    button.attributedTitle = normalTitle;
    button.layer.backgroundColor = normalBgColor.CGColor;
    
    return button;
}

- (void)handleFavoritesButtonClicked:(NSButton *)sender {
    if (!sender) {
        return;
    }
    FavoritesFilter filter = (FavoritesFilter)sender.tag;
    if (self.currentFavoritesFilter == filter) {
        return;
    }
    self.currentFavoritesFilter = filter;
    [self updateFavoritesButtonStates];
    [self reloadFavoritesTable];
}

#pragma mark - Button State Updates

- (void)updateFavoritesButtonTitles {
    if (!self.favoritesButtons || self.favoritesButtons.count == 0) {
        return;
    }
    NSArray<NSDictionary<NSString *, id> *> *configs = [self favoritesButtonConfigs];
    NSUInteger count = MIN(self.favoritesButtons.count, configs.count);
    for (NSUInteger i = 0; i < count; i++) {
        NSDictionary<NSString *, id> *config = configs[i];
        NSButton *button = self.favoritesButtons[i];
        button.title = L(config[@"key"], config[@"default"]);
    }
}

- (void)updateFavoritesButtonStates {
    if (!self.favoritesButtons || self.favoritesButtons.count == 0) {
        return;
    }
    
    NSColor *normalBgColor = [NSColor colorWithRed:0.98 green:0.98 blue:0.99 alpha:1.0];
    NSColor *selectedBgColor = [NSColor colorWithRed:0.2 green:0.5 blue:0.9 alpha:1.0];
    NSColor *normalTextColor = [NSColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
    NSColor *selectedTextColor = [NSColor whiteColor];
    
    for (NSButton *button in self.favoritesButtons) {
        BOOL isSelected = (button.tag == self.currentFavoritesFilter);
        button.state = isSelected ? NSControlStateValueOn : NSControlStateValueOff;
        
        NSString *title = button.title;
        NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:title];
        NSColor *textColor = isSelected ? selectedTextColor : normalTextColor;
        [attributedTitle addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, title.length)];
        [attributedTitle addAttribute:NSFontAttributeName value:button.font range:NSMakeRange(0, title.length)];
        button.attributedTitle = attributedTitle;
        button.layer.backgroundColor = (isSelected ? selectedBgColor : normalBgColor).CGColor;
    }
}

#pragma mark - Filtering

- (NSArray<NSDictionary *> *)filteredFavoriteItems {
    NSArray<NSDictionary *> *items = self.favoriteItems ?: @[];
    if (items.count == 0) {
        return @[];
    }
    switch (self.currentFavoritesFilter) {
        case FavoritesFilterLinks: {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
                return [item[@"type"] isEqualToString:@"url"];
            }];
            return [items filteredArrayUsingPredicate:predicate];
        }
        case FavoritesFilterMedia: {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
                return [self favoriteItemIsMedia:item];
            }];
            return [items filteredArrayUsingPredicate:predicate];
        }
        case FavoritesFilterFiles: {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
                return [self favoriteItemIsFile:item];
            }];
            return [items filteredArrayUsingPredicate:predicate];
        }
        case FavoritesFilterHistory: {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
                return [item[@"type"] isEqualToString:@"line"];
            }];
            return [items filteredArrayUsingPredicate:predicate];
        }
        case FavoritesFilterRecent: {
            NSUInteger count = items.count;
            NSUInteger maxItems = MIN(count, 20);
            return [items subarrayWithRange:NSMakeRange(0, maxItems)];
        }
        case FavoritesFilterAll:
        default:
            return items;
    }
}

- (BOOL)favoriteItemIsMedia:(NSDictionary *)item {
    if (![item[@"type"] isEqualToString:@"url"]) {
        return NO;
    }
    NSString *urlString = item[@"url"];
    if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
        return NO;
    }
    NSString *extension = [self pathExtensionForURLString:urlString];
    if (extension.length == 0) {
        return NO;
    }
    NSSet<NSString *> *mediaExtensions = [NSSet setWithArray:@[
        @"jpg", @"jpeg", @"png", @"gif", @"webp", @"bmp", @"tiff", @"svg",
        @"mp4", @"mov", @"m4v", @"webm", @"avi", @"mkv", @"mpg", @"mpeg", @"3gp"
    ]];
    return [mediaExtensions containsObject:extension];
}

- (BOOL)favoriteItemIsFile:(NSDictionary *)item {
    if (![item[@"type"] isEqualToString:@"url"]) {
        return NO;
    }
    NSString *urlString = item[@"url"];
    if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
        return NO;
    }
    NSString *extension = [self pathExtensionForURLString:urlString];
    if (extension.length == 0) {
        return NO;
    }
    NSSet<NSString *> *fileExtensions = [NSSet setWithArray:@[
        @"pdf", @"doc", @"docx", @"xls", @"xlsx", @"ppt", @"pptx",
        @"txt", @"md", @"rtf", @"csv", @"zip", @"rar", @"7z", @"tar", @"gz",
        @"json", @"xml", @"apk", @"dmg", @"pkg", @"exe", @"iso"
    ]];
    return [fileExtensions containsObject:extension];
}

- (NSString *)pathExtensionForURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *extension = url.pathExtension;
    if (extension.length == 0) {
        extension = [urlString pathExtension];
    }
    return extension.lowercaseString ?: @"";
}

#pragma mark - Table View Support

- (void)reloadFavoritesTable {
    // Load from database if not yet loaded
    if (!self.favoriteItems) {
        [self loadFavoritesFromStorage];
        return;
    }
    CVLog(@"[Favorites] reloadFavoritesTable: %lu items, favoritesTableView=%@", 
          (unsigned long)self.favoriteItems.count, self.favoritesTableView);
    if (self.favoritesTableView) {
        [self.favoritesTableView reloadData];
        CVLog(@"[Favorites] reloadFavoritesTable: reloaded tableView");
    }
    [self updateFavoritesEmptyState];
}

- (void)loadFavoritesFromStorage {
    // Load from database
    NSArray<NSDictionary *> *items = [[MessageStorage sharedStorage] loadAllFavorites];
    self.favoriteItems = [items mutableCopy] ?: [[NSMutableArray alloc] init];
    CVLog(@"[Favorites] loadFavoritesFromStorage: loaded %lu items from database", (unsigned long)self.favoriteItems.count);
    
    if (self.favoritesTableView) {
        [self.favoritesTableView reloadData];
    }
    [self updateFavoritesEmptyState];
}

- (void)updateFavoritesEmptyState {
    if (!self.favoritesEmptyLabel) {
        return;
    }
    BOOL hasItems = ([self filteredFavoriteItems].count > 0);
    self.favoritesEmptyLabel.hidden = hasItems;
}

- (void)layoutFavoritesButtonsInPanel {
    if (!self.favoritesPanel || self.favoritesButtons.count == 0) {
        return;
    }
    CGFloat padding = 12.0;
    CGFloat titleHeight = 40.0;
    CGFloat buttonHeight = 32.0;
    CGFloat spacing = 6.0;
    NSRect panelBounds = self.favoritesPanel.bounds;
    CGFloat panelWidth = panelBounds.size.width;
    CGFloat panelHeight = panelBounds.size.height;
    CGFloat startY = panelHeight - padding - titleHeight - buttonHeight;
    CGFloat maxWidth = MAX(0.0, panelWidth - padding * 2);

    // Update title label position
    NSView *titleView = nil;
    for (NSView *subview in self.favoritesPanel.subviews) {
        if ([subview isKindOfClass:[NSTextField class]] && ((NSTextField *)subview).editable == NO) {
            titleView = subview;
            break;
        }
    }
    if (titleView) {
        titleView.frame = NSMakeRect(padding, panelHeight - titleHeight + 8, maxWidth, 24);
    }

    for (NSUInteger i = 0; i < self.favoritesButtons.count; i++) {
        NSButton *button = self.favoritesButtons[i];
        CGFloat y = startY - (buttonHeight + spacing) * i;
        button.frame = NSMakeRect(padding, y, maxWidth, buttonHeight);
    }
}

- (NSString *)displayTextForFavoriteItem:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return @"";
    }
    NSString *content = item[@"content"];
    if (![content isKindOfClass:[NSString class]]) {
        content = @"";
    }
    NSString *server = item[@"server"];
    NSString *channel = item[@"channel"];
    
    // If channel is empty, try to extract from channelKey
    if (channel.length == 0) {
        NSString *channelKey = item[@"channelKey"];
        if (channelKey.length > 0) {
            NSRange range = [channelKey rangeOfString:ChannelKeySeparator];
            if (range.location != NSNotFound && range.location + range.length < channelKey.length) {
                channel = [channelKey substringFromIndex:range.location + range.length];
            } else {
                // Legacy format: server:channel
                NSRange legacyRange = [channelKey rangeOfString:@":" options:NSBackwardsSearch];
                if (legacyRange.location != NSNotFound && legacyRange.location + 1 < channelKey.length) {
                    channel = [channelKey substringFromIndex:legacyRange.location + 1];
                }
            }
        }
    }
    
    if (server.length > 0 && channel.length > 0) {
        return [NSString stringWithFormat:@"%@ / %@: %@", server, channel, content];
    }
    if (channel.length > 0) {
        return [NSString stringWithFormat:@"%@: %@", channel, content];
    }
    if (server.length > 0) {
        return [NSString stringWithFormat:@"%@: %@", server, content];
    }
    return content ?: @"";
}

#pragma mark - Persistence (Database)

- (void)addFavoriteItem:(NSDictionary *)item {
    if (!item || ![item isKindOfClass:[NSDictionary class]]) {
        return;
    }
    
    // Save to database
    BOOL saved = [[MessageStorage sharedStorage] saveFavoriteItem:item];
    if (saved) {
        // Reload from database to get the item with its assigned id
        // This ensures delete operations will work correctly
        [self loadFavoritesFromStorage];
    }
}

- (void)addFavoriteItemWithType:(NSString *)type content:(NSString *)content url:(NSString *)urlString {
    if (type.length == 0 || content.length == 0) {
        CVLog(@"[Favorites] addFavoriteItemWithType: invalid input - type=%@, content length=%lu", type, (unsigned long)content.length);
        return;
    }
    
    NSMutableDictionary *item = [[NSMutableDictionary alloc] init];
    item[@"type"] = type;
    item[@"content"] = content;
    if (urlString.length > 0) {
        item[@"url"] = urlString;
    }
    
    // Set server and channel
    NSString *server = @"";
    NSString *channel = @"";
    
    if (self.currentChannelKey.length > 0) {
        item[@"channelKey"] = self.currentChannelKey;
        // Extract server and channel from channelKey (format: server||channel)
        NSRange range = [self.currentChannelKey rangeOfString:ChannelKeySeparator];
        if (range.location != NSNotFound) {
            server = [self.currentChannelKey substringToIndex:range.location];
            if (range.location + range.length < self.currentChannelKey.length) {
                channel = [self.currentChannelKey substringFromIndex:range.location + range.length];
            }
        }
    }
    
    if (server.length == 0 && self.currentServer.length > 0) {
        server = self.currentServer;
    }
    
    item[@"server"] = server;
    item[@"channel"] = channel;
    item[@"timestamp"] = [NSDate date];
    
    CVLog(@"[Favorites] Adding item: type=%@, server=%@, channel=%@", type, server, channel);
    [self addFavoriteItem:item];
}

- (void)removeFavoriteItemAtIndex:(NSUInteger)index {
    NSArray<NSDictionary *> *filteredItems = [self filteredFavoriteItems];
    if (index >= filteredItems.count) {
        return;
    }
    
    // Get the item to delete
    NSDictionary *item = filteredItems[index];
    NSNumber *itemId = item[@"id"];
    if (!itemId || ![itemId isKindOfClass:[NSNumber class]]) {
        CVLog(@"[Favorites] Cannot delete: no valid id for item at index %lu", (unsigned long)index);
        return;
    }
    
    // Delete from database by ID
    BOOL deleted = [[MessageStorage sharedStorage] deleteFavoriteById:[itemId integerValue]];
    if (deleted) {
        CVLog(@"[Favorites] Successfully deleted item with id %@", itemId);
        // Reload from database to ensure consistency
        [self loadFavoritesFromStorage];
    } else {
        CVLog(@"[Favorites] Failed to delete item with id %@", itemId);
    }
}

@end

#pragma mark - Settings Category

@implementation ChatViewController (Settings)

- (void)openSettings {
    if (!self.settingsWindowController) {
        self.settingsWindowController = [[SettingsWindowController alloc] init];
        self.settingsWindowController.delegate = self;
    }
    [self.settingsWindowController showWindow:nil];
}

- (void)settingsWindowController:(SettingsWindowController *)controller didChangeShowLogWindowOnStartup:(BOOL)showLogWindow {
    CVLog(@"🔧 [SETTINGS] didChangeShowLogWindowOnStartup called with: %@", showLogWindow ? @"YES" : @"NO");
    
    [[MessageStorage sharedStorage] setSettingForKey:kSettingShowLogWindowOnStartup value:showLogWindow ? @"1" : @"0"];
    
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self settingsWindowController:controller didChangeShowLogWindowOnStartup:showLogWindow];
        });
        return;
    }
    
    self.logWindowVisible = showLogWindow;
    
    NSView *logView = self.logContainer ?: self.logScrollView;
    if (self.middleSplitView && logView) {
        logView.hidden = !self.logWindowVisible;
        
        CGFloat contentHeight = self.middleSplitView.bounds.size.height;
        if (!self.logWindowVisible) {
            [self.middleSplitView setPosition:contentHeight ofDividerAtIndex:0];
        } else {
            [self.middleSplitView setPosition:contentHeight * 0.75 ofDividerAtIndex:0];
        }
        [self.middleSplitView adjustSubviews];
        logView.hidden = !self.logWindowVisible;
        
        // Force updates
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.middleSplitView && logView) {
                logView.hidden = !self.logWindowVisible;
                CGFloat contentHeight = self.middleSplitView.bounds.size.height;
                if (!self.logWindowVisible) {
                    [self.middleSplitView setPosition:contentHeight ofDividerAtIndex:0];
                } else {
                    [self.middleSplitView setPosition:contentHeight * 0.75 ofDividerAtIndex:0];
                }
                [self.middleSplitView adjustSubviews];
                logView.hidden = !self.logWindowVisible;
            }
        });
    }
    
    CVLog(@"Settings changed: Show log window on startup = %@", showLogWindow ? @"YES" : @"NO");
}

- (void)settingsWindowController:(SettingsWindowController *)controller didChangeShowChannelColors:(BOOL)showColors {
    self.showChannelColors = showColors;
    
    [[MessageStorage sharedStorage] setSettingForKey:kSettingShowChannelColors value:showColors ? @"1" : @"0"];
    
    [self reloadChannelListForMode];
    
    // Re-render the current channel's messages with the new color setting
    if (self.currentChannelKey) {
        [self displayMessagesForChannel:self.currentChannelKey];
        CVLog(@"Re-rendered messages for channel %@ with showColors=%@", self.currentChannelKey, showColors ? @"YES" : @"NO");
    }
    
    CVLog(@"Settings changed: Show channel colors = %@", showColors ? @"YES" : @"NO");
}

- (void)settingsWindowController:(SettingsWindowController *)controller didChangeMaxMessagesPerChannel:(NSInteger)maxMessages {
    self.maxMessagesPerChannel = maxMessages;
    
    // Update all existing channel buffers
    for (ChannelBuffer *buffer in self.channels.allValues) {
        buffer.maxMessages = maxMessages;
        [buffer trimMessagesToLimit];
    }
    
    // Re-render current channel if needed
    if (self.currentChannelKey) {
        [self displayMessagesForChannel:self.currentChannelKey];
    }
    
    CVLog(@"Settings changed: Max messages per channel = %ld", (long)maxMessages);
}

- (void)settingsWindowController:(SettingsWindowController *)controller didChangeMessageLineSpacing:(NSInteger)spacing {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self settingsWindowController:controller didChangeMessageLineSpacing:spacing];
        });
        return;
    }
    if (spacing < 0) spacing = 0;
    if (spacing > 20) spacing = 20;
    self.messageLineSpacing = spacing;
    [[MessageStorage sharedStorage] setSettingForKey:kSettingMessageLineSpacing value:[NSString stringWithFormat:@"%ld", (long)spacing]];

    // Clear cached attributed messages so new spacing is applied
    [self.cachedAttributedMessages removeAllObjects];
    [self.lastRenderedMessageCount removeAllObjects];
    self.lastDisplayedChannelKey = nil;
    if (self.currentChannelKey) {
        [self displayMessagesForChannel:self.currentChannelKey];
    }
    CVLog(@"Settings changed: Message line spacing = %ld", (long)spacing);
}

@end
