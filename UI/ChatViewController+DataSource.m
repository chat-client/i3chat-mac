//
//  ChatViewController+DataSource.m
//  i3Chat
//
//  TableView and OutlineView data source/delegate for ChatViewController
//

#import "ChatViewController+Private.h"

// Custom NSOutlineView subclass that can accept first responder
@interface FocusableOutlineView : NSOutlineView
@end

@implementation FocusableOutlineView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    // Post notification when focus changes
    if (result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"FocusableOutlineViewDidBecomeFirstResponder" object:self];
        });
    }
    return result;
}

- (BOOL)resignFirstResponder {
    BOOL result = [super resignFirstResponder];
    // Post notification when focus changes
    if (result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"FocusableOutlineViewDidResignFirstResponder" object:self];
        });
    }
    return result;
}

- (void)mouseDown:(NSEvent *)event {
    // Process the click first
    [super mouseDown:event];
    
    // After click is processed, make this view first responder to get focus
    // This ensures text colors update correctly when channel is selected
    if (self.window && self.window.isKeyWindow) {
        // Use a small delay to ensure selection has been processed
        // This delay allows the selection to be set before we try to get focus
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.window makeFirstResponder:self];
        });
    }
}

@end

@implementation ChatViewController (DataSource)

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (![NSThread isMainThread]) {
        __block NSInteger result = 0;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self numberOfRowsInTableView:tableView];
        });
        return result;
    }
    
    if (tableView == self.userListView) {
        NSArray<NSString *> *users = [self displayedUsersForCurrentChannel];
        NSInteger count = users.count;
        CVLog(@"numberOfRowsInTableView (userListView): Returning %ld for channel %@", (long)count, self.currentChannelKey);
        return count;
    }
    if (tableView == self.favoritesTableView) {
        return [self filteredFavoriteItems].count;
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (![NSThread isMainThread]) {
        __block id result = @"";
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self tableView:tableView objectValueForTableColumn:tableColumn row:row];
        });
        return result;
    }
    
    @try {
        if (tableView == self.userListView) {
            NSArray<NSString *> *users = [self displayedUsersForCurrentChannel];
            if (row >= 0 && row < (NSInteger)users.count) {
                NSString *user = users[row];
                CVLog(@"tableView:objectValueForTableColumn: Returning user[%ld] = %@ for channel %@", (long)row, user, self.currentChannelKey);
                return user ?: @"";
            }
            CVLog(@"tableView:objectValueForTableColumn: No user at row %ld (users.count=%lu, currentChannelKey=%@)",
                  (long)row, (unsigned long)users.count, self.currentChannelKey);
        }
        if (tableView == self.favoritesTableView) {
            NSArray<NSDictionary *> *items = [self filteredFavoriteItems];
            if (row >= 0 && row < (NSInteger)items.count) {
                NSDictionary *item = items[row];
                return [self displayTextForFavoriteItem:item];
            }
            return @"";
        }
        return @"";
    } @catch (NSException *exception) {
        CVLog(@"Error in objectValueForTableColumn: %@", exception);
        return @"";
    }
}

#pragma mark - NSTableViewDelegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    if (tableView == self.channelListView) {
        NSTableRowView *rowView = [[NSTableRowView alloc] init];
        rowView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
        BOOL isSelected = (row == tableView.selectedRow);
        rowView.selected = isSelected;
        ChannelTreeItem *item = [self.channelListView itemAtRow:row];
        [self applyChannelListRowStyle:rowView forItem:item];
        return rowView;
    }
    NSTableRowView *rowView = [[NSTableRowView alloc] init];
    rowView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    return rowView;
}

