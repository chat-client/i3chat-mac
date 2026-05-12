//
//  ChatViewController+Channel.m
//  i3Chat
//
//  Channel and server management for ChatViewController
//  All data stored in SQLite database at ~/.i3chat/i3chat.db
//

#import "ChatViewController+Private.h"
#import "MessageStorage.h"
#import "DebugLog.h"

@implementation ChatViewController (Channel)

#pragma mark - Server Connection

- (void)connectToServers {
    if (self.configs.count == 0) {
        return;
    }
    
    for (IRCConfig *config in self.configs) {
        if (config.server.length == 0) {
            continue;
        }
        
        [self addServerIfNeeded:config.server];
        
        IRCClient *client = [[IRCClient alloc] initWithConfig:config];
        client.delegate = self;
        self.ircClients[config.server] = client;
        
        CVLog(@"ChatViewController: connectToServers - delegate set for %@: %@",
              config.server, client.delegate ? @"YES" : @"NO");
        
        [client connect];
    }
}

#pragma mark - Channel Key Management

- (NSString *)makeChannelKey:(NSString *)server channel:(NSString *)channel {
    return [NSString stringWithFormat:@"%@%@%@", server, ChannelKeySeparator, channel];
}

- (NSString *)serverFromChannelKey:(NSString *)channelKey {
    if (!channelKey || channelKey.length == 0) {
        return @"";
    }
    NSRange range = [channelKey rangeOfString:ChannelKeySeparator];
    if (range.location != NSNotFound) {
        return [channelKey substringToIndex:range.location];
    }
    NSRange legacyRange = [channelKey rangeOfString:@":" options:NSBackwardsSearch];
    if (legacyRange.location == NSNotFound) {
        return @"";
    }
    return [channelKey substringToIndex:legacyRange.location];
}

- (NSString *)channelFromChannelKey:(NSString *)channelKey {
    if (!channelKey || channelKey.length == 0) {
        return @"";
    }
    NSRange range = [channelKey rangeOfString:ChannelKeySeparator];
    if (range.location != NSNotFound) {
        if (range.location + range.length >= channelKey.length) {
            return @"";
        }
        return [channelKey substringFromIndex:range.location + range.length];
    }
    NSRange legacyRange = [channelKey rangeOfString:@":" options:NSBackwardsSearch];
    if (legacyRange.location == NSNotFound || legacyRange.location + 1 >= channelKey.length) {
        return @"";
    }
    return [channelKey substringFromIndex:legacyRange.location + 1];
}

#pragma mark - Client/Config Accessors

- (IRCClient *)clientForServer:(NSString *)server {
    if (!server || server.length == 0) {
        return nil;
    }
    return self.ircClients[server];
}

- (IRCConfig *)configForServer:(NSString *)server {
    if (!server || server.length == 0) {
        return nil;
    }
    return self.serverConfigs[server];
}

- (IRCConfig *)ensureConfigForServer:(NSString *)server {
    IRCConfig *config = [self configForServer:server];
    if (config) {
        return config;
    }

    IRCConfig *fallback = nil;
    if (self.currentServer.length > 0) {
        fallback = [self configForServer:self.currentServer];
    }
    if (!fallback && self.configs.count > 0) {
        fallback = self.configs[0];
    }

    NSString *nick = fallback ? fallback.nick : @"user-i3chat";
    NSString *user = fallback ? fallback.user : @"macirc";
    NSString *realName = fallback ? fallback.realName : @"macOS IRC Client";
    NSString *password = fallback ? fallback.password : nil;
    BOOL useTLS;
    if ([server hasSuffix:@":6697"]) {
        useTLS = YES;
    } else if ([server hasSuffix:@":6667"]) {
        useTLS = NO;
    } else {
        useTLS = fallback ? fallback.useTLS : NO;
    }

    config = [[IRCConfig alloc] initWithServer:server
                                          nick:nick
                                          user:user
                                      realName:realName
                                       channel:@""
                                      password:password
                                        useTLS:useTLS];
    self.serverConfigs[server] = config;

    NSMutableArray<IRCConfig *> *configs = [self.configs mutableCopy];
    [configs addObject:config];
    self.configs = configs;

    return config;
}

#pragma mark - Joined Channels Management

- (NSMutableSet<NSString *> *)joinedChannelSetForServer:(NSString *)server createIfNeeded:(BOOL)createIfNeeded {
    if (!server || server.length == 0) {
        return nil;
    }
    NSMutableSet<NSString *> *set = self.joinedChannels[server];
    if (!set && createIfNeeded) {
        set = [[NSMutableSet alloc] init];
        self.joinedChannels[server] = set;
    }
    return set;
}

