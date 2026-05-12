//
//  ChatViewController+Menu.m
//  i3Chat
//
//  Menu handling for ChatViewController
//

#import "ChatViewController+Private.h"

@implementation ChatViewController (Menu)

#pragma mark - NSMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    // Disable auto-enabling so we can manually control menu item states
    menu.autoenablesItems = NO;
    
    if (menu == self.userListMenu) {
        [self buildUserListMenu:menu];
    } else if (menu == self.channelListMenu) {
        [self buildChannelListMenu:menu];
    } else if (menu == self.favoritesMenu) {
        [self buildFavoritesMenu:menu];
    }
}

#pragma mark - User List Menu

- (void)buildUserListMenu:(NSMenu *)menu {
    NSInteger row = self.userListView.clickedRow;
    if (row < 0) {
        return;
    }
    
    NSArray<NSString *> *users = [self displayedUsersForCurrentChannel];
    if (row >= (NSInteger)users.count) {
        return;
    }
    
    NSString *user = users[row];
    
    NSMenuItem *whoisItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.whois", @"WHOIS")
                                                       action:@selector(handleUserWhoisFromMenu:)
                                                keyEquivalent:@""];
    whoisItem.target = self;
    whoisItem.representedObject = user;
    [menu addItem:whoisItem];
    
    NSMenuItem *privateItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.privateMessage", @"Private Message")
                                                         action:@selector(handleUserPrivateMessageFromMenu:)
                                                  keyEquivalent:@""];
    privateItem.target = self;
    privateItem.representedObject = user;
    [menu addItem:privateItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *inviteItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.invite", @"Invite to Channel...")
                                                        action:@selector(handleUserInviteFromMenu:)
                                                 keyEquivalent:@""];
    inviteItem.target = self;
    inviteItem.representedObject = user;
    [menu addItem:inviteItem];
}

- (void)handleUserPrivateMessageFromMenu:(id)sender {
    NSString *user = [sender representedObject];
    NSString *nick = [self baseNickFromUserListEntry:user];
    if (nick.length == 0) {
        return;
    }
    
    ChannelBuffer *buffer = self.currentChannelKey ? self.channels[self.currentChannelKey] : nil;
    NSString *server = buffer.server.length > 0 ? buffer.server : self.currentServer;
    if (server.length > 0) {
        [self addChannel:server channel:nick isPrivate:YES];
        NSString *channelKey = [self makeChannelKey:server channel:nick];
        [self switchToChannel:channelKey];
    }
}

#pragma mark - Channel List Menu

- (void)buildChannelListMenu:(NSMenu *)menu {
    NSInteger row = self.channelListView.clickedRow;
    
    // If clicked on empty space or invalid row, show "Join Server" option
    if (row < 0 || row >= self.channelListView.numberOfRows) {
        NSMenuItem *joinServerItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.joinServer", @"Join Server")
                                                                action:@selector(handleJoinServerFromMenu:)
                                                         keyEquivalent:@""];
        joinServerItem.target = self;
        [menu addItem:joinServerItem];
        return;
    }
    
    ChannelTreeItem *treeItem = [self.channelListView itemAtRow:row];
    if (![treeItem isKindOfClass:[ChannelTreeItem class]]) {
        NSMenuItem *joinServerItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.joinServer", @"Join Server")
                                                                action:@selector(handleJoinServerFromMenu:)
                                                         keyEquivalent:@""];
        joinServerItem.target = self;
        [menu addItem:joinServerItem];
        return;
    }
    
    // Select the clicked row
    [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    
    if (treeItem.type == ChannelTreeItemTypeServer) {
        [self buildServerContextMenu:menu forServer:treeItem.server];
    } else if (treeItem.type == ChannelTreeItemTypeGroup) {
        [self buildGroupContextMenu:menu forGroupName:treeItem.server];
    } else if (treeItem.type == ChannelTreeItemTypeChannel || treeItem.type == ChannelTreeItemTypeRecent) {
        [self buildChannelContextMenu:menu forItem:treeItem];
    }
}

- (void)buildServerContextMenu:(NSMenu *)menu forServer:(NSString *)server {
    if (!server || server.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:server];
    BOOL isConnected = client && client.isConnected && ![self.disconnectedServers containsObject:server];
    // isRegistered means fully registered with server (received 001 RPL_WELCOME)
    // Only enable channel operations after registration is complete
    BOOL isRegistered = client && client.isRegistered;
    
    // Connect/Disconnect toggle
    NSString *toggleTitle = isConnected ? L(@"chat.menu.disconnect", @"Disconnect") : L(@"chat.menu.connect", @"Connect");
    NSMenuItem *toggleItem = [[NSMenuItem alloc] initWithTitle:toggleTitle
                                                        action:@selector(handleServerToggleConnection:)
                                                 keyEquivalent:@""];
    toggleItem.target = self;
    toggleItem.representedObject = server;
    [menu addItem:toggleItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Channel List - requires registered
    NSMenuItem *listItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.channelList", @"Channel List")
                                                      action:@selector(handleServerList:)
                                               keyEquivalent:@""];
    listItem.target = self;
    listItem.representedObject = server;
    listItem.enabled = isRegistered;
    [menu addItem:listItem];
    
    // Change Nickname - requires registered
    NSMenuItem *nickItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.changeNickname", @"Change Nickname")
                                                      action:@selector(handleServerChangeNick:)
                                               keyEquivalent:@""];
    nickItem.target = self;
    nickItem.representedObject = server;
    nickItem.enabled = isRegistered;
    [menu addItem:nickItem];
    
    // Join Channel - requires registered
    NSMenuItem *joinItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.joinChannel", @"Join Channel")
                                                      action:@selector(handleServerJoinChannel:)
                                               keyEquivalent:@""];
    joinItem.target = self;
    joinItem.representedObject = server;
    joinItem.enabled = isRegistered;
    [menu addItem:joinItem];
    
    // Server Links - requires connected (same as main menu Links command)
    NSMenuItem *linksItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.serverLinks", @"Server Links")
                                                       action:@selector(handleServerLinksFromMenu:)
                                                keyEquivalent:@""];
    linksItem.target = self;
    linksItem.representedObject = server;
    linksItem.enabled = isConnected;
    [menu addItem:linksItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Delete Server - only enabled when disconnected
    NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.deleteServer", @"Delete Server")
                                                        action:@selector(handleDeleteServerFromMenu:)
                                                 keyEquivalent:@""];
    deleteItem.target = self;
    deleteItem.representedObject = server;
    deleteItem.enabled = !isConnected;  // Only allow deletion when disconnected
    [menu addItem:deleteItem];
}

- (void)buildGroupContextMenu:(NSMenu *)menu forGroupName:(NSString *)groupName {
    if (!groupName || groupName.length == 0) {
        return;
    }
    
    NSMenuItem *deleteGroupItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.deleteGroup", @"Delete Group")
                                                             action:@selector(handleDeleteGroupFromMenu:)
                                                      keyEquivalent:@""];
    deleteGroupItem.target = self;
    deleteGroupItem.representedObject = groupName;
    [menu addItem:deleteGroupItem];
}