- (void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
    if (tableView == self.channelListView) {
        rowView.selected = (row == tableView.selectedRow);
        ChannelTreeItem *item = [self.channelListView itemAtRow:row];
        [self applyChannelListRowStyle:rowView forItem:item];
        
        // Update text color based on selection AND focus state
        BOOL hasFocus = [self isChannelListViewFocused];
        NSTableCellView *cellView = [rowView viewAtColumn:0];
        if (cellView && cellView.textField) {
            // Only show white text if selected AND has focus
            if (rowView.selected && hasFocus) {
                cellView.textField.textColor = [NSColor whiteColor];
            } else {
                BOOL isDisabled = [self isChannelListItemDisabled:item];
                cellView.textField.textColor = isDisabled
                    ? [NSColor colorWithWhite:0.55 alpha:1.0]
                    : [NSColor colorWithWhite:0.15 alpha:1.0];
            }
        }
    }
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView != self.userListView && tableView != self.favoritesTableView) {
        return nil;
    }

    NSTableCellView *cellView = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, tableView.rowHeight)];
        cellView.identifier = tableColumn.identifier;

        if (tableView == self.favoritesTableView) {
            FavoritesTextView *textView = [[FavoritesTextView alloc] initWithFrame:NSMakeRect(12, 0, tableColumn.width - 24, tableView.rowHeight)];
            textView.editable = NO;
            textView.selectable = YES;
            textView.drawsBackground = NO;
            textView.usesRuler = NO;
            textView.usesFontPanel = NO;
            textView.importsGraphics = NO;
            textView.allowsImageEditing = NO;
            textView.delegate = self;
            textView.chatViewController = self;
            textView.font = [NSFont systemFontOfSize:13];
            textView.textColor = [NSColor colorWithWhite:0.15 alpha:1.0];
            textView.textContainerInset = NSMakeSize(0, 0);
            textView.textContainer.lineFragmentPadding = 0;
            textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            textView.identifier = @"FavoritesTextView";
            textView.linkTextAttributes = @{
                NSForegroundColorAttributeName: [NSColor systemBlueColor],
                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                NSCursorAttributeName: [NSCursor pointingHandCursor]
            };
            [cellView addSubview:textView];
        } else {
            NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 0, tableColumn.width - 24, tableView.rowHeight)];
            textField.editable = NO;
            textField.selectable = NO;
            textField.bezeled = NO;
            textField.drawsBackground = NO;
            textField.font = [NSFont systemFontOfSize:13];
            textField.textColor = [NSColor colorWithWhite:0.15 alpha:1.0];
            textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            textField.tag = 100;
            [cellView addSubview:textField];
        }
    }

    NSString *text = [self tableView:tableView objectValueForTableColumn:tableColumn row:row];

    if (tableView == self.favoritesTableView) {
        FavoritesTextView *textView = nil;
        for (NSView *subview in cellView.subviews) {
            if ([subview isKindOfClass:[FavoritesTextView class]]) {
                textView = (FavoritesTextView *)subview;
                break;
            }
        }
        if (textView && text) {
            NSFont *font = textView.font ?: [NSFont systemFontOfSize:13];
            NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: [NSColor colorWithWhite:0.15 alpha:1.0]
            }];
            NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
            if (detector) {
                NSArray<NSTextCheckingResult *> *matches = [detector matchesInString:text options:0 range:NSMakeRange(0, text.length)];
                for (NSTextCheckingResult *match in matches) {
                    if (match.URL) {
                        [attrStr addAttribute:NSLinkAttributeName value:match.URL range:match.range];
                    }
                }
            }
            [textView.textStorage setAttributedString:attrStr];
        }
    } else {
        NSTextField *textField = [cellView viewWithTag:100];
        if (textField && text) {
            textField.stringValue = text;
            // Set text color based on selection state
            BOOL isSelected = (row == tableView.selectedRow);
            textField.textColor = isSelected ? [NSColor whiteColor] : [NSColor colorWithWhite:0.15 alpha:1.0];
        }
    }

    return cellView;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    
    if (tableView == self.userListView) {
        NSInteger row = self.userListView.selectedRow;
        if (row != self.previousUserListSelectedRow) {
            self.previousUserListSelectedRow = row;
        }
        
        // Update text colors for all visible rows in user list
        NSRange visibleRows = [tableView rowsInRect:tableView.visibleRect];
        for (NSInteger i = visibleRows.location; i < (NSInteger)(visibleRows.location + visibleRows.length); i++) {
            NSTableCellView *cellView = [tableView viewAtColumn:0 row:i makeIfNecessary:NO];
            if (cellView) {
                NSTextField *textField = [cellView viewWithTag:100];
                if (textField) {
                    BOOL isSelected = (i == tableView.selectedRow);
                    textField.textColor = isSelected ? [NSColor whiteColor] : [NSColor colorWithWhite:0.15 alpha:1.0];
                }
            }
        }
    } else if (tableView == self.favoritesTableView) {
        // Update text colors for all visible rows in favorites list
        NSRange visibleRows = [tableView rowsInRect:tableView.visibleRect];
        for (NSInteger i = visibleRows.location; i < (NSInteger)(visibleRows.location + visibleRows.length); i++) {
            NSTableCellView *cellView = [tableView viewAtColumn:0 row:i makeIfNecessary:NO];
            if (cellView) {
                for (NSView *subview in cellView.subviews) {
                    if ([subview isKindOfClass:[NSTextView class]]) {
                        NSTextView *textView = (NSTextView *)subview;
                        BOOL isSelected = (i == tableView.selectedRow);
                        textView.textColor = isSelected ? [NSColor whiteColor] : [NSColor colorWithWhite:0.15 alpha:1.0];
                        break;
                    }
                }
            }
        }
    }
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (outlineView != self.channelListView) {
        return 0;
    }
    
    if (!item) {
        if (self.channelListMode == ChannelListModeChannels) {
            return self.serverOrder.count;
        }
        if (self.channelListMode == ChannelListModeGroups) {
            return self.customGroupOrder.count > 0 ? self.customGroupOrder.count : 1;
        }
        if (self.channelListMode == ChannelListModeRecent) {
            return self.recentChannelKeys.count;
        }
        return 0;
    }
    
    if (![item isKindOfClass:[ChannelTreeItem class]]) {
        return 0;
    }
    
    ChannelTreeItem *treeItem = (ChannelTreeItem *)item;
    if (self.channelListMode == ChannelListModeChannels) {
        if (treeItem.type == ChannelTreeItemTypeServer) {
            NSArray<NSString *> *channels = self.serverChannelOrder[treeItem.server];
            return channels ? channels.count : 0;
        }
        return 0;
    }
    
    if (self.channelListMode == ChannelListModeGroups) {
        if (treeItem.type == ChannelTreeItemTypeGroup) {
            NSArray<NSString *> *channels = self.customGroupChannels[treeItem.server];
            // Count only existing channels to avoid blank rows
            if (channels) {
                NSUInteger count = 0;
                for (NSString *channelKey in channels) {
                    if (self.channels[channelKey]) {
                        count++;
                    }
                }
                return count;
            }
            return 0;
        }
        return 0;
    }
    
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (outlineView != self.channelListView) {
        return nil;
    }
    
    if (!item) {
        if (self.channelListMode == ChannelListModeChannels) {
            if (index >= 0 && index < (NSInteger)self.serverOrder.count) {
                NSString *server = self.serverOrder[index];
                return self.serverItems[server];
            }
            return nil;
        }
        if (self.channelListMode == ChannelListModeGroups) {
            if (self.customGroupOrder.count == 0) {
                return self.groupPlaceholderItem;
            }
            if (index >= 0 && index < (NSInteger)self.customGroupOrder.count) {
                NSString *groupName = self.customGroupOrder[index];
                return self.groupItems[groupName];
            }
            return nil;
        }
        if (self.channelListMode == ChannelListModeRecent) {
            if (index >= 0 && index < (NSInteger)self.recentChannelKeys.count) {
                NSString *channelKey = self.recentChannelKeys[index];
                return [self recentItemForChannelKey:channelKey];
            }
            return nil;
        }
        return nil;
    }
    
    if (![item isKindOfClass:[ChannelTreeItem class]]) {
        return nil;
    }
    
    ChannelTreeItem *treeItem = (ChannelTreeItem *)item;
    if (self.channelListMode == ChannelListModeChannels) {
        if (treeItem.type == ChannelTreeItemTypeServer) {
            NSArray<NSString *> *channels = self.serverChannelOrder[treeItem.server];
            if (index >= 0 && index < (NSInteger)channels.count) {
                NSString *channelKey = channels[index];
                return self.channelItems[channelKey];
            }
        }
        return nil;
    }
    
    if (self.channelListMode == ChannelListModeGroups) {
        if (treeItem.type == ChannelTreeItemTypeGroup) {
            NSString *groupName = treeItem.server;
            NSArray<NSString *> *channels = self.customGroupChannels[groupName];
            if (channels) {
                // Find the Nth existing channel to avoid blank rows
                NSUInteger foundIndex = 0;
                for (NSString *channelKey in channels) {
                    if (self.channels[channelKey]) {
                        if (foundIndex == index) {
                            // Use a unique key combining group name and channel key
                            // This allows the same channel to appear in multiple groups with separate item objects
                            NSString *groupChannelKey = [NSString stringWithFormat:@"%@:%@", groupName, channelKey];
                            ChannelTreeItem *channelItem = self.groupChannelItems[groupChannelKey];
                            if (!channelItem) {
                                channelItem = [[ChannelTreeItem alloc] init];
                                channelItem.type = ChannelTreeItemTypeChannel;
                                channelItem.channelKey = channelKey;
                                // Store the group name in the server property for reference
                                channelItem.server = groupName;
                                self.groupChannelItems[groupChannelKey] = channelItem;
                            }
                            return channelItem;
                        }
                        foundIndex++;
                    }
                }
            }
        }
        return nil;
    }
    
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if (outlineView != self.channelListView) {
        return NO;
    }
    
    if (![item isKindOfClass:[ChannelTreeItem class]]) {
        return NO;
    }
    
    ChannelTreeItem *treeItem = (ChannelTreeItem *)item;
    if (self.channelListMode == ChannelListModeChannels) {
        return treeItem.type == ChannelTreeItemTypeServer;
    }
    if (self.channelListMode == ChannelListModeGroups) {
        if (treeItem.type == ChannelTreeItemTypeGroup) {
            NSArray<NSString *> *channels = self.customGroupChannels[treeItem.server];
            return channels.count > 0;
        }
        return NO;
    }
    return NO;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    if (outlineView != self.channelListView) {
        return @"";
    }
    
    if (![item isKindOfClass:[ChannelTreeItem class]]) {
        return @"";
    }
    
    ChannelTreeItem *treeItem = (ChannelTreeItem *)item;
    if (treeItem.type == ChannelTreeItemTypeServer) {
        return treeItem.server ?: @"";
    }
    
    if (treeItem.type == ChannelTreeItemTypeGroup || treeItem.type == ChannelTreeItemTypePlaceholder) {
        return treeItem.server ?: @"";
    }
    
    if (treeItem.type == ChannelTreeItemTypeRecent && treeItem.channelKey) {
        return [self displayNameForRecentChannelKey:treeItem.channelKey];
    }
    
    if (treeItem.channelKey) {
        ChannelBuffer *buffer = self.channels[treeItem.channelKey];
        if (buffer) {
            NSString *name = buffer.name ?: @"";
            if (buffer.unreadCount > 0) {
                name = [NSString stringWithFormat:@"%@ (%ld)", name, (long)buffer.unreadCount];
            }
            return name;
        }
    }
    
    return @"";
}