- (NSMutableSet<NSString *> *)autoJoinChannelSetForServer:(NSString *)server createIfNeeded:(BOOL)createIfNeeded {
    if (!server || server.length == 0) {
        return nil;
    }
    NSMutableSet<NSString *> *set = self.autoJoinChannels[server];
    if (!set && createIfNeeded) {
        set = [[NSMutableSet alloc] init];
        self.autoJoinChannels[server] = set;
    }
    return set;
}

- (BOOL)isChannelJoined:(ChannelBuffer *)buffer {
    if (!buffer || buffer.isPrivate) {
        return YES;
    }
    NSMutableSet<NSString *> *joinedSet = [self joinedChannelSetForServer:buffer.server createIfNeeded:NO];
    return joinedSet && [joinedSet containsObject:buffer.name];
}

- (BOOL)isServerConnected:(NSString *)server {
    if (!server || server.length == 0) {
        return NO;
    }
    IRCClient *client = [self clientForServer:server];
    return client && client.isConnected && ![self.disconnectedServers containsObject:server];
}

- (BOOL)isChannelListItemDisabled:(ChannelTreeItem *)item {
    if (![item isKindOfClass:[ChannelTreeItem class]]) {
        return NO;
    }

    if (item.type == ChannelTreeItemTypeServer) {
        return ![self isServerConnected:item.server];
    }

    if (item.type == ChannelTreeItemTypeChannel) {
        ChannelBuffer *buffer = item.channelKey ? self.channels[item.channelKey] : nil;
        if (!buffer) {
            return NO;
        }

        if (![self isServerConnected:buffer.server]) {
            return YES;
        }

        if (buffer.isPrivate) {
            return NO;
        }

        return ![self isChannelJoined:buffer];
    }

    if (item.type == ChannelTreeItemTypeRecent) {
        ChannelBuffer *buffer = item.channelKey ? self.channels[item.channelKey] : nil;
        if (!buffer) {
            return YES;
        }
        if (![self isServerConnected:buffer.server]) {
            return YES;
        }
        if (buffer.isPrivate) {
            return NO;
        }
        return ![self isChannelJoined:buffer];
    }
    
    if (item.type == ChannelTreeItemTypeGroup) {
        NSArray<NSString *> *channels = self.customGroupChannels[item.server];
        return channels.count == 0;
    }
    
    if (item.type == ChannelTreeItemTypePlaceholder) {
        return YES;
    }

    return NO;
}

#pragma mark - Server Management

- (BOOL)addServerIfNeeded:(NSString *)server {
    if (!server || server.length == 0) {
        return NO;
    }
    BOOL needsReload = NO;

    if (![self.serverOrder containsObject:server]) {
        [self.serverOrder addObject:server];
        needsReload = YES;
    }
    
    if (!self.serverChannelOrder[server]) {
        self.serverChannelOrder[server] = [[NSMutableArray alloc] init];
    }
    
    if (!self.serverItems[server]) {
        ChannelTreeItem *item = [[ChannelTreeItem alloc] init];
        item.type = ChannelTreeItemTypeServer;
        item.server = server;
        self.serverItems[server] = item;
        needsReload = YES;
    }
    
    if (needsReload) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadChannelListPreservingSelection];
            ChannelTreeItem *serverItem = self.serverItems[server];
            if (serverItem) {
                [self.channelListView expandItem:serverItem];
            }
        });
    }

    [self persistServersAndChannels];
    return needsReload;
}

- (void)selectServerIfEmpty:(NSString *)server {
    ChannelTreeItem *serverItem = self.serverItems[server];
    if (!serverItem) {
        return;
    }
    NSArray<NSString *> *channels = self.serverChannelOrder[server];
    if (channels.count > 0) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger row = [self.channelListView rowForItem:serverItem];
        if (row >= 0) {
            [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            [self.channelListView scrollRowToVisible:row];
        }
    });
}

- (void)selectServer:(NSString *)server {
    ChannelTreeItem *serverItem = self.serverItems[server];
    if (!serverItem) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger row = [self.channelListView rowForItem:serverItem];
        if (row >= 0) {
            [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            [self.channelListView scrollRowToVisible:row];
        }
    });
}

- (void)clearUsersForServer:(NSString *)server {
    if (!server || server.length == 0) {
        return;
    }
    NSArray<NSString *> *channelKeys = self.serverChannelOrder[server];
    for (NSString *channelKey in channelKeys) {
        ChannelBuffer *buffer = self.channels[channelKey];
        if (buffer && buffer.users) {
            [buffer.users removeAllObjects];
        }
    }
    NSMutableSet<NSString *> *joinedSet = [self joinedChannelSetForServer:server createIfNeeded:NO];
    [joinedSet removeAllObjects];
    
    if (self.currentChannelKey && [[self serverFromChannelKey:self.currentChannelKey] isEqualToString:server]) {
        [self updateUserListForChannel:self.currentChannelKey];
    }
}