- (void)buildChannelContextMenu:(NSMenu *)menu forItem:(ChannelTreeItem *)treeItem {
    NSString *channelKey = treeItem.channelKey;
    ChannelBuffer *buffer = channelKey ? self.channels[channelKey] : nil;
    
    if (!buffer && treeItem.type == ChannelTreeItemTypeRecent) {
        NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.removeFromHistory", @"Remove from History")
                                                            action:@selector(handleRemoveFromRecentFromMenu:)
                                                     keyEquivalent:@""];
        removeItem.target = self;
        removeItem.representedObject = channelKey;
        [menu addItem:removeItem];
        return;
    }
    if (!buffer) {
        return;
    }

    IRCClient *client = [self clientForServer:buffer.server];
    BOOL isConnected = client && client.isConnected && ![self.disconnectedServers containsObject:buffer.server];
    NSMutableSet<NSString *> *joinedSet = [self joinedChannelSetForServer:buffer.server createIfNeeded:NO];
    BOOL isJoined = buffer.isPrivate ? YES : (joinedSet && [joinedSet containsObject:buffer.name]);

    // Join/Part/Close action
    NSString *title = @"";
    SEL action = nil;
    if (buffer.isPrivate) {
        title = L(@"chat.menu.closePrivate", @"Close Private Chat");
        action = @selector(handleClosePrivateChat:);
    } else if (isConnected && isJoined) {
        title = L(@"chat.menu.leaveChannel", @"Leave Channel");
        action = @selector(handlePartChannel:);
    } else {
        title = L(@"chat.menu.join", @"Join");
        action = @selector(handleJoinChannelFromMenu:);
    }
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    menuItem.target = self;
    menuItem.representedObject = channelKey;
    if (!buffer.isPrivate) {
        menuItem.enabled = isConnected;
    }
    [menu addItem:menuItem];

    if (!buffer.isPrivate) {
        NSMenuItem *deleteChannelItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.deleteChannel", @"Delete Channel")
                                                                   action:@selector(handleDeleteChannelFromMenu:)
                                                            keyEquivalent:@""];
        deleteChannelItem.target = self;
        deleteChannelItem.representedObject = channelKey;
        [menu addItem:deleteChannelItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // Change Topic - only for non-private channels that are joined
    if (!buffer.isPrivate && isConnected && isJoined) {
        NSMenuItem *changeTopicItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.changeTopic", @"Change Topic")
                                                                  action:@selector(handleChangeChannelTopic:)
                                                           keyEquivalent:@""];
        changeTopicItem.target = self;
        changeTopicItem.representedObject = channelKey;
        [menu addItem:changeTopicItem];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    // Group submenu
    [self addGroupSubmenuToMenu:menu forChannelKey:channelKey];

    [menu addItem:[NSMenuItem separatorItem]];

    // History
    NSMenuItem *historyItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.viewLocalHistory", @"View Local History")
                                                         action:@selector(handleShowHistoryFromMenu:)
                                                  keyEquivalent:@""];
    historyItem.target = self;
    historyItem.representedObject = channelKey;
    [menu addItem:historyItem];
    
    // Toggle message storage
    NSMenuItem *storageItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.toggleMessageStorage", @"Allow Message Storage")
                                                         action:@selector(handleToggleMessageStorage:)
                                                  keyEquivalent:@""];
    storageItem.target = self;
    storageItem.representedObject = channelKey;
    storageItem.state = buffer.allowMessageStorage ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:storageItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.clearHistory", @"Clear history")
                                                       action:@selector(handleClearHistoryFromMenu:)
                                                keyEquivalent:@""];
    clearItem.target = self;
    clearItem.representedObject = channelKey;
    [menu addItem:clearItem];

    if (treeItem.type == ChannelTreeItemTypeRecent) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.removeFromHistory", @"Remove from History")
                                                            action:@selector(handleRemoveFromRecentFromMenu:)
                                                     keyEquivalent:@""];
        removeItem.target = self;
        removeItem.representedObject = channelKey;
        [menu addItem:removeItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // Background color
    NSMenuItem *setColorItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.setBackgroundColor", @"Set Background Color")
                                                          action:@selector(handleSetBackgroundColorFromMenu:)
                                                   keyEquivalent:@""];
    setColorItem.target = self;
    setColorItem.representedObject = channelKey;
    [menu addItem:setColorItem];

    NSMenuItem *resetColorItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.resetBackgroundColor", @"Reset Background Color")
                                                            action:@selector(handleResetBackgroundColorFromMenu:)
                                                     keyEquivalent:@""];
    resetColorItem.target = self;
    resetColorItem.representedObject = channelKey;
    resetColorItem.enabled = [self hasBackgroundColorForChannelKey:channelKey];
    [menu addItem:resetColorItem];
}

- (void)addGroupSubmenuToMenu:(NSMenu *)menu forChannelKey:(NSString *)channelKey {
    NSMenuItem *groupMenuItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.addToGroup", @"Add to Group")
                                                           action:nil
                                                    keyEquivalent:@""];
    NSMenu *groupMenu = [[NSMenu alloc] initWithTitle:@"AddToGroup"];
    if (self.customGroupOrder.count == 0) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.group.empty", @"No groups")
                                                           action:nil
                                                    keyEquivalent:@""];
        emptyItem.enabled = NO;
        [groupMenu addItem:emptyItem];
    } else {
        for (NSString *groupName in self.customGroupOrder) {
            NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:groupName
                                                               action:@selector(handleAddChannelToGroup:)
                                                        keyEquivalent:@""];
            groupItem.target = self;
            groupItem.representedObject = @{
                ChannelGroupInfoGroupKey: groupName ?: @"",
                ChannelGroupInfoChannelKey: channelKey ?: @""
            };
            groupItem.state = [self isChannelKey:channelKey inGroup:groupName] ? NSControlStateValueOn : NSControlStateValueOff;
            [groupMenu addItem:groupItem];
        }
    }
    [groupMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *newGroupItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.newGroup", @"New Group...")
                                                          action:@selector(handleCreateGroupFromMenu:)
                                                   keyEquivalent:@""];
    newGroupItem.target = self;
    newGroupItem.representedObject = channelKey;
    [groupMenu addItem:newGroupItem];
    groupMenuItem.submenu = groupMenu;
    [menu addItem:groupMenuItem];

    // Remove from group submenu
    NSMenuItem *removeGroupMenuItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.removeFromGroup", @"Remove from Group")
                                                                 action:nil
                                                          keyEquivalent:@""];
    NSMenu *removeGroupMenu = [[NSMenu alloc] initWithTitle:@"RemoveFromGroup"];
    BOOL hasGroupsToRemove = NO;
    for (NSString *groupName in self.customGroupOrder) {
        if ([self isChannelKey:channelKey inGroup:groupName]) {
            NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:groupName
                                                                action:@selector(handleRemoveChannelFromGroup:)
                                                         keyEquivalent:@""];
            removeItem.target = self;
            removeItem.representedObject = @{
                ChannelGroupInfoGroupKey: groupName ?: @"",
                ChannelGroupInfoChannelKey: channelKey ?: @""
            };
            [removeGroupMenu addItem:removeItem];
            hasGroupsToRemove = YES;
        }
    }
    if (!hasGroupsToRemove) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.group.empty", @"No groups")
                                                           action:nil
                                                    keyEquivalent:@""];
        emptyItem.enabled = NO;
        [removeGroupMenu addItem:emptyItem];
    }
    removeGroupMenuItem.submenu = removeGroupMenu;
    [menu addItem:removeGroupMenuItem];
}

#pragma mark - Favorites Menu

- (void)buildFavoritesMenu:(NSMenu *)menu {
    NSInteger row = self.favoritesTableView.clickedRow;
    if (row < 0) {
        return;
    }
    
    NSArray<NSDictionary *> *items = [self filteredFavoriteItems];
    if (row >= (NSInteger)items.count) {
        return;
    }
    
    // Copy menu item
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.copy", @"Copy")
                                                      action:@selector(handleFavoritesCopy:)
                                               keyEquivalent:@""];
    copyItem.target = self;
    copyItem.representedObject = @(row);
    copyItem.enabled = YES;
    [menu addItem:copyItem];
    
    // Delete menu item
    NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.delete", @"Delete")
                                                        action:@selector(handleFavoritesDelete:)
                                                 keyEquivalent:@""];
    deleteItem.target = self;
    deleteItem.representedObject = @(row);
    deleteItem.enabled = YES;
    [menu addItem:deleteItem];
}