#pragma mark - NSOutlineViewDelegate

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    // Ignore selection changes during reload or programmatic updates
    if (notification.object != self.channelListView || 
        self.isUpdatingChannelSelection || 
        self.isReloadingChannelList) {
        return;
    }
    
    // Update text colors when selection changes
    // Use a small delay to ensure first responder has been updated after click
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateChannelListTextColors];
    });
    
    NSInteger row = self.channelListView.selectedRow;
    if (row < 0) {
        return;
    }
    // Always update the previous selected row, even if it's the same as current
    self.previousChannelListSelectedRow = row;
    
    ChannelTreeItem *item = [self.channelListView itemAtRow:row];
    if (![item isKindOfClass:[ChannelTreeItem class]]) {
        return;
    }
    
    if (item.type == ChannelTreeItemTypeServer) {
        self.currentServer = item.server;
        // Switch to server status window when clicking on server address
        NSString *statusChannelKey = [self makeChannelKey:item.server channel:item.server];
        if (self.channels[statusChannelKey]) {
            [self switchToChannel:statusChannelKey];
        } else {
            // Server not connected yet, but still update currentChannelKey to prevent focus jumping
            // when the server connects later
            self.currentChannelKey = statusChannelKey;
            // Clear chat view since there's no buffer yet
            self.chatTextView.string = L(@"chat.notConnected", @"Server not connected. Right-click to connect.");
            // Clear user list
            [self updateUserListForChannel:@""];
        }
        [self updateStatus];
        return;
    }
    
    if (item.type == ChannelTreeItemTypeChannel || item.type == ChannelTreeItemTypeRecent) {
        NSString *channelKey = item.channelKey;
        if (channelKey && ![channelKey isEqualToString:self.currentChannelKey]) {
            [self switchToChannel:channelKey];
        }
    }
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if (outlineView != self.channelListView) {
        return nil;
    }
    
    NSTableCellView *cellView = [outlineView makeViewWithIdentifier:tableColumn.identifier owner:self];
    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, outlineView.rowHeight)];
        cellView.identifier = tableColumn.identifier;
        
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 0, tableColumn.width - 24, outlineView.rowHeight)];
        textField.editable = NO;
        textField.selectable = NO;
        textField.bezeled = NO;
        textField.drawsBackground = NO;
        textField.font = [NSFont systemFontOfSize:13];
        textField.textColor = [NSColor colorWithWhite:0.15 alpha:1.0];
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        // Make textField not accept first responder so outline view can get focus
        // This is important for proper focus detection
        textField.refusesFirstResponder = YES;
        cellView.textField = textField;
        [cellView addSubview:textField];
    }
    
    NSString *text = [self outlineView:outlineView objectValueForTableColumn:tableColumn byItem:item];
    NSTextField *textField = cellView.textField;
    if (textField) {
        textField.stringValue = text ?: @"";
        
        // Set font based on item type
        if ([item isKindOfClass:[ChannelTreeItem class]]) {
            ChannelTreeItem *treeItem = (ChannelTreeItem *)item;
            if (treeItem.type == ChannelTreeItemTypeServer || treeItem.type == ChannelTreeItemTypeGroup) {
                textField.font = [NSFont boldSystemFontOfSize:13];
            } else {
                textField.font = [NSFont systemFontOfSize:13];
            }
        }
        
        // Check if this row is selected AND the outline view has focus
        NSInteger row = [outlineView rowForItem:item];
        BOOL isSelected = (row >= 0 && row == outlineView.selectedRow);
        BOOL hasFocus = [self isChannelListViewFocused];
        
        // Set text color: white only if selected AND has focus, otherwise gray/black
        if (isSelected && hasFocus) {
            textField.textColor = [NSColor whiteColor];
        } else {
            BOOL isDisabled = [self isChannelListItemDisabled:item];
            textField.textColor = isDisabled
                ? [NSColor colorWithWhite:0.55 alpha:1.0]   // Dimmed for disconnected/unjoined
                : [NSColor colorWithWhite:0.15 alpha:1.0]; // Normal for connected/joined
        }
    }
    
    return cellView;
}