#pragma mark - Channel Management

- (void)addChannel:(NSString *)server channel:(NSString *)channel isPrivate:(BOOL)isPrivate {
    NSString *key = [self makeChannelKey:server channel:channel];
    
    if (!self.channels[key]) {
        ChannelBuffer *buffer = [[ChannelBuffer alloc] initWithName:channel server:server isPrivate:isPrivate];
        
        // Load message storage setting from database
        BOOL allowStorage = [self loadMessageStorageSettingForChannelKey:key];
        buffer.allowMessageStorage = allowStorage;
        
        self.channels[key] = buffer;
    }
    
    BOOL didAddServer = [self addServerIfNeeded:server];
    BOOL didAddChannel = NO;
    
    NSMutableArray<NSString *> *channelOrder = self.serverChannelOrder[server];
    if (channelOrder && ![channelOrder containsObject:key]) {
        [channelOrder addObject:key];
        didAddChannel = YES;
    }
    
    if (!self.channelItems[key]) {
        ChannelTreeItem *item = [[ChannelTreeItem alloc] init];
        item.type = ChannelTreeItemTypeChannel;
        item.server = server;
        item.channelKey = key;
        self.channelItems[key] = item;
        didAddChannel = YES;
    }

    if (didAddServer || didAddChannel) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadChannelListPreservingSelection];
            ChannelTreeItem *serverItem = self.serverItems[server];
            if (serverItem) {
                [self.channelListView expandItem:serverItem];
            }
        });
    }
    
    if (!self.currentChannelKey) {
        self.currentChannelKey = key;
        [self switchToChannel:key];
    }

    if (!isPrivate) {
        [self persistServersAndChannels];
    }
}

- (void)addPersistedChannel:(NSString *)server channel:(NSString *)channel {
    if (!server || server.length == 0 || !channel || channel.length == 0) {
        return;
    }

    NSString *key = [self makeChannelKey:server channel:channel];
    if (!self.channels[key]) {
        ChannelBuffer *buffer = [[ChannelBuffer alloc] initWithName:channel server:server isPrivate:NO];
        
        // Load message storage setting from database
        BOOL allowStorage = [self loadMessageStorageSettingForChannelKey:key];
        buffer.allowMessageStorage = allowStorage;
        
        self.channels[key] = buffer;
    }

    [self addServerIfNeeded:server];
    NSMutableArray<NSString *> *channelOrder = self.serverChannelOrder[server];
    if (channelOrder && ![channelOrder containsObject:key]) {
        [channelOrder addObject:key];
    }

    if (!self.channelItems[key]) {
        ChannelTreeItem *item = [[ChannelTreeItem alloc] init];
        item.type = ChannelTreeItemTypeChannel;
        item.server = server;
        item.channelKey = key;
        self.channelItems[key] = item;
    }
}

- (void)removeChannelWithKey:(NSString *)channelKey {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self removeChannelWithKey:channelKey];
        });
        return;
    }

    if (!channelKey || channelKey.length == 0) {
        return;
    }

    BOOL wasCurrent = [channelKey isEqualToString:self.currentChannelKey];
    NSString *server = [self serverFromChannelKey:channelKey];
    NSMutableArray<NSString *> *channelOrder = server.length > 0 ? self.serverChannelOrder[server] : nil;
    NSUInteger index = channelOrder ? [channelOrder indexOfObject:channelKey] : NSNotFound;

    [self.channels removeObjectForKey:channelKey];
    [self.channelItems removeObjectForKey:channelKey];
    if (channelOrder && index != NSNotFound) {
        [channelOrder removeObjectAtIndex:index];
    }
    
    // Use protected reload to prevent focus jumping
    self.isReloadingChannelList = YES;
    [self.channelListView reloadData];
    self.isReloadingChannelList = NO;

    if (!wasCurrent) {
        return;
    }

    NSString *nextChannelKey = nil;
    if (channelOrder && channelOrder.count > 0) {
        NSUInteger nextIndex = (index == NSNotFound || index >= channelOrder.count) ? channelOrder.count - 1 : index;
        nextChannelKey = channelOrder[nextIndex];
    }
    if (!nextChannelKey) {
        for (NSString *serverKey in self.serverOrder) {
            NSArray<NSString *> *serverChannels = self.serverChannelOrder[serverKey];
            if (serverChannels.count > 0) {
                nextChannelKey = serverChannels[0];
                break;
            }
        }
    }

    if (nextChannelKey) {
        [self switchToChannel:nextChannelKey];
    } else {
        self.currentChannelKey = nil;
        self.chatTextView.string = L(@"chat.noChannel", @"No channel selected.\n");
    }
}