- (void)handleFavoritesCopy:(id)sender {
    NSNumber *rowNum = [sender representedObject];
    if (![rowNum isKindOfClass:[NSNumber class]]) {
        return;
    }
    NSInteger row = rowNum.integerValue;
    NSArray<NSDictionary *> *items = [self filteredFavoriteItems];
    if (row < 0 || row >= (NSInteger)items.count) {
        return;
    }
    
    NSDictionary *item = items[row];
    NSString *text = [self displayTextForFavoriteItem:item];
    
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

- (void)handleFavoritesOpen:(id)sender {
    NSNumber *rowNum = [sender representedObject];
    if (![rowNum isKindOfClass:[NSNumber class]]) {
        return;
    }
    NSInteger row = rowNum.integerValue;
    NSArray<NSDictionary *> *items = [self filteredFavoriteItems];
    if (row < 0 || row >= (NSInteger)items.count) {
        return;
    }
    
    NSDictionary *item = items[row];
    NSString *urlString = item[@"url"];
    if ([urlString isKindOfClass:[NSString class]] && urlString.length > 0) {
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
    }
}

- (void)handleFavoritesDelete:(id)sender {
    NSNumber *rowNum = [sender representedObject];
    if (![rowNum isKindOfClass:[NSNumber class]]) {
        return;
    }
    NSInteger row = rowNum.integerValue;
    [self removeFavoriteItemAtIndex:row];
}

#pragma mark - Chat Context Menu

- (NSMenu *)chatMenuForEvent:(NSEvent *)event inTextView:(NSTextView *)textView {
    NSLog(@"[Menu] chatMenuForEvent:inTextView: called, textView=%@", textView);
    if (!textView || textView.string.length == 0) {
        NSLog(@"[Menu] chatMenuForEvent: no textView or empty string");
        return nil;
    }

    NSPoint point = event ? [textView convertPoint:event.locationInWindow fromView:nil] : NSMakePoint(0, 0);
    if (event && !NSPointInRect(point, textView.bounds)) {
        NSLog(@"[Menu] chatMenuForEvent: point not in bounds");
        return nil;
    }

    NSUInteger resolvedIndex = NSNotFound;
    if (event) {
        resolvedIndex = [textView characterIndexForInsertionAtPoint:point];
    }
    if (resolvedIndex == NSNotFound || resolvedIndex >= textView.string.length) {
        NSLog(@"[Menu] chatMenuForEvent: invalid resolvedIndex=%lu", (unsigned long)resolvedIndex);
        return nil;
    }

    NSString *lineText = [self lineTextForCharacterIndex:resolvedIndex inTextView:textView];
    NSLog(@"[Menu] chatMenuForEvent: lineText=%@", lineText);
    if (lineText.length == 0) {
        NSLog(@"[Menu] chatMenuForEvent: lineText is empty");
        return nil;
    }

    NSLog(@"[Menu] chatMenuForEvent: creating context menu with lineText");
    NSMenu *contextMenu = [[NSMenu alloc] initWithTitle:@"ChatContextMenu"];
    
    // Copy item - use selected text if available, otherwise use current line
    NSString *copyText = [self selectedTextInTextView:textView];
    if (copyText.length == 0) {
        copyText = lineText;
    }
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.copy", @"Copy")
                                                      action:@selector(handleCopyFromMenu:)
                                               keyEquivalent:@""];
    copyItem.target = self;
    copyItem.representedObject = copyText;
    copyItem.keyEquivalent = @"c";
    copyItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [contextMenu addItem:copyItem];
    [contextMenu addItem:[NSMenuItem separatorItem]];

    // Favorite current line
    NSMenuItem *favoriteLineItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.favorite.line", @"Favorite Message")
                                                              action:@selector(handleFavoriteLineFromMenu:)
                                                       keyEquivalent:@""];
    favoriteLineItem.target = self;
    favoriteLineItem.representedObject = lineText;
    [contextMenu addItem:favoriteLineItem];

    // Favorite URLs found in the line
    NSArray<NSString *> *urls = [self urlsInString:lineText];
    if (urls.count > 0) {
        [contextMenu addItem:[NSMenuItem separatorItem]];
        for (NSString *url in urls) {
            NSString *title = [NSString stringWithFormat:L(@"chat.favorite.link", @"Favorite Link: %@"), url];
            NSMenuItem *favoriteLinkItem = [[NSMenuItem alloc] initWithTitle:title
                                                                       action:@selector(handleFavoriteURLFromMenu:)
                                                                keyEquivalent:@""];
            favoriteLinkItem.target = self;
            favoriteLinkItem.representedObject = url;
            [contextMenu addItem:favoriteLinkItem];
        }
    }
    
    // Clear screen
    [contextMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clearScreenItem = [[NSMenuItem alloc] initWithTitle:L(@"chat.menu.clearScreen", @"Clear Screen")
                                                             action:@selector(handleClearScreen:)
                                                      keyEquivalent:@""];
    clearScreenItem.target = self;
    [contextMenu addItem:clearScreenItem];
    
    return contextMenu;
}

- (NSString *)lineTextForCharacterIndex:(NSUInteger)index inTextView:(NSTextView *)textView {
    if (!textView || index >= textView.string.length) {
        return @"";
    }
    NSRange lineRange = [textView.string lineRangeForRange:NSMakeRange(index, 0)];
    NSString *line = [textView.string substringWithRange:lineRange];
    return [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] ?: @"";
}

- (NSString *)selectedTextInTextView:(NSTextView *)textView {
    if (!textView) {
        return @"";
    }
    NSRange range = textView.selectedRange;
    if (range.length == 0 || range.location + range.length > textView.string.length) {
        return @"";
    }
    return [textView.string substringWithRange:range];
}

- (NSArray<NSString *> *)urlsInString:(NSString *)string {
    if (string.length == 0) {
        return @[];
    }
    NSError *error = nil;
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
    if (!detector || error) {
        return @[];
    }
    NSMutableArray<NSString *> *urls = [[NSMutableArray alloc] init];
    [detector enumerateMatchesInString:string
                               options:0
                                 range:NSMakeRange(0, string.length)
                            usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        if (!result || result.resultType != NSTextCheckingTypeLink) {
            return;
        }
        NSString *urlString = result.URL.absoluteString ?: @"";
        if (urlString.length == 0) {
            return;
        }
        [urls addObject:urlString];
    }];
    return [urls copy];
}

- (void)handleCopyFromMenu:(id)sender {
    NSString *text = [sender representedObject];
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

- (void)handleFavoriteLineFromMenu:(id)sender {
    NSLog(@"[Menu] handleFavoriteLineFromMenu called with sender=%@", sender);
    NSString *line = [sender representedObject];
    NSLog(@"[Menu] handleFavoriteLineFromMenu: line=%@", line);
    if (![line isKindOfClass:[NSString class]] || line.length == 0) {
        NSLog(@"[Menu] handleFavoriteLineFromMenu: invalid line, returning");
        return;
    }
    NSLog(@"[Menu] handleFavoriteLineFromMenu: calling addFavoriteItemWithType");
    [self addFavoriteItemWithType:@"line" content:line url:nil];
}

- (void)handleFavoriteURLFromMenu:(id)sender {
    NSLog(@"[Menu] handleFavoriteURLFromMenu called with sender=%@", sender);
    NSString *url = [sender representedObject];
    NSLog(@"[Menu] handleFavoriteURLFromMenu: url=%@", url);
    if (![url isKindOfClass:[NSString class]] || url.length == 0) {
        NSLog(@"[Menu] handleFavoriteURLFromMenu: invalid url, returning");
        return;
    }
    NSLog(@"[Menu] handleFavoriteURLFromMenu: calling addFavoriteItemWithType");
    [self addFavoriteItemWithType:@"url" content:url url:url];
}

- (void)handleClearScreen:(id)sender {
    // Clear the current channel's message buffer and display
    if (!self.currentChannelKey) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[self.currentChannelKey];
    if (buffer) {
        [buffer.messages removeAllObjects];
    }
    
    // Clear cached attributed messages
    [self.cachedAttributedMessages removeObjectForKey:self.currentChannelKey];
    [self.lastRenderedMessageCount removeObjectForKey:self.currentChannelKey];
    
    // Clear the text view
    self.chatTextView.string = @"";
}

- (void)handleFavoritesCopyShortcutFromTextView:(NSTextView *)textView {
    NSRange selectedRange = textView.selectedRange;
    if (selectedRange.length > 0) {
        NSString *selectedText = [textView.string substringWithRange:selectedRange];
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:selectedText forType:NSPasteboardTypeString];
    }
}