- (BOOL)isChannelListViewFocused {
    if (!self.channelListView || !self.channelListView.window) {
        return NO;
    }
    
    // Check if window is key window (has focus)
    if (!self.channelListView.window.isKeyWindow) {
        return NO;
    }
    
    NSResponder *firstResponder = self.channelListView.window.firstResponder;
    if (!firstResponder) {
        return NO;
    }
    
    // Check if first responder is the outline view itself
    if (firstResponder == self.channelListView) {
        return YES;
    }
    
    // Check if first responder is a view
    if (![firstResponder isKindOfClass:[NSView class]]) {
        return NO;
    }
    
    NSView *responderView = (NSView *)firstResponder;
    
    // If first responder is the input field, channel list doesn't have focus
    if (self.inputField && responderView == self.inputField) {
        return NO;
    }
    
    // Check if responder is a subview of the outline view (cell views, text fields, etc.)
    // Walk up the view hierarchy to see if it's within channelListView
    NSView *currentView = responderView;
    while (currentView) {
        if (currentView == self.channelListView) {
            // Found that responder is a subview of channel list
            return YES;
        }
        currentView = currentView.superview;
    }
    
    // If first responder is not channel list or its subviews, channel list doesn't have focus
    return NO;
}

- (void)updateChannelListTextColors {
    if (!self.channelListView || self.isReloadingChannelList) {
        return;
    }
    
    BOOL hasFocus = [self isChannelListViewFocused];
    [self.channelListView enumerateAvailableRowViewsUsingBlock:^(__kindof NSTableRowView *rowView, NSInteger rowIndex) {
        NSTableCellView *cellView = [rowView viewAtColumn:0];
        if (cellView && cellView.textField) {
            id rowItem = [self.channelListView itemAtRow:rowIndex];
            // Only show white text if selected AND has focus
            if (rowView.selected && hasFocus) {
                cellView.textField.textColor = [NSColor whiteColor];
            } else {
                BOOL isDisabled = [self isChannelListItemDisabled:rowItem];
                cellView.textField.textColor = isDisabled
                    ? [NSColor colorWithWhite:0.55 alpha:1.0]
                    : [NSColor colorWithWhite:0.15 alpha:1.0];
            }
        }
    }];
}