#pragma mark - Channel Switching

- (void)switchToChannel:(NSString *)channelKey {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self switchToChannel:channelKey];
        });
        return;
    }
    
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer) {
        CVLog(@"Warning: No buffer found for channelKey %@", channelKey);
        return;
    }
    
    // Update current channel
    self.currentChannelKey = channelKey;
    NSString *server = [self serverFromChannelKey:channelKey];
    if (server.length > 0) {
        self.currentServer = server;
    }
    
    // Clear nickname highlights when switching channels
    [self.highlightedNicknames removeAllObjects];
    
    // Load recent messages if needed
    [self loadRecentMessagesIfNeededForChannelKey:channelKey];
    
    // Display messages
    [self displayMessagesForChannel:channelKey];
    
    // Update user list
    [self updateUserListForChannel:channelKey];
    
    // Update status
    [self updateStatus];
    
    // Update window title
    if (buffer.name.length > 0) {
        [self updateWindowTitleForChatName:buffer.name];
    }
    
    // Apply background color
    [self applyBackgroundColorForChannelKey:channelKey];
    
    // Record in recent channels
    [self recordRecentChannelKey:channelKey];
    
    // Mark as read
    if (buffer.unreadCount > 0) {
        buffer.unreadCount = 0;
        // Use more granular update instead of full reloadData to avoid interference with channel switching
        // Only reload the specific item that changed
        if (self.channelListMode == ChannelListModeChannels) {
            ChannelTreeItem *item = self.channelItems[channelKey];
            if (item) {
                NSInteger row = [self.channelListView rowForItem:item];
                if (row >= 0) {
                    self.isReloadingChannelList = YES;
                    [self.channelListView reloadItem:item reloadChildren:NO];
                    self.isReloadingChannelList = NO;
                }
            }
        } else if (self.channelListMode == ChannelListModeRecent) {
            ChannelTreeItem *item = [self recentItemForChannelKey:channelKey];
            if (item) {
                NSInteger row = [self.channelListView rowForItem:item];
                if (row >= 0) {
                    self.isReloadingChannelList = YES;
                    [self.channelListView reloadItem:item reloadChildren:NO];
                    self.isReloadingChannelList = NO;
                }
            }
        } else if (self.channelListMode == ChannelListModeGroups) {
            // In groups mode, the same channel can appear in multiple groups
            // We need to reload ALL instances of this channel across all groups
            self.isReloadingChannelList = YES;
            for (NSString *groupChannelKey in self.groupChannelItems) {
                // groupChannelKey format is "groupName:channelKey"
                if ([groupChannelKey hasSuffix:[NSString stringWithFormat:@":%@", channelKey]]) {
                    ChannelTreeItem *item = self.groupChannelItems[groupChannelKey];
                    if (item) {
                        NSInteger row = [self.channelListView rowForItem:item];
                        if (row >= 0) {
                            [self.channelListView reloadItem:item reloadChildren:NO];
                        }
                    }
                }
            }
            self.isReloadingChannelList = NO;
        }
    }
    
    // Select in channel list
    self.isUpdatingChannelSelection = YES;
    if (self.channelListMode == ChannelListModeChannels) {
        ChannelTreeItem *item = self.channelItems[channelKey];
        if (item) {
            NSInteger row = [self.channelListView rowForItem:item];
            if (row >= 0) {
                [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
                [self.channelListView scrollRowToVisible:row];
            }
        } else {
            // This is a server status window (channel name equals server name)
            // Select the server row instead
            ChannelTreeItem *serverItem = self.serverItems[server];
            if (serverItem) {
                NSInteger row = [self.channelListView rowForItem:serverItem];
                if (row >= 0) {
                    [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
                    [self.channelListView scrollRowToVisible:row];
                }
            }
        }
    } else if (self.channelListMode == ChannelListModeRecent) {
        ChannelTreeItem *item = [self recentItemForChannelKey:channelKey];
        if (item) {
            NSInteger row = [self.channelListView rowForItem:item];
            if (row >= 0) {
                [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
                [self.channelListView scrollRowToVisible:row];
            }
        }
    }
    // Note: For ChannelListModeGroups, we intentionally skip programmatic selection
    // because the same channel can appear in multiple groups. Since they share the same
    // ChannelTreeItem object, rowForItem: cannot distinguish between different group instances.
    // The user's click already selected the correct row, so we preserve their selection.
    self.isUpdatingChannelSelection = NO;
}

#pragma mark - Recent Channels

- (void)recordRecentChannelKey:(NSString *)channelKey {
    if (channelKey.length == 0) {
        return;
    }
    
    [self.recentChannelKeys removeObject:channelKey];
    [self.recentChannelKeys insertObject:channelKey atIndex:0];
    if (self.recentChannelKeys.count > 20) {
        [self.recentChannelKeys removeLastObject];
    }
    
    if (!self.recentItems[channelKey]) {
        ChannelTreeItem *item = [[ChannelTreeItem alloc] init];
        item.type = ChannelTreeItemTypeRecent;
        item.channelKey = channelKey;
        self.recentItems[channelKey] = item;
    }
    
    if (self.channelListMode == ChannelListModeRecent) {
        [self requestChannelListReload];
    }
    [self persistRecentChannelKeys];
}

- (void)removeRecentChannelKey:(NSString *)channelKey {
    if (channelKey.length == 0) {
        return;
    }
    [self.recentChannelKeys removeObject:channelKey];
    [self.recentItems removeObjectForKey:channelKey];
    if (self.channelListMode == ChannelListModeRecent) {
        [self requestChannelListReload];
    }
    [self persistRecentChannelKeys];
}

- (void)loadRecentChannelKeysFromDefaults {
    // First try to load from SQLite
    NSString *jsonString = [[MessageStorage sharedStorage] getSettingForKey:kSettingRecentChannelKeys];
    CVLog(@"[Recent] Loading from SQLite, key=%@, jsonString=%@", kSettingRecentChannelKeys, jsonString);
    NSArray *recentKeys = nil;
    
    if (jsonString.length > 0) {
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        recentKeys = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        if (error || ![recentKeys isKindOfClass:[NSArray class]]) {
            CVLog(@"[Recent] JSON parse error: %@", error);
            recentKeys = nil;
        } else {
            CVLog(@"[Recent] Loaded recent keys from SQLite: %@", recentKeys);
        }
    }
    
    // If not in SQLite, try to migrate from NSUserDefaults
    if (!recentKeys) {
        id rawRecent = [[NSUserDefaults standardUserDefaults] objectForKey:kChannelRecentListDefaultsKey];
        if ([rawRecent isKindOfClass:[NSArray class]]) {
            recentKeys = (NSArray *)rawRecent;
            // Migrate to SQLite
            [self persistRecentChannelKeys];
            // Remove from NSUserDefaults
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kChannelRecentListDefaultsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
    
    if ([recentKeys isKindOfClass:[NSArray class]]) {
        [self.recentChannelKeys removeAllObjects];
        for (id value in recentKeys) {
            if (![value isKindOfClass:[NSString class]]) {
                continue;
            }
            NSString *channelKey = (NSString *)value;
            if (channelKey.length == 0) {
                continue;
            }
            if (![self.recentChannelKeys containsObject:channelKey]) {
                [self.recentChannelKeys addObject:channelKey];
            }
            if (!self.recentItems[channelKey]) {
                ChannelTreeItem *item = [[ChannelTreeItem alloc] init];
                item.type = ChannelTreeItemTypeRecent;
                item.channelKey = channelKey;
                self.recentItems[channelKey] = item;
            }
        }
    }
    if (self.channelListMode == ChannelListModeRecent) {
        [self requestChannelListReload];
    }
}

- (void)persistRecentChannelKeys {
    NSArray<NSString *> *recentKeys = self.recentChannelKeys ? [self.recentChannelKeys copy] : @[];
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:recentKeys options:0 error:&error];
    if (!error && jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        BOOL success = [[MessageStorage sharedStorage] setSettingForKey:kSettingRecentChannelKeys value:jsonString];
        CVLog(@"[Recent] Saved to SQLite: key=%@, count=%lu, success=%@", kSettingRecentChannelKeys, (unsigned long)recentKeys.count, success ? @"YES" : @"NO");
    } else {
        CVLog(@"[Recent] Failed to serialize recent keys: %@", error);
    }
}

- (BOOL)isChannelKeyInServerList:(NSString *)channelKey {
    if (channelKey.length == 0) {
        return NO;
    }
    NSString *server = [self serverFromChannelKey:channelKey];
    NSArray<NSString *> *channels = server.length > 0 ? self.serverChannelOrder[server] : nil;
    if (!channels) {
        return NO;
    }
    return [channels containsObject:channelKey];
}

- (ChannelTreeItem *)recentItemForChannelKey:(NSString *)channelKey {
    if (channelKey.length == 0) {
        return nil;
    }
    ChannelTreeItem *item = self.recentItems[channelKey];
    if (!item) {
        item = [[ChannelTreeItem alloc] init];
        item.type = ChannelTreeItemTypeRecent;
        item.channelKey = channelKey;
        self.recentItems[channelKey] = item;
    }
    return item;
}

- (void)requestChannelListReload {
    if (!self.channelListView || self.pendingChannelListReload) {
        return;
    }
    self.pendingChannelListReload = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pendingChannelListReload = NO;
        if (self.isReloadingChannelList) {
            return;
        }
        [self reloadChannelListPreservingSelection];
    });
}

- (void)reloadChannelListPreservingSelection {
    if (!self.channelListView) {
        return;
    }
    
    // Save current selection
    NSInteger selectedRow = self.channelListView.selectedRow;
    id selectedItem = selectedRow >= 0 ? [self.channelListView itemAtRow:selectedRow] : nil;
    
    // For groups mode, also save the channel key to verify the item at the restored row
    NSString *selectedChannelKey = nil;
    if (self.channelListMode == ChannelListModeGroups && selectedItem && [selectedItem isKindOfClass:[ChannelTreeItem class]]) {
        ChannelTreeItem *treeItem = (ChannelTreeItem *)selectedItem;
        selectedChannelKey = treeItem.channelKey;
    }
    
    // Reload data
    self.isReloadingChannelList = YES;
    [self.channelListView reloadData];
    self.isReloadingChannelList = NO;
    
    // Restore selection
    if (selectedItem) {
        NSInteger newRow = -1;
        
        if (self.channelListMode == ChannelListModeGroups) {
            // In groups mode, the same channel can appear in multiple groups sharing the same item object.
            // rowForItem: cannot distinguish between them. Instead, try to keep the same row position
            // if the item at that row still has the same channelKey.
            NSInteger rowCount = [self.channelListView numberOfRows];
            if (selectedRow >= 0 && selectedRow < rowCount) {
                id itemAtOldRow = [self.channelListView itemAtRow:selectedRow];
                if (itemAtOldRow && [itemAtOldRow isKindOfClass:[ChannelTreeItem class]]) {
                    ChannelTreeItem *treeItem = (ChannelTreeItem *)itemAtOldRow;
                    if ([treeItem.channelKey isEqualToString:selectedChannelKey]) {
                        newRow = selectedRow;
                    }
                }
            }
        } else {
            newRow = [self.channelListView rowForItem:selectedItem];
        }
        
        if (newRow >= 0) {
            self.isUpdatingChannelSelection = YES;
            [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
            self.isUpdatingChannelSelection = NO;
            self.previousChannelListSelectedRow = newRow;
        }
    }
}

- (NSString *)displayNameForRecentChannelKey:(NSString *)channelKey {
    if (channelKey.length == 0) {
        return @"";
    }
    ChannelBuffer *buffer = self.channels[channelKey];
    NSString *name = buffer ? (buffer.name ?: @"") : ([self channelFromChannelKey:channelKey] ?: @"");
    NSString *server = [self serverFromChannelKey:channelKey];
    NSString *displayName = name;
    if (server.length > 0 && ![server isEqualToString:self.currentServer]) {
        displayName = [NSString stringWithFormat:@"%@ / %@", server, name];
    }
    if (buffer && buffer.unreadCount > 0) {
        displayName = [NSString stringWithFormat:@"%@ (%ld)", displayName, (long)buffer.unreadCount];
    }
    return displayName;
}

- (void)reloadChannelListForMode {
    if (!self.channelListView) {
        return;
    }
    
    self.isReloadingChannelList = YES;
    [self.channelListView reloadData];
    self.isReloadingChannelList = NO;
    
    // First deselect all to prevent auto-selection of first row
    [self.channelListView deselectAll:nil];
    
    if (self.channelListMode == ChannelListModeChannels) {
        for (NSString *server in self.serverOrder) {
            ChannelTreeItem *serverItem = self.serverItems[server];
            if (serverItem) {
                [self.channelListView expandItem:serverItem];
            }
        }
        if (self.currentChannelKey) {
            ChannelTreeItem *item = self.channelItems[self.currentChannelKey];
            NSInteger row = item ? [self.channelListView rowForItem:item] : -1;
            if (row >= 0) {
                self.isUpdatingChannelSelection = YES;
                [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
                self.isUpdatingChannelSelection = NO;
            }
        }
    } else if (self.channelListMode == ChannelListModeRecent) {
        if (self.currentChannelKey.length > 0) {
            ChannelTreeItem *item = [self recentItemForChannelKey:self.currentChannelKey];
            NSInteger row = item ? [self.channelListView rowForItem:item] : -1;
            if (row >= 0) {
                self.isUpdatingChannelSelection = YES;
                [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
                self.isUpdatingChannelSelection = NO;
            }
        }
    }
}

#pragma mark - Groups Management

- (void)loadCustomGroupsFromDefaults {
    // First try to load from SQLite
    NSString *jsonString = [[MessageStorage sharedStorage] getSettingForKey:kSettingCustomChannelGroups];
    CVLog(@"[Groups] Loading from SQLite, key=%@, jsonString=%@", kSettingCustomChannelGroups, jsonString);
    NSDictionary *rawGroups = nil;
    
    if (jsonString.length > 0) {
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        rawGroups = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        if (error || ![rawGroups isKindOfClass:[NSDictionary class]]) {
            CVLog(@"[Groups] JSON parse error: %@", error);
            rawGroups = nil;
        } else {
            CVLog(@"[Groups] Loaded groups from SQLite: %@", rawGroups);
        }
    }
    
    // If not in SQLite, try to migrate from NSUserDefaults
    if (!rawGroups) {
        id legacyGroups = [[NSUserDefaults standardUserDefaults] objectForKey:kChannelCustomGroupsDefaultsKey];
        if ([legacyGroups isKindOfClass:[NSDictionary class]]) {
            rawGroups = (NSDictionary *)legacyGroups;
            // Migrate to SQLite
            [self persistCustomGroupChannels:rawGroups];
            // Remove from NSUserDefaults
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kChannelCustomGroupsDefaultsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
    
    if ([rawGroups isKindOfClass:[NSDictionary class]]) {
        self.customGroupChannels = rawGroups;
        NSArray<NSString *> *keys = [self.customGroupChannels.allKeys sortedArrayUsingSelector:@selector(compare:)];
        self.customGroupOrder = keys ?: @[];
    } else {
        self.customGroupChannels = @{};
        self.customGroupOrder = @[];
    }
    
    [self.groupItems removeAllObjects];
    [self.groupChannelItems removeAllObjects];
    for (NSString *groupName in self.customGroupOrder) {
        ChannelTreeItem *item = [[ChannelTreeItem alloc] init];
        item.type = ChannelTreeItemTypeGroup;
        item.server = groupName;
        self.groupItems[groupName] = item;
    }
    
    if (!self.groupPlaceholderItem) {
        self.groupPlaceholderItem = [[ChannelTreeItem alloc] init];
        self.groupPlaceholderItem.type = ChannelTreeItemTypePlaceholder;
        self.groupPlaceholderItem.server = L(@"chat.group.empty", @"No groups");
    }
}

- (void)persistCustomGroupChannels:(NSDictionary<NSString *, NSArray<NSString *> *> *)groups {
    self.customGroupChannels = groups ?: @{};
    NSArray<NSString *> *keys = [self.customGroupChannels.allKeys sortedArrayUsingSelector:@selector(compare:)];
    self.customGroupOrder = keys ?: @[];
    
    [self.groupItems removeAllObjects];
    [self.groupChannelItems removeAllObjects];
    for (NSString *groupName in self.customGroupOrder) {
        ChannelTreeItem *item = [[ChannelTreeItem alloc] init];
        item.type = ChannelTreeItemTypeGroup;
        item.server = groupName;
        self.groupItems[groupName] = item;
    }
    
    // Save to SQLite as JSON
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:(groups ?: @{}) options:0 error:&error];
    if (!error && jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        BOOL success = [[MessageStorage sharedStorage] setSettingForKey:kSettingCustomChannelGroups value:jsonString];
        CVLog(@"[Groups] Saved to SQLite: key=%@, value=%@, success=%@", kSettingCustomChannelGroups, jsonString, success ? @"YES" : @"NO");
    } else {
        CVLog(@"[Groups] Failed to serialize groups: %@", error);
    }
    
    if (self.channelListMode == ChannelListModeGroups) {
        [self requestChannelListReload];
    }
}

- (BOOL)isChannelKey:(NSString *)channelKey inGroup:(NSString *)groupName {
    if (channelKey.length == 0 || groupName.length == 0) {
        return NO;
    }
    NSArray<NSString *> *channels = self.customGroupChannels[groupName];
    return channels && [channels containsObject:channelKey];
}

- (NSString *)existingGroupNameMatching:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    NSString *lowerName = [name lowercaseString];
    for (NSString *groupName in self.customGroupOrder) {
        if ([[groupName lowercaseString] isEqualToString:lowerName]) {
            return groupName;
        }
    }
    return nil;
}

#pragma mark - Persistence

- (void)persistServersAndChannels {
    if (self.isLoadingPersistedChannels) {
        return;
    }

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *channelsByServer = [[NSMutableDictionary alloc] init];
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *privateChatsByServer = [[NSMutableDictionary alloc] init];
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *joinedChannelsByServer = [[NSMutableDictionary alloc] init];
    for (NSString *server in self.serverOrder) {
        NSArray<NSString *> *channelKeys = self.serverChannelOrder[server];
        NSMutableArray<NSString *> *channels = [[NSMutableArray alloc] init];
        NSMutableArray<NSString *> *privateChats = [[NSMutableArray alloc] init];
        for (NSString *channelKey in channelKeys) {
            ChannelBuffer *buffer = self.channels[channelKey];
            if (!buffer || buffer.name.length == 0) {
                continue;
            }
            if (buffer.isPrivate) {
                [privateChats addObject:buffer.name];
            } else {
                [channels addObject:buffer.name];
            }
        }
        channelsByServer[server] = channels;
        privateChatsByServer[server] = privateChats;

        NSMutableSet<NSString *> *autoJoinSet = [self autoJoinChannelSetForServer:server createIfNeeded:NO];
        if (autoJoinSet) {
            joinedChannelsByServer[server] = [autoJoinSet allObjects];
        } else {
            joinedChannelsByServer[server] = @[];
        }
    }

    NSDictionary *payload = @{
        @"servers": self.serverOrder ?: @[],
        @"channelsByServer": channelsByServer ?: @{},
        @"privateChatsByServer": privateChatsByServer ?: @{},
        @"joinedChannelsByServer": joinedChannelsByServer ?: @{}
    };
    
    // Save to database
    [[MessageStorage sharedStorage] saveServersChannelsConfig:payload];
}

- (void)loadPersistedServersAndChannels {
    // Load from database
    NSDictionary *payload = [[MessageStorage sharedStorage] loadServersChannelsConfig];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSArray<NSString *> *servers = payload[@"servers"];
    NSDictionary<NSString *, NSArray<NSString *> *> *channelsByServer = payload[@"channelsByServer"];
    NSDictionary<NSString *, NSArray<NSString *> *> *privateChatsByServer = payload[@"privateChatsByServer"];
    NSDictionary<NSString *, NSArray<NSString *> *> *joinedChannelsByServer = payload[@"joinedChannelsByServer"];
    if (![servers isKindOfClass:[NSArray class]] || ![channelsByServer isKindOfClass:[NSDictionary class]]) {
        return;
    }

    self.isLoadingPersistedChannels = YES;
    for (NSString *server in servers) {
        [self addServerIfNeeded:server];
    }
    for (NSString *server in servers) {
        NSArray<NSString *> *channels = channelsByServer[server];
        if (![channels isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (NSString *channel in channels) {
            if (![channel isKindOfClass:[NSString class]] || channel.length == 0) {
                continue;
            }
            [self addPersistedChannel:server channel:channel];
        }
    }
    for (NSString *server in servers) {
        NSArray<NSString *> *privateChats = [privateChatsByServer isKindOfClass:[NSDictionary class]] ? privateChatsByServer[server] : nil;
        if (![privateChats isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (NSString *chat in privateChats) {
            if (![chat isKindOfClass:[NSString class]] || chat.length == 0) {
                continue;
            }
            [self addChannel:server channel:chat isPrivate:YES];
        }
    }
    for (NSString *server in servers) {
        NSArray<NSString *> *joined = [joinedChannelsByServer isKindOfClass:[NSDictionary class]] ? joinedChannelsByServer[server] : nil;
        if (![joined isKindOfClass:[NSArray class]]) {
            continue;
        }
        NSMutableSet<NSString *> *autoJoinSet = [self autoJoinChannelSetForServer:server createIfNeeded:YES];
        for (NSString *channel in joined) {
            if (![channel isKindOfClass:[NSString class]] || channel.length == 0) {
                continue;
            }
            [autoJoinSet addObject:channel];
        }
    }
    self.isLoadingPersistedChannels = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.isReloadingChannelList = YES;
        [self.channelListView reloadData];
        self.isReloadingChannelList = NO;
        
        for (NSString *server in self.serverOrder) {
            ChannelTreeItem *serverItem = self.serverItems[server];
            if (serverItem) {
                [self.channelListView expandItem:serverItem];
            }
        }
        
        // Clear selection after loading - don't auto-select anything
        [self.channelListView deselectAll:nil];
        self.previousChannelListSelectedRow = -1;
    });
}

@end