- (void)handleFavoritesOpenShortcutFromTextView:(NSTextView *)textView {
    NSRange selectedRange = textView.selectedRange;
    if (selectedRange.length > 0) {
        NSString *selectedText = [[textView.string substringWithRange:selectedRange] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (selectedText.length > 0) {
            NSURL *url = [NSURL URLWithString:selectedText];
            if (url && url.scheme) {
                [[NSWorkspace sharedWorkspace] openURL:url];
            }
        }
    }
}

#pragma mark - Menu Actions

- (NSString *)baseNickFromUserListEntry:(NSString *)user {
    if (!user) {
        return @"";
    }
    NSString *trimmed = [user stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @"";
    }
    NSCharacterSet *modePrefixes = [NSCharacterSet characterSetWithCharactersInString:@"@+%&~"];
    while (trimmed.length > 0) {
        unichar firstChar = [trimmed characterAtIndex:0];
        if (![modePrefixes characterIsMember:firstChar]) {
            break;
        }
        trimmed = [trimmed substringFromIndex:1];
    }
    return trimmed;
}

- (void)handleUserWhoisFromMenu:(id)sender {
    NSString *user = [sender representedObject];
    NSString *nick = [self baseNickFromUserListEntry:user];
    if (nick.length == 0) {
        return;
    }

    ChannelBuffer *buffer = self.currentChannelKey ? self.channels[self.currentChannelKey] : nil;
    NSString *server = buffer.server.length > 0 ? buffer.server : self.currentServer;
    IRCClient *client = [self clientForServer:server];
    if (client && client.isConnected && ![self.disconnectedServers containsObject:server]) {
        // Set pending whois nick and server to receive and display the result in a window
        self.pendingWhoisNick = nick;
        self.pendingWhoisServer = server;
        
        // Create and show window with loading state
        self.whoisWindowController = [[WhoisWindowController alloc] initWithNickname:nick server:server];
        self.whoisWindowController.delegate = self;
        [self.whoisWindowController showWindow:nil];
        [self.whoisWindowController.window makeKeyAndOrderFront:nil];
        
        // Send the WHOIS command
        [client sendRawCommand:[NSString stringWithFormat:@"WHOIS %@", nick]];
    }
}

#pragma mark - WhoisWindowControllerDelegate

- (void)whoisWindowController:(WhoisWindowController *)controller didRequestJoinChannel:(NSString *)channel {
    NSString *server = controller.server ?: self.currentServer;
    if (server.length == 0 || channel.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:server];
    if (client && client.isConnected && ![self.disconnectedServers containsObject:server]) {
        [client joinChannel:channel];
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.joiningChannel", @"Joining channel %@..."), channel] forServer:server];
    }
}

- (void)handleUserInviteFromMenu:(id)sender {
    NSString *user = [sender representedObject];
    NSString *nick = [self baseNickFromUserListEntry:user];
    if (nick.length == 0) {
        return;
    }

    ChannelBuffer *buffer = self.currentChannelKey ? self.channels[self.currentChannelKey] : nil;
    NSString *server = buffer.server.length > 0 ? buffer.server : self.currentServer;
    IRCClient *client = [self clientForServer:server];
    if (!client || !client.isConnected || [self.disconnectedServers containsObject:server]) {
        return;
    }

    NSMutableSet<NSString *> *joinedSet = [self joinedChannelSetForServer:server createIfNeeded:NO];
    NSMutableSet<NSString *> *channelSet = joinedSet ? [joinedSet mutableCopy] : [[NSMutableSet alloc] init];
    if (channelSet.count == 0) {
        for (ChannelBuffer *candidate in self.channels.allValues) {
            if (!candidate || candidate.isPrivate) {
                continue;
            }
            if (![candidate.server isEqualToString:server]) {
                continue;
            }
            if ([self isChannelJoined:candidate] && candidate.name.length > 0) {
                [channelSet addObject:candidate.name];
            }
        }
    }

    NSArray<NSString *> *channels = [[channelSet allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (channels.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = L(@"prompt.inviteChannel.title", @"Invite to Channel");
        alert.informativeText = L(@"prompt.inviteChannel.empty", @"No joined channels available.");
        [alert addButtonWithTitle:L(@"chat.prompt.ok", @"OK")];
        [alert runModal];
        return;
    }

    NSString *preferredChannel = (buffer && !buffer.isPrivate) ? buffer.name : @"";
    NSString *channel = [self promptForChannelFromList:channels
                                                 title:L(@"prompt.inviteChannel.title", @"Invite to Channel")
                                               message:L(@"prompt.inviteChannel.listMessage", @"Select a channel to invite")
                                     preferredChannel:preferredChannel];
    if (channel.length == 0) {
        return;
    }

    [client sendRawCommand:[NSString stringWithFormat:@"INVITE %@ %@", nick, channel]];
}

- (void)handleJoinChannelFromMenu:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer) {
        return;
    }
    
    IRCClient *client = [self clientForServer:buffer.server];
    if (client && client.isConnected && ![self.disconnectedServers containsObject:buffer.server]) {
        [client joinChannel:buffer.name];
    }
}

- (void)handlePartChannel:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer || buffer.isPrivate) {
        return;
    }
    
    IRCClient *client = [self clientForServer:buffer.server];
    if (client && client.isConnected && ![self.disconnectedServers containsObject:buffer.server]) {
        [client sendRawCommand:[NSString stringWithFormat:@"PART %@", buffer.name]];
    }
}

- (void)handleChangeChannelTopic:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer || buffer.isPrivate) {
        return;
    }
    
    IRCClient *client = [self clientForServer:buffer.server];
    if (!client || !client.isConnected || [self.disconnectedServers containsObject:buffer.server]) {
        return;
    }
    
    // Check if channel is joined
    NSMutableSet<NSString *> *joinedSet = [self joinedChannelSetForServer:buffer.server createIfNeeded:NO];
    BOOL isJoined = joinedSet && [joinedSet containsObject:buffer.name];
    if (!isJoined) {
        return;
    }
    
    // Prompt for new topic
    NSString *newTopic = [self promptForInputWithTitle:L(@"chat.prompt.changeTopic.title", @"Change Topic")
                                                message:[NSString stringWithFormat:L(@"chat.prompt.changeTopic.message", @"Enter new topic for %@:"), buffer.name]
                                            placeholder:L(@"chat.prompt.changeTopic.placeholder", @"Channel topic")];
    if (newTopic.length > 0) {
        // Send TOPIC command: TOPIC #channel :topic text
        [client sendRawCommand:[NSString stringWithFormat:@"TOPIC %@ :%@", buffer.name, newTopic]];
    }
}

- (void)handleClosePrivateChat:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    [self removeChannelWithKey:channelKey];
}

- (void)handleDeleteChannelFromMenu:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    [self removeChannelWithKey:channelKey];
    [self persistServersAndChannels];
}

- (void)handleConnectServerFromMenu:(id)sender {
    NSString *server = [sender representedObject];
    if (!server || server.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:server];
    BOOL isConnected = client && client.isConnected && ![self.disconnectedServers containsObject:server];
    if (!isConnected) {
        IRCConfig *config = [self ensureConfigForServer:server];
        if ([server hasSuffix:@":6697"]) config.useTLS = YES;
        else if ([server hasSuffix:@":6667"]) config.useTLS = NO;
        if (![self promptForConnectOptionsForServer:server config:config]) {
            return;
        }
    }
    
    client = [self clientForServer:server];
    if (client) {
        [client connect];
    } else {
        IRCConfig *config = [self ensureConfigForServer:server];
        client = [[IRCClient alloc] initWithConfig:config];
        client.delegate = self;
        self.ircClients[server] = client;
        [client connect];
    }
}

- (void)handleDisconnectServerFromMenu:(id)sender {
    NSString *server = [sender representedObject];
    if (!server || server.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:server];
    if (client) {
        [client disconnect];
    }
}

- (void)handleServerToggleConnection:(id)sender {
    NSString *server = [sender representedObject];
    if (!server || server.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:server];
    BOOL isConnected = client && client.isConnected && ![self.disconnectedServers containsObject:server];
    
    if (isConnected) {
        [self handleDisconnectServerFromMenu:sender];
    } else {
        [self handleConnectServerFromMenu:sender];
    }
}

- (void)handleServerList:(id)sender {
    NSString *server = [sender representedObject];
    if (!server || server.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:server];
    if (client && client.isConnected) {
        self.channelListServer = server;
        
        // Get or create channel list window controller for this server
        ChannelListWindowController *controller = self.channelListWindowControllers[server];
        if (!controller) {
            controller = [[ChannelListWindowController alloc] initWithServerAddress:server];
            controller.delegate = self;
            self.channelListWindowControllers[server] = controller;
        }
        [controller clearChannels];
        [controller showWindow:nil];
        [client sendRawCommand:@"LIST"];
    }
}