- (void)applyChannelListRowStyle:(NSTableRowView *)rowView forItem:(ChannelTreeItem *)item {
    if (!rowView || !item || !self.showChannelColors) {
        return;
    }
    
    if (item.type == ChannelTreeItemTypeChannel && item.channelKey) {
        NSColor *bgColor = [self loadBackgroundColorForChannelKey:item.channelKey];
        if (bgColor) {
            rowView.backgroundColor = bgColor;
        }
    }
}

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == self.mainSplitView) {
        if (dividerIndex == 0) {
            return 150; // Left panel minimum
        } else if (dividerIndex == 1) {
            return 300; // Middle panel minimum (from left edge)
        }
    } else if (splitView == self.middleSplitView) {
        if (dividerIndex == 0) {
            return 100; // Chat area minimum height
        }
    }
    return proposedMinimumPosition;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == self.mainSplitView) {
        CGFloat splitViewWidth = splitView.bounds.size.width;
        if (dividerIndex == 0) {
            return splitViewWidth * 0.4; // Left panel can be at most 40%
        } else if (dividerIndex == 1) {
            return splitViewWidth - 150; // Right panel minimum 150
        }
    } else if (splitView == self.middleSplitView) {
        CGFloat splitViewHeight = splitView.bounds.size.height;
        if (self.logScrollView && self.logScrollView.hidden) {
            return splitViewHeight;
        }
        return splitViewHeight - 50;
    }
    return proposedMaximumPosition;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    if (notification.object == self.mainSplitView) {
        [self updateInputLayoutForWidth:self.view.bounds.size.width];
        [self updateChannelPanelLayout];
        [self updateSidePanelLayouts];
    }
}

#pragma mark - User List Actions

- (void)userListDoubleClickAction:(id)sender {
    NSInteger row = self.userListView.clickedRow;
    if (row < 0) {
        return;
    }
    
    NSArray<NSString *> *users = [self displayedUsersForCurrentChannel];
    if (row >= (NSInteger)users.count) {
        return;
    }
    
    NSString *user = users[row];
    NSString *nick = [self baseNickFromUserListEntry:user];
    if (nick.length == 0) {
        return;
    }
    
    // Open private message with this user
    ChannelBuffer *buffer = self.currentChannelKey ? self.channels[self.currentChannelKey] : nil;
    NSString *server = buffer.server.length > 0 ? buffer.server : self.currentServer;
    if (server.length > 0) {
        [self addChannel:server channel:nick isPrivate:YES];
        NSString *channelKey = [self makeChannelKey:server channel:nick];
        [self switchToChannel:channelKey];
    }
}

@end