- (void)handleServerChangeNick:(id)sender {
    NSString *server = [sender representedObject];
    if (!server || server.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:server];
    if (!client || !client.isConnected) {
        return;
    }
    
    IRCConfig *config = [self configForServer:server];
    NSString *currentNick = config.nick ?: @"";
    NSString *newNick = [[self promptForInputWithTitle:L(@"chat.prompt.changeNick.title", @"Change Nickname")
                                                message:[NSString stringWithFormat:L(@"chat.prompt.changeNick.message", @"Current nickname: %@"), currentNick]
                                            placeholder:L(@"chat.prompt.changeNick.placeholder", @"New nickname")] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (newNick.length > 0) {
        [client sendRawCommand:[NSString stringWithFormat:@"NICK %@", newNick]];
        if (config) config.nick = newNick;
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.changingNick", @"Changing nickname to %@..."), newNick]];
        [self updateStatus];
    }
}

- (void)handleServerJoinChannel:(id)sender {
    NSString *server = [sender representedObject];
    if (!server || server.length == 0) {
        return;
    }
    
    IRCClient *client = [self clientForServer:server];
    if (!client || !client.isConnected) {
        return;
    }
    
    NSString *channel = [self promptForInputWithTitle:L(@"chat.prompt.joinChannel.title", @"Join Channel")
                                              message:L(@"chat.prompt.joinChannel.message", @"Enter channel name:")
                                          placeholder:L(@"chat.prompt.joinChannel.placeholder", @"#channel")];
    if (channel.length > 0) {
        if (![channel hasPrefix:@"#"] && ![channel hasPrefix:@"&"]) {
            channel = [@"#" stringByAppendingString:channel];
        }
        [client joinChannel:channel];
    }
}

- (void)handleServerLinksFromMenu:(id)sender {
    NSString *server = [sender representedObject];
    if (!server || server.length == 0) {
        return;
    }
    IRCClient *client = [self clientForServer:server];
    if (!client || !client.isConnected || [self.disconnectedServers containsObject:server]) {
        return;
    }
    NSString *mask = [self promptForInputWithTitle:L(@"prompt.serverLinks.title", @"Server Links")
                                            message:L(@"prompt.serverLinks.message", @"Enter server mask (optional)")
                                        placeholder:L(@"prompt.serverLinks.placeholder", @"*.libera.chat")];
    NSArray *parts = mask.length > 0 ? @[@"links", mask] : @[@"links"];
    [self handleLinksCommand:parts activeServer:server activeClient:client];
}

- (void)handleJoinServerFromMenu:(id)sender {
    NSString *serverAddress = [self promptForInputWithTitle:L(@"chat.prompt.joinServer.title", @"Join Server")
                                                    message:L(@"chat.prompt.joinServer.message", @"Enter server address:")
                                                placeholder:L(@"chat.prompt.joinServer.placeholder", @"irc.example.com")];
    if (serverAddress.length == 0) {
        return;
    }
    
    // Get config info from current server or first config
    IRCConfig *activeConfig = nil;
    if (self.currentServer.length > 0) {
        activeConfig = [self configForServer:self.currentServer];
    }
    if (!activeConfig && self.configs.count > 0) {
        activeConfig = self.configs[0];
    }
    
    NSString *nick = activeConfig ? activeConfig.nick : @"user-i3chat";
    NSString *realName = activeConfig ? activeConfig.realName : @"macOS IRC Client";
    BOOL useTLS = [serverAddress hasSuffix:@":6697"];
    
    // Check if server already exists
    CVLog(@"handleJoinServerFromMenu: serverAddress=%@, serverOrder contains=%@", serverAddress, [self.serverOrder containsObject:serverAddress] ? @"YES" : @"NO");
    if ([self.serverOrder containsObject:serverAddress]) {
        // Server already exists, try to connect
        IRCClient *client = [self clientForServer:serverAddress];
        if (client && !client.isConnected) {
            [client connect];
        }
        [self selectServer:serverAddress];
        
        // Still save to history to update last_connected time
        CVLog(@"handleJoinServerFromMenu: Server exists, saving to history");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            BOOL success = [[ServerHistoryStorage sharedStorage] touchLoginHistoryWithServer:serverAddress
                                                                         nick:nick
                                                                      channel:@""
                                                                     realName:realName
                                                                       useTLS:useTLS];
            CVLog(@"handleJoinServerFromMenu (existing): touchLoginHistoryWithServer returned %@", success ? @"YES" : @"NO");
        });
        return;
    }
    
    // Add new server - need to create config and client first
    CVLog(@"handleJoinServerFromMenu: Adding new server %@", serverAddress);
    
    // Create config for new server
    NSString *user = activeConfig ? activeConfig.user : @"macirc";
    NSString *password = activeConfig ? activeConfig.password : nil;
    
    IRCConfig *newConfig = [[IRCConfig alloc] initWithServer:serverAddress
                                                        nick:nick
                                                        user:user
                                                    realName:realName
                                                     channel:@""
                                                    password:password
                                                      useTLS:useTLS];
    self.serverConfigs[serverAddress] = newConfig;
    
    NSMutableArray<IRCConfig *> *configs = [self.configs mutableCopy];
    [configs addObject:newConfig];
    self.configs = configs;
    
    BOOL added = [self addServerIfNeeded:serverAddress];
    CVLog(@"handleJoinServerFromMenu: addServerIfNeeded returned %@", added ? @"YES" : @"NO");
    
    // Create and connect client
    IRCClient *client = [[IRCClient alloc] initWithConfig:newConfig];
    client.delegate = self;
    self.ircClients[serverAddress] = client;
    [client connect];
    
    [self selectServer:serverAddress];
    [self persistServersAndChannels];
    
    // Save server to history so it appears in login window and menus
    CVLog(@"handleJoinServerFromMenu: Saving new server to history");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        BOOL success = [[ServerHistoryStorage sharedStorage] touchLoginHistoryWithServer:serverAddress
                                                                     nick:nick
                                                                  channel:@""
                                                                 realName:realName
                                                                   useTLS:useTLS];
        CVLog(@"handleJoinServerFromMenu (new): touchLoginHistoryWithServer returned %@", success ? @"YES" : @"NO");
    });
}

- (void)handleDeleteServerFromMenu:(id)sender {
    NSString *server = [sender representedObject];
    if (!server || server.length == 0) {
        return;
    }
    
    // Disconnect if connected
    IRCClient *client = [self clientForServer:server];
    if (client) {
        [client disconnect];
    }
    
    // Remove all channels for this server
    NSArray<NSString *> *channelKeys = [self.serverChannelOrder[server] copy];
    for (NSString *channelKey in channelKeys) {
        [self.channels removeObjectForKey:channelKey];
        [self.channelItems removeObjectForKey:channelKey];
    }
    
    // Remove server data
    [self.ircClients removeObjectForKey:server];
    [self.serverConfigs removeObjectForKey:server];
    [self.serverChannelOrder removeObjectForKey:server];
    [self.serverItems removeObjectForKey:server];
    [self.serverOrder removeObject:server];
    [self.disconnectedServers removeObject:server];
    
    [self reloadChannelListPreservingSelection];
    [self persistServersAndChannels];
}

- (void)handleClearHistoryFromMenu:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer) {
        return;
    }
    
    // Get display name from channel key
    NSString *displayName = [self channelFromChannelKey:channelKey];
    if (!displayName || displayName.length == 0) {
        displayName = channelKey;
    }
    
    // Confirm before clearing history
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = L(@"chat.alert.clearHistory.title", @"Clear History");
    alert.informativeText = [NSString stringWithFormat:L(@"chat.alert.clearHistory.message", @"Are you sure you want to clear all local history for %@? This action cannot be undone."), displayName];
    [alert addButtonWithTitle:L(@"common.delete", @"Delete")];
    [alert addButtonWithTitle:L(@"common.cancel", @"Cancel")];
    alert.alertStyle = NSAlertStyleWarning;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        // Clear messages from memory
        [buffer.messages removeAllObjects];
        [self.cachedAttributedMessages removeObjectForKey:channelKey];
        [self.lastRenderedMessageCount removeObjectForKey:channelKey];
        
        // Clear messages from local database
        [[MessageStorage sharedStorage] deleteMessagesForWindowKey:channelKey];
        
        if ([channelKey isEqualToString:self.currentChannelKey]) {
            [self displayMessagesForChannel:channelKey];
        }
    }
}

- (void)handleShowHistoryFromMenu:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    
    // Get display name from channel key
    NSString *displayName = [self channelFromChannelKey:channelKey];
    if (!displayName || displayName.length == 0) {
        displayName = channelKey;
    }
    
    if (!self.historyWindowController) {
        self.historyWindowController = [[HistoryWindowController alloc] init];
    }
    [self.historyWindowController showHistoryForWindowKey:channelKey displayName:displayName];
    [self.historyWindowController showWindow:nil];
}

- (void)handleToggleMessageStorage:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer) {
        return;
    }
    
    // Toggle the storage setting
    buffer.allowMessageStorage = !buffer.allowMessageStorage;
    
    // Save the setting to database
    [self saveMessageStorageSetting:buffer.allowMessageStorage forChannelKey:channelKey];
    
    // Update menu item state
    NSMenuItem *menuItem = sender;
    menuItem.state = buffer.allowMessageStorage ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Optional: Show a notification
    // Removed because showNotificationWithTitle:message: method doesn't exist
    // NSString *status = buffer.allowMessageStorage ? L(@"chat.notification.storageEnabled", @"Message storage enabled") : L(@"chat.notification.storageDisabled", @"Message storage disabled");
    // NSString *channelName = [self channelFromChannelKey:channelKey] ?: channelKey;
    // NSString *message = [NSString stringWithFormat:L(@"chat.notification.channelStorage", @"%@ for %@"), status, channelName];
    // [self showNotificationWithTitle:L(@"chat.notification.title", @"Message Storage") message:message];
}

- (void)handleRemoveFromRecentFromMenu:(id)sender {
    NSString *channelKey = [sender representedObject];
    [self removeRecentChannelKey:channelKey];
}

- (void)handleAddChannelToGroup:(id)sender {
    NSDictionary *info = [sender representedObject];
    if (![info isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSString *groupName = info[ChannelGroupInfoGroupKey];
    NSString *channelKey = info[ChannelGroupInfoChannelKey];
    if (groupName.length == 0 || channelKey.length == 0) {
        return;
    }

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *groups = [self.customGroupChannels mutableCopy];
    if (!groups) {
        groups = [[NSMutableDictionary alloc] init];
    }
    NSArray<NSString *> *existingChannels = groups[groupName];
    NSMutableArray<NSString *> *channels = existingChannels ? [existingChannels mutableCopy] : [[NSMutableArray alloc] init];
    if ([channels containsObject:channelKey]) {
        [channels removeObject:channelKey];
    } else {
        [channels addObject:channelKey];
    }
    groups[groupName] = [channels copy];
    [self persistCustomGroupChannels:groups];
}

- (void)handleCreateGroupFromMenu:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (![channelKey isKindOfClass:[NSString class]] || channelKey.length == 0) {
        return;
    }

    NSString *groupName = [self promptForInputWithTitle:L(@"prompt.group.title", @"New Group")
                                                message:L(@"prompt.group.message", @"Enter a group name")
                                            placeholder:L(@"prompt.group.placeholder", @"Group name")];
    NSString *trimmed = [groupName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }

    NSString *resolvedGroupName = [self existingGroupNameMatching:trimmed] ?: trimmed;
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *groups = [self.customGroupChannels mutableCopy];
    if (!groups) {
        groups = [[NSMutableDictionary alloc] init];
    }
    NSArray<NSString *> *existingChannels = groups[resolvedGroupName];
    NSMutableArray<NSString *> *channels = existingChannels ? [existingChannels mutableCopy] : [[NSMutableArray alloc] init];
    if (![channels containsObject:channelKey]) {
        [channels addObject:channelKey];
    }
    groups[resolvedGroupName] = [channels copy];
    [self persistCustomGroupChannels:groups];
}

- (void)handleRemoveChannelFromGroup:(id)sender {
    NSDictionary *info = [sender representedObject];
    if (![info isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSString *groupName = info[ChannelGroupInfoGroupKey];
    NSString *channelKey = info[ChannelGroupInfoChannelKey];
    if (groupName.length == 0 || channelKey.length == 0) {
        return;
    }

    NSArray<NSString *> *existingChannels = self.customGroupChannels[groupName];
    if (!existingChannels || existingChannels.count == 0 || ![existingChannels containsObject:channelKey]) {
        return;
    }

    NSMutableArray<NSString *> *channels = [existingChannels mutableCopy];
    [channels removeObject:channelKey];
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *groups = [self.customGroupChannels mutableCopy];
    if (!groups) {
        groups = [[NSMutableDictionary alloc] init];
    }
    groups[groupName] = [channels copy];
    [self persistCustomGroupChannels:groups];
}

- (void)handleDeleteGroupFromMenu:(id)sender {
    NSString *groupName = [sender representedObject];
    if (![groupName isKindOfClass:[NSString class]] || groupName.length == 0) {
        return;
    }
    
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *groups = [self.customGroupChannels mutableCopy];
    [groups removeObjectForKey:groupName];
    [self persistCustomGroupChannels:groups];
}

#pragma mark - Background Color

- (void)handleSetBackgroundColorFromMenu:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }

    CVLog(@"[COLOR] handleSetBackgroundColorFromMenu: channelKey=%@", channelKey);
    self.colorEditingChannelKey = channelKey;

    NSColor *currentColor = [self loadBackgroundColorForChannelKey:channelKey];
    if (!currentColor) {
        currentColor = [self defaultChatBackgroundColor];
    }
    CVLog(@"[COLOR] handleSetBackgroundColorFromMenu: currentColor=%@", currentColor);

    NSColorPanel *colorPanel = [NSColorPanel sharedColorPanel];
    colorPanel.showsAlpha = YES;
    colorPanel.continuous = YES;
    [colorPanel setColor:currentColor];
    [colorPanel setTarget:self];
    [colorPanel setAction:@selector(backgroundColorPanelDidChange:)];
    [colorPanel makeKeyAndOrderFront:nil];
    CVLog(@"[COLOR] handleSetBackgroundColorFromMenu: color panel shown");
}

- (void)handleResetBackgroundColorFromMenu:(id)sender {
    NSString *channelKey = [sender representedObject];
    if (!channelKey || channelKey.length == 0) {
        return;
    }

    [self clearBackgroundColorForChannelKey:channelKey];
    if ([channelKey isEqualToString:self.currentChannelKey]) {
        [self applyBackgroundColorForChannelKey:channelKey];
    }
}

- (void)backgroundColorPanelDidChange:(id)sender {
    if (!self.colorEditingChannelKey || self.colorEditingChannelKey.length == 0) {
        CVLog(@"[COLOR] backgroundColorPanelDidChange: no channel key");
        return;
    }

    NSColorPanel *panel = (NSColorPanel *)sender;
    NSColor *color = panel.color;
    if (!color) {
        CVLog(@"[COLOR] backgroundColorPanelDidChange: no color selected");
        return;
    }
    CVLog(@"[COLOR] backgroundColorPanelDidChange: selected color=%@", color);

    // Convert to sRGB color space for consistency
    NSColor *sRGBColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!sRGBColor) {
        CVLog(@"[COLOR] backgroundColorPanelDidChange: using original color space");
        sRGBColor = color;
    }
    CVLog(@"[COLOR] backgroundColorPanelDidChange: converted to sRGB=%@", sRGBColor);

    [self saveBackgroundColor:sRGBColor forChannelKey:self.colorEditingChannelKey];
    if ([self.colorEditingChannelKey isEqualToString:self.currentChannelKey]) {
        CVLog(@"[COLOR] backgroundColorPanelDidChange: applying color to current channel");
        [self applyBackgroundColorForChannelKey:self.colorEditingChannelKey];
    }
}

- (NSString *)backgroundColorSettingKeyForChannelKey:(NSString *)channelKey {
    return [NSString stringWithFormat:@"%@%@", kSettingChannelBackgroundColorPrefix, channelKey];
}

- (NSString *)legacyBackgroundColorDefaultsKeyForChannelKey:(NSString *)channelKey {
    return [NSString stringWithFormat:@"%@%@", kChannelBackgroundColorDefaultsPrefix, channelKey];
}

- (NSColor *)defaultChatBackgroundColor {
    return [NSColor whiteColor];
}

- (BOOL)hasBackgroundColorForChannelKey:(NSString *)channelKey {
    if (!channelKey || channelKey.length == 0) {
        return NO;
    }
    NSString *key = [self backgroundColorSettingKeyForChannelKey:channelKey];
    NSString *value = [[MessageStorage sharedStorage] getSettingForKey:key];
    if (value.length > 0) {
        return YES;
    }
    // Check legacy NSUserDefaults
    NSString *legacyKey = [self legacyBackgroundColorDefaultsKeyForChannelKey:channelKey];
    return [[NSUserDefaults standardUserDefaults] objectForKey:legacyKey] != nil;
}

- (nullable NSColor *)loadBackgroundColorForChannelKey:(NSString *)channelKey {
    if (!channelKey || channelKey.length == 0) {
        CVLog(@"[COLOR] loadBackgroundColorForChannelKey: invalid channel key");
        return nil;
    }
    CVLog(@"[COLOR] loadBackgroundColorForChannelKey: channelKey=%@", channelKey);

    // First try to load from SQLite
    NSString *key = [self backgroundColorSettingKeyForChannelKey:channelKey];
    CVLog(@"[COLOR] loadBackgroundColorForChannelKey: storage key=%@", key);
    NSString *jsonString = [[MessageStorage sharedStorage] getSettingForKey:key];
    CVLog(@"[COLOR] loadBackgroundColorForChannelKey: jsonString=%@", jsonString);
    NSDictionary *colorInfo = nil;
    
    if (jsonString.length > 0) {
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        colorInfo = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        if (error) {
            CVLog(@"[COLOR] loadBackgroundColorForChannelKey: JSON error=%@", error);
            colorInfo = nil;
        } else if (![colorInfo isKindOfClass:[NSDictionary class]]) {
            CVLog(@"[COLOR] loadBackgroundColorForChannelKey: invalid dictionary type");
            colorInfo = nil;
        }
    }
    CVLog(@"[COLOR] loadBackgroundColorForChannelKey: loaded colorInfo=%@", colorInfo);
    
    // If not in SQLite, try to migrate from NSUserDefaults
    if (!colorInfo) {
        NSString *legacyKey = [self legacyBackgroundColorDefaultsKeyForChannelKey:channelKey];
        colorInfo = [[NSUserDefaults standardUserDefaults] dictionaryForKey:legacyKey];
        CVLog(@"[COLOR] loadBackgroundColorForChannelKey: legacy colorInfo=%@", colorInfo);
        if (colorInfo) {
            CVLog(@"[COLOR] loadBackgroundColorForChannelKey: migrating legacy color");
            // Migrate to SQLite
            [self saveBackgroundColor:[self colorFromDictionary:colorInfo] forChannelKey:channelKey];
            // Remove from NSUserDefaults
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:legacyKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
    
    NSColor *color = [self colorFromDictionary:colorInfo];
    CVLog(@"[COLOR] loadBackgroundColorForChannelKey: final color=%@", color);
    return color;
}

- (NSColor *)colorFromDictionary:(NSDictionary *)colorInfo {
    if (!colorInfo) {
        return nil;
    }
    
    NSNumber *red = colorInfo[@"r"];
    NSNumber *green = colorInfo[@"g"];
    NSNumber *blue = colorInfo[@"b"];
    NSNumber *alpha = colorInfo[@"a"];
    if (!red || !green || !blue || !alpha) {
        return nil;
    }

    // Create color in sRGB color space for consistency
    NSColor *color = [NSColor colorWithRed:red.doubleValue
                                     green:green.doubleValue
                                      blue:blue.doubleValue
                                     alpha:alpha.doubleValue];
    
    NSColor *sRGBColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (sRGBColor) {
        return sRGBColor;
    }
    
    return color;
}

- (void)saveBackgroundColor:(NSColor *)color forChannelKey:(NSString *)channelKey {
    if (!color || !channelKey || channelKey.length == 0) {
        CVLog(@"[COLOR] saveBackgroundColor: invalid parameters");
        return;
    }
    CVLog(@"[COLOR] saveBackgroundColor: channelKey=%@ color=%@", channelKey, color);

    NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgbColor) {
        CVLog(@"[COLOR] saveBackgroundColor: failed to convert to sRGB");
        return;
    }

    NSString *key = [self backgroundColorSettingKeyForChannelKey:channelKey];
    NSDictionary *colorInfo = @{
        @"r": @(rgbColor.redComponent),
        @"g": @(rgbColor.greenComponent),
        @"b": @(rgbColor.blueComponent),
        @"a": @(rgbColor.alphaComponent)
    };
    CVLog(@"[COLOR] saveBackgroundColor: colorInfo=%@", colorInfo);
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:colorInfo options:0 error:&error];
    if (error) {
        CVLog(@"[COLOR] saveBackgroundColor: JSON error=%@", error);
        return;
    }
    
    if (jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        CVLog(@"[COLOR] saveBackgroundColor: jsonString=%@", jsonString);
        BOOL success = [[MessageStorage sharedStorage] setSettingForKey:key value:jsonString];
        CVLog(@"[COLOR] saveBackgroundColor: save success=%@", success ? @"YES" : @"NO");
    }
}

- (NSString *)messageStorageSettingKeyForChannelKey:(NSString *)channelKey {
    return [NSString stringWithFormat:@"%@%@", kSettingChannelMessageStoragePrefix, channelKey];
}

- (void)saveMessageStorageSetting:(BOOL)enabled forChannelKey:(NSString *)channelKey {
    if (!channelKey || channelKey.length == 0) {
        CVLog(@"[MSG_STORAGE] saveMessageStorageSetting: invalid channel key");
        return;
    }
    CVLog(@"[MSG_STORAGE] saveMessageStorageSetting: channelKey=%@ enabled=%@", channelKey, enabled ? @"YES" : @"NO");
    
    NSString *key = [self messageStorageSettingKeyForChannelKey:channelKey];
    NSString *value = enabled ? @"YES" : @"NO";
    BOOL success = [[MessageStorage sharedStorage] setSettingForKey:key value:value];
    CVLog(@"[MSG_STORAGE] saveMessageStorageSetting: save success=%@", success ? @"YES" : @"NO");
}

- (BOOL)loadMessageStorageSettingForChannelKey:(NSString *)channelKey {
    if (!channelKey || channelKey.length == 0) {
        CVLog(@"[MSG_STORAGE] loadMessageStorageSetting: invalid channel key");
        return YES; // 默认启用
    }
    CVLog(@"[MSG_STORAGE] loadMessageStorageSetting: channelKey=%@", channelKey);
    
    NSString *key = [self messageStorageSettingKeyForChannelKey:channelKey];
    NSString *value = [[MessageStorage sharedStorage] getSettingForKey:key];
    CVLog(@"[MSG_STORAGE] loadMessageStorageSetting: stored value=%@", value);
    
    // 如果没有存储设置，返回默认值YES
    if (!value) {
        return YES;
    }
    
    return [value isEqualToString:@"YES"];
}

- (void)clearBackgroundColorForChannelKey:(NSString *)channelKey {
    if (!channelKey || channelKey.length == 0) {
        return;
    }

    NSString *key = [self backgroundColorSettingKeyForChannelKey:channelKey];
    [[MessageStorage sharedStorage] deleteSettingForKey:key];
    
    // Also remove legacy key if exists
    NSString *legacyKey = [self legacyBackgroundColorDefaultsKeyForChannelKey:channelKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:legacyKey];
}

- (void)applyBackgroundColorForChannelKey:(NSString *)channelKey {
    CVLog(@"[COLOR] applyBackgroundColorForChannelKey: channelKey=%@", channelKey);
    CVLog(@"[COLOR] applyBackgroundColorForChannelKey: showChannelColors=%@", self.showChannelColors ? @"YES" : @"NO");
    
    NSColor *color = nil;
    
    // Always load custom background color if it exists, regardless of showChannelColors setting
    color = [self loadBackgroundColorForChannelKey:channelKey];
    
    if (!color) {
        color = [self defaultChatBackgroundColor];
        CVLog(@"[COLOR] applyBackgroundColorForChannelKey: using default color=%@", color);
    }

    // Ensure color has correct alpha channel
    NSColor *finalColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!finalColor) {
        finalColor = color;
        CVLog(@"[COLOR] applyBackgroundColorForChannelKey: using original color space");
    }
    CVLog(@"[COLOR] applyBackgroundColorForChannelKey: finalColor=%@", finalColor);
    CVLog(@"[COLOR] applyBackgroundColorForChannelKey: CGColor=%@", finalColor.CGColor);

    if (self.chatTextView) {
        CVLog(@"[COLOR] applyBackgroundColorForChannelKey: updating chatTextView");
        self.chatTextView.drawsBackground = YES;
        self.chatTextView.backgroundColor = finalColor;
        [self.chatTextView setNeedsDisplay:YES];
    } else {
        CVLog(@"[COLOR] applyBackgroundColorForChannelKey: chatTextView is nil");
    }

    if (self.chatScrollView) {
        CVLog(@"[COLOR] applyBackgroundColorForChannelKey: updating chatScrollView");
        self.chatScrollView.wantsLayer = YES;
        // Ensure CGColor includes alpha channel
        self.chatScrollView.layer.backgroundColor = finalColor.CGColor;
        // Also update content view background
        if (self.chatScrollView.contentView) {
            self.chatScrollView.contentView.wantsLayer = YES;
            self.chatScrollView.contentView.layer.backgroundColor = finalColor.CGColor;
            [self.chatScrollView.contentView setNeedsDisplay:YES];
        } else {
            CVLog(@"[COLOR] applyBackgroundColorForChannelKey: scroll view contentView is nil");
        }
        [self.chatScrollView setNeedsDisplay:YES];
    } else {
        CVLog(@"[COLOR] applyBackgroundColorForChannelKey: chatScrollView is nil");
    }
    
    // Force view hierarchy update
    [self.view setNeedsDisplay:YES];
    [self.view setNeedsLayout:YES];
    [self.view layoutSubtreeIfNeeded];
    CVLog(@"[COLOR] applyBackgroundColorForChannelKey: layout updated");
}

#pragma mark - Prompt Helpers

- (NSString *)promptForInputWithTitle:(NSString *)title message:(NSString *)message placeholder:(NSString *)placeholder {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:L(@"chat.prompt.ok", @"OK")];
    [alert addButtonWithTitle:L(@"chat.prompt.cancel", @"Cancel")];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.placeholderString = placeholder;
    alert.accessoryView = input;
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        return input.stringValue;
    }
    return @"";
}

- (NSString *)promptForChannelFromList:(NSArray<NSString *> *)channels title:(NSString *)title message:(NSString *)message preferredChannel:(NSString *)preferredChannel {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:L(@"chat.prompt.ok", @"OK")];
    [alert addButtonWithTitle:L(@"chat.prompt.cancel", @"Cancel")];
    
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 24) pullsDown:NO];
    for (NSString *channel in channels) {
        [popup addItemWithTitle:channel];
    }
    if (preferredChannel.length > 0 && [channels containsObject:preferredChannel]) {
        [popup selectItemWithTitle:preferredChannel];
    }
    alert.accessoryView = popup;
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        return popup.selectedItem.title;
    }
    return @"";
}

- (BOOL)promptForConnectOptionsForServer:(NSString *)server config:(IRCConfig *)config {
    if (!server || server.length == 0 || !config) {
        return NO;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = L(@"prompt.connectOptions.title", @"Connect to Server");
    alert.informativeText = [NSString stringWithFormat:L(@"prompt.connectOptions.message", @"Configure connection options for %@"), server];
    [alert addButtonWithTitle:L(@"prompt.connectOptions.connect", @"Connect")];
    [alert addButtonWithTitle:L(@"chat.prompt.cancel", @"Cancel")];

    CGFloat w = 320, rowH = 38, labelW = 96, fieldX = 104, fieldW = 206;
    CGFloat viewH = 4 * rowH + 10;
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, viewH)];
    acc.wantsLayer = YES;

    // Row 0: Nickname (top)
    NSTextField *nickLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, viewH - 20, labelW, 18)];
    nickLabel.stringValue = L(@"prompt.connectOptions.nick", @"Nickname:");
    nickLabel.bezeled = NO; nickLabel.drawsBackground = NO; nickLabel.editable = NO;
    nickLabel.font = [NSFont systemFontOfSize:13];
    [acc addSubview:nickLabel];
    NSTextField *nickField = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, viewH - 26, fieldW, 22)];
    nickField.stringValue = config.nick ?: @"";
    nickField.placeholderString = L(@"prompt.connectOptions.nickPlaceholder", @"nickname");
    [acc addSubview:nickField];

    // Row 1: Real Name
    NSTextField *realLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, viewH - 20 - rowH, labelW, 18)];
    realLabel.stringValue = L(@"prompt.connectOptions.realName", @"Real Name:");
    realLabel.bezeled = NO; realLabel.drawsBackground = NO; realLabel.editable = NO;
    realLabel.font = [NSFont systemFontOfSize:13];
    [acc addSubview:realLabel];
    NSTextField *realField = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, viewH - 26 - rowH, fieldW, 22)];
    realField.stringValue = config.realName ?: @"";
    realField.placeholderString = L(@"prompt.connectOptions.realNamePlaceholder", @"Your real name");
    [acc addSubview:realField];

    // Row 2: Password
    NSTextField *pwLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, viewH - 20 - 2*rowH, labelW, 18)];
    pwLabel.stringValue = L(@"prompt.connectOptions.password", @"Password:");
    pwLabel.bezeled = NO; pwLabel.drawsBackground = NO; pwLabel.editable = NO;
    pwLabel.font = [NSFont systemFontOfSize:13];
    [acc addSubview:pwLabel];
    NSSecureTextField *pwField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(fieldX, viewH - 26 - 2*rowH, fieldW, 22)];
    pwField.stringValue = config.password ?: @"";
    pwField.placeholderString = L(@"prompt.connectOptions.passwordPlaceholder", @"Server password (optional)");
    [acc addSubview:pwField];

    // Row 3: Use TLS/SSL
    NSButton *tlsCheck = [[NSButton alloc] initWithFrame:NSMakeRect(fieldX, viewH - 24 - 3*rowH, fieldW, 20)];
    tlsCheck.buttonType = NSButtonTypeSwitch;
    tlsCheck.title = L(@"prompt.connectOptions.useTLS", @"Use TLS/SSL");
    tlsCheck.state = config.useTLS ? NSControlStateValueOn : NSControlStateValueOff;
    [acc addSubview:tlsCheck];

    alert.accessoryView = acc;
    NSModalResponse response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) {
        return NO;
    }
    NSString *nick = [nickField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (nick.length == 0) {
        NSAlert *err = [[NSAlert alloc] init];
        err.messageText = L(@"prompt.connectOptions.errorTitle", @"Invalid Input");
        err.informativeText = L(@"prompt.connectOptions.nickRequired", @"Nickname is required.");
        [err addButtonWithTitle:L(@"chat.prompt.ok", @"OK")];
        [err runModal];
        return NO;
    }
    config.nick = nick;
    config.realName = realField.stringValue.length > 0 ? realField.stringValue : (config.realName ?: @"");
    config.password = pwField.stringValue.length > 0 ? pwField.stringValue : nil;
    config.useTLS = (tlsCheck.state == NSControlStateValueOn);
    return YES;
}

#pragma mark - Main Menu Actions

- (void)menuJoinChannel:(id)sender {
    NSString *channel = [self promptForInputWithTitle:L(@"prompt.join.title", @"Join Channel")
                                              message:L(@"prompt.join.message", @"Enter channel name")
                                          placeholder:L(@"prompt.join.placeholder", @"#channel")];
    if (channel.length > 0) {
        [self handleCommand:[NSString stringWithFormat:@"/join %@", channel]];
    }
}

- (void)menuPartChannel:(id)sender {
    [self handleCommand:@"/part"];
}

- (void)menuPrivateMessage:(id)sender {
    NSString *target = [self promptForInputWithTitle:L(@"prompt.privateMessage.title", @"Private Message")
                                             message:L(@"prompt.privateMessage.targetMessage", @"Enter target user or channel")
                                         placeholder:L(@"prompt.privateMessage.targetPlaceholder", @"nickname")];
    if (target.length == 0) {
        return;
    }

    NSString *message = [self promptForInputWithTitle:L(@"prompt.privateMessage.title", @"Private Message")
                                              message:L(@"prompt.privateMessage.message", @"Enter message")
                                          placeholder:L(@"prompt.privateMessage.messagePlaceholder", @"message")];
    if (message.length == 0) {
        return;
    }
    [self handleCommand:[NSString stringWithFormat:@"/msg %@ %@", target, message]];
}

- (void)menuChangeNick:(id)sender {
    NSString *newNick = [self promptForInputWithTitle:L(@"prompt.changeNick.title", @"Change Nickname")
                                              message:L(@"prompt.changeNick.message", @"Enter a new nickname")
                                          placeholder:L(@"prompt.changeNick.placeholder", @"nickname")];
    if (newNick.length == 0) {
        return;
    }
    [self handleCommand:[NSString stringWithFormat:@"/nick %@", newNick]];
}

- (void)menuConnectServer:(id)sender {
    NSString *server = [self promptForInputWithTitle:L(@"prompt.connectServer.title", @"Connect Server")
                                             message:L(@"prompt.connectServer.message", @"Enter server address")
                                         placeholder:L(@"prompt.connectServer.placeholder", @"irc.example.net:6667")];
    if (server.length == 0) {
        return;
    }
    [self handleCommand:[NSString stringWithFormat:@"/server %@", server]];
}

- (void)menuServerLinks:(id)sender {
    NSString *mask = [self promptForInputWithTitle:L(@"prompt.serverLinks.title", @"Server Links")
                                           message:L(@"prompt.serverLinks.message", @"Enter server mask (optional)")
                                       placeholder:L(@"prompt.serverLinks.placeholder", @"*.libera.chat")];
    if (mask.length > 0) {
        [self handleCommand:[NSString stringWithFormat:@"/links %@", mask]];
    } else {
        [self handleCommand:@"/links"];
    }
}

- (void)menuListChannels:(id)sender {
    NSString *pattern = [self promptForInputWithTitle:L(@"prompt.listChannels.title", @"List Channels")
                                              message:L(@"prompt.listChannels.message", @"Enter channel pattern (optional)")
                                          placeholder:L(@"prompt.listChannels.placeholder", @"#test*")];
    if (pattern.length > 0) {
        [self handleCommand:[NSString stringWithFormat:@"/list %@", pattern]];
    } else {
        [self handleCommand:@"/list"];
    }
}

- (void)menuRawCommand:(id)sender {
    NSString *command = [self promptForInputWithTitle:L(@"prompt.rawCommand.title", @"Raw Command")
                                              message:L(@"prompt.rawCommand.message", @"Enter raw IRC command")
                                          placeholder:L(@"prompt.rawCommand.placeholder", @"WHOIS nickname")];
    if (command.length == 0) {
        return;
    }
    [self handleCommand:[NSString stringWithFormat:@"/raw %@", command]];
}

- (void)menuHelp:(id)sender {
    [self showHelp];
}

- (void)menuQuit:(id)sender {
    [self handleCommand:@"/quit"];
}

- (void)menuConnectToServer:(id)sender {
    NSString *server = [sender representedObject];
    if (![server isKindOfClass:[NSString class]] || server.length == 0) {
        return;
    }
    IRCClient *client = [self clientForServer:server];
    BOOL isConnected = client && client.isConnected && ![self.disconnectedServers containsObject:server];
    if (isConnected) {
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.serverAlreadyConnected", @"Server %@ is already connected."), server]];
        return;
    }
    [self addServerIfNeeded:server];
    IRCConfig *config = [self ensureConfigForServer:server];
    if ([server hasSuffix:@":6697"]) config.useTLS = YES;
    else if ([server hasSuffix:@":6667"]) config.useTLS = NO;
    if (![self promptForConnectOptionsForServer:server config:config]) {
        return;
    }
    client = [self clientForServer:server];
    if (client) {
        [client connect];
    } else {
        client = [[IRCClient alloc] initWithConfig:config];
        client.delegate = self;
        self.ircClients[server] = client;
        [client connect];
    }
    self.currentServer = server;
    [self updateStatus];
    [self selectServer:server];
    [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.connecting", @"Connecting to %@..."), server]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [[ServerHistoryStorage sharedStorage] touchLoginHistoryWithServer:server
                                                                    nick:config.nick
                                                                 channel:@""
                                                                realName:config.realName
                                                                  useTLS:config.useTLS];
    });
}

@end
