//
//  ChatViewController+Input.m
//  i3Chat
//
//  Input handling and command processing for ChatViewController
//

#import "ChatViewController+Private.h"

@implementation ChatViewController (Input)

#pragma mark - NSTextFieldDelegate

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self control:control textView:textView doCommandBySelector:commandSelector];
        });
        return result;
    }
    
    @try {
        if (control == self.inputField && self.inputField) {
            if (commandSelector == @selector(insertNewline:)) {
                [self handleInput];
                return YES;
            } else if (commandSelector == @selector(insertTab:)) {
                [self handleCommandAutocomplete];
                return YES;
            } else if (commandSelector == @selector(moveUp:)) {
                [self navigateHistory:NO];
                return YES;
            } else if (commandSelector == @selector(moveDown:)) {
                [self navigateHistory:YES];
                return YES;
            }
        }
        return NO;
    } @catch (NSException *exception) {
        CVLog(@"Error in control:textView:doCommandBySelector: %@", exception);
        return NO;
    }
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object != self.inputField) {
        return;
    }
    [self updateAutocompleteMenuForInput:self.inputField.stringValue];
}

- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    // When input field gains focus, update channel list text colors
    if (notification.object == self.inputField) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateChannelListTextColors];
        });
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    // When input field loses focus, update channel list text colors
    if (notification.object == self.inputField) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateChannelListTextColors];
        });
    }
}

#pragma mark - Input Handling

- (void)handleInput {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleInput];
        });
        return;
    }
    
    @try {
        if (!self.inputField) {
            CVLog(@"Error: inputField is nil in handleInput");
            return;
        }
        
        NSString *input = [self.inputField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (input.length == 0) {
            return;
        }
        
        CVLog(@"👤 [USER INPUT] %@", input);
        
        [self addToInputHistory:input];
        self.inputField.stringValue = @"";
        self.inputHistoryIndex = -1;
        
        if ([input hasPrefix:@"/me"]) {
            [self handleMeCommand:input];
        } else if ([input hasPrefix:@"/"]) {
            [self handleCommand:input];
        } else if (self.currentChannelKey) {
            [self sendMessageToCurrentChannel:input];
        }
    } @catch (NSException *exception) {
        CVLog(@"Error in handleInput: %@", exception);
        CVLog(@"Stack trace: %@", [exception callStackSymbols]);
    }
}

- (void)handleMeCommand:(NSString *)input {
    NSString *actionText = @"";
    if (input.length > 3) {
        actionText = [[input substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    if (actionText.length == 0) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[self.currentChannelKey];
    IRCClient *client = buffer ? [self clientForServer:buffer.server] : nil;
    IRCConfig *config = buffer ? [self configForServer:buffer.server] : nil;
    
    if (buffer && buffer.name.length > 0 && client && client.isConnected) {
        NSString *target = buffer.name;
        NSString *ctcp = [NSString stringWithFormat:@"%CACTION %@%C", 0x01, actionText, 0x01];
        [client sendMessage:ctcp toTarget:target];
        [self recordRecentChannelKey:self.currentChannelKey];

        NSString *timeStr = [self formatTime];
        NSString *nickStr = config.nick ?: @"";
        NSString *formattedMessage = [NSString stringWithFormat:@"[%@] * %@ %@", timeStr, nickStr, actionText];

        if (buffer.messages) {
            NSUInteger removedCount = [buffer addMessage:formattedMessage];
            if (removedCount > 0) {
                NSMutableArray *cached = self.cachedAttributedMessages[self.currentChannelKey];
                if (cached && cached.count > 0) {
                    NSUInteger deleteCount = MIN(removedCount, cached.count);
                    NSRange deleteRange = NSMakeRange(0, deleteCount);
                    [cached removeObjectsInRange:deleteRange];
                }
                self.channelKeyWithTrimmedHead = self.currentChannelKey;
                self.trimmedHeadCount = removedCount;
            }
            [self displayMessagesForChannel:self.currentChannelKey];
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            @try {
                ChannelBuffer *buffer = self.channels[self.currentChannelKey];
                if (buffer && buffer.allowMessageStorage) {
                    Message *msg = [[Message alloc] initWithWindowKey:self.currentChannelKey
                                                  sender:config.nick ?: @""
                                                  content:actionText
                                                  msgType:@"action"
                                                  timestamp:[NSDate date]];
                    [[MessageStorage sharedStorage] saveMessage:msg];
                }
            } @catch (NSException *exception) {
                CVLog(@"Error saving message: %@", exception);
            }
        });
    }
}

- (void)sendMessageToCurrentChannel:(NSString *)input {
    ChannelBuffer *buffer = self.channels[self.currentChannelKey];
    IRCClient *client = buffer ? [self clientForServer:buffer.server] : nil;
    IRCConfig *config = buffer ? [self configForServer:buffer.server] : nil;
    
    if (buffer && buffer.name.length > 0 && client && client.isConnected) {
        NSString *target = buffer.name;
        [client sendMessage:input toTarget:target];
        [self recordRecentChannelKey:self.currentChannelKey];
        
        NSString *timeStr = [self formatTime];
        NSString *nickStr = config.nick ?: @"";
        NSString *formattedMessage = [NSString stringWithFormat:@"[%@] <%@> %@", timeStr, nickStr, input];
        
        if (buffer.messages) {
            NSUInteger removedCount = [buffer addMessage:formattedMessage];
            if (removedCount > 0) {
                NSMutableArray *cached = self.cachedAttributedMessages[self.currentChannelKey];
                if (cached && cached.count > 0) {
                    NSUInteger deleteCount = MIN(removedCount, cached.count);
                    NSRange deleteRange = NSMakeRange(0, deleteCount);
                    [cached removeObjectsInRange:deleteRange];
                }
                self.channelKeyWithTrimmedHead = self.currentChannelKey;
                self.trimmedHeadCount = removedCount;
            }
            [self displayMessagesForChannel:self.currentChannelKey];
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            @try {
                ChannelBuffer *buffer = self.channels[self.currentChannelKey];
                if (buffer && buffer.allowMessageStorage) {
                    Message *msg = [[Message alloc] initWithWindowKey:self.currentChannelKey
                                                               sender:config.nick ?: @""
                                                               content:input
                                                               msgType:@"self"
                                                               timestamp:[NSDate date]];
                    [[MessageStorage sharedStorage] saveMessage:msg];
                }
            } @catch (NSException *exception) {
                    CVLog(@"Error saving message: %@", exception);
            }
        });
    }
}

#pragma mark - Command Handling

- (void)handleCommand:(NSString *)command {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleCommand:command];
        });
        return;
    }
    
    CVLog(@"⚙️ [COMMAND HANDLER] Processing command: %@", command);
    
    @try {
        if (!command || command.length == 0) {
            return;
        }
        
        NSArray *parts = [command componentsSeparatedByString:@" "];
        if (parts.count == 0) {
            return;
        }
        
        NSString *cmd = [parts[0] lowercaseString];
        
        // Get active server context
        NSString *activeServer = [self determineActiveServer];
        IRCClient *activeClient = [self clientForServer:activeServer];
        IRCConfig *activeConfig = [self configForServer:activeServer];
        
        if ([cmd isEqualToString:@"/join"] && parts.count >= 2) {
            [self handleJoinCommand:parts activeClient:activeClient];
        } else if ([cmd isEqualToString:@"/server"] && parts.count >= 2) {
            [self handleServerCommand:parts activeConfig:activeConfig];
        } else if ([cmd isEqualToString:@"/part"]) {
            [self handlePartCommand:parts activeClient:activeClient];
        } else if ([cmd isEqualToString:@"/msg"] && parts.count >= 3) {
            [self handleMsgCommand:parts activeServer:activeServer activeClient:activeClient];
        } else if ([cmd isEqualToString:@"/quit"]) {
            [self handleQuitCommand];
        } else if ([cmd isEqualToString:@"/raw"] && parts.count >= 2) {
            [self handleRawCommand:parts activeClient:activeClient];
        } else if ([cmd isEqualToString:@"/nick"] && parts.count >= 2) {
            [self handleNickCommand:parts activeClient:activeClient activeConfig:activeConfig];
        } else if ([cmd isEqualToString:@"/help"]) {
            [self showHelp];
        } else if ([cmd isEqualToString:@"/links"]) {
            [self handleLinksCommand:parts activeServer:activeServer activeClient:activeClient];
        } else if ([cmd isEqualToString:@"/list"]) {
            [self handleListCommand:parts activeServer:activeServer activeClient:activeClient];
        } else {
            [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.unknownCommand", @"Unknown command: %@"), cmd]];
        }
    } @catch (NSException *exception) {
        CVLog(@"Error in handleCommand: %@", exception);
        CVLog(@"Stack trace: %@", [exception callStackSymbols]);
    }
}

- (NSString *)determineActiveServer {
    NSString *activeServer = @"";
    NSInteger selectedRow = self.channelListView ? self.channelListView.selectedRow : -1;
    ChannelTreeItem *selectedItem = (selectedRow >= 0) ? [self.channelListView itemAtRow:selectedRow] : nil;
    if ([selectedItem isKindOfClass:[ChannelTreeItem class]]) {
        if (selectedItem.type == ChannelTreeItemTypeServer) {
            activeServer = selectedItem.server ?: @"";
        } else if (selectedItem.type == ChannelTreeItemTypeChannel && selectedItem.channelKey) {
            activeServer = [self serverFromChannelKey:selectedItem.channelKey];
        }
    }
    if (activeServer.length == 0) {
        activeServer = self.currentServer.length > 0
            ? self.currentServer
            : (self.currentChannelKey ? [self serverFromChannelKey:self.currentChannelKey] : (self.serverOrder.count > 0 ? self.serverOrder[0] : @""));
    }
    return activeServer;
}

- (void)handleJoinCommand:(NSArray *)parts activeClient:(IRCClient *)activeClient {
    NSString *channel = parts[1];
    if (activeClient && channel) {
        [activeClient joinChannel:channel];
    }
}

- (void)handleServerCommand:(NSArray *)parts activeConfig:(IRCConfig *)activeConfig {
    NSString *server = parts[1];
    if (!server || server.length == 0) {
        [self addSystemMessage:L(@"chat.message.serverUsage", @"Usage: /server host:port")];
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
    CVLog(@"handleServerCommand: Saving server %@ to history", server);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [[ServerHistoryStorage sharedStorage] touchLoginHistoryWithServer:server
                                                                      nick:config.nick
                                                                   channel:@""
                                                                  realName:config.realName
                                                                    useTLS:config.useTLS];
    });
}

- (void)handlePartCommand:(NSArray *)parts activeClient:(IRCClient *)activeClient {
    NSString *channel = nil;
    NSString *reason = nil;
    
    if (parts.count >= 2) {
        NSString *firstArg = parts[1];
        BOOL looksLikeChannel = [firstArg hasPrefix:@"#"] || [firstArg hasPrefix:@"&"];
        if (looksLikeChannel) {
            channel = firstArg;
            if (parts.count > 2) {
                reason = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@" "];
            }
        } else if (self.currentChannelKey) {
            ChannelBuffer *buffer = self.channels[self.currentChannelKey];
            if (buffer && buffer.isPrivate) {
                [self addSystemMessage:L(@"chat.message.partPrivateNotAllowed", @"Cannot /part a private chat. Specify a channel like /part #channel")];
                return;
            }
            if (buffer && buffer.name.length > 0) {
                channel = buffer.name;
                reason = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@" "];
            } else {
                channel = firstArg;
                if (![channel hasPrefix:@"#"]) {
                    channel = [@"#" stringByAppendingString:channel];
                }
                if (parts.count > 2) {
                    reason = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@" "];
                }
            }
        } else {
            channel = firstArg;
            if (![channel hasPrefix:@"#"]) {
                channel = [@"#" stringByAppendingString:channel];
            }
            if (parts.count > 2) {
                reason = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@" "];
            }
        }
    } else if (self.currentChannelKey) {
        ChannelBuffer *buffer = self.channels[self.currentChannelKey];
        if (buffer && buffer.isPrivate) {
            [self addSystemMessage:L(@"chat.message.partPrivateNotAllowed", @"Cannot /part a private chat. Specify a channel like /part #channel")];
            return;
        }
        channel = buffer.name;
    }

    if (!channel || channel.length == 0) {
        [self addSystemMessage:L(@"chat.message.partUsage", @"Usage: /part [#channel] [reason]")];
        return;
    }

    NSString *partCommand = reason && reason.length > 0
        ? [NSString stringWithFormat:@"PART %@ :%@", channel, reason]
        : [NSString stringWithFormat:@"PART %@", channel];
    
    IRCClient *client = activeClient;
    if (self.currentChannelKey) {
        ChannelBuffer *buffer = self.channels[self.currentChannelKey];
        if (buffer) {
            client = [self clientForServer:buffer.server];
        }
    }
    if (client) {
        [client sendRawCommand:partCommand];
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.leaving", @"Leaving %@..."), channel]];
    }
}

- (void)handleMsgCommand:(NSArray *)parts activeServer:(NSString *)activeServer activeClient:(IRCClient *)activeClient {
    NSString *target = parts[1];
    NSString *message = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@" "];
    if (activeClient && target && message) {
        [activeClient sendMessage:message toTarget:target];
        NSString *channelKey = [self makeChannelKey:activeServer channel:target];
        [self addChannel:activeServer channel:target isPrivate:YES];
        [self recordRecentChannelKey:channelKey];
        [self switchToChannel:channelKey];
    }
}

- (void)handleQuitCommand {
    for (IRCClient *client in self.ircClients.allValues) {
        [client disconnect];
    }
    [NSApp terminate:nil];
}

- (void)handleRawCommand:(NSArray *)parts activeClient:(IRCClient *)activeClient {
    NSString *rawCommand = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@" "];
    if (activeClient && rawCommand) {
        [activeClient sendRawCommand:rawCommand];
    }
}

- (void)handleNickCommand:(NSArray *)parts activeClient:(IRCClient *)activeClient activeConfig:(IRCConfig *)activeConfig {
    NSString *newNick = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!newNick || newNick.length == 0) {
        return;
    }
    if (!activeClient) {
        [self addSystemMessage:L(@"chat.message.nickNoConnection", @"No active server connection for /nick.")];
        return;
    }
    [activeClient sendRawCommand:[NSString stringWithFormat:@"NICK %@", newNick]];
    if (activeConfig) {
        activeConfig.nick = newNick;
    }
    [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.changingNick", @"Changing nickname to %@..."), newNick]];
    [self updateStatus];
}

- (void)handleLinksCommand:(NSArray *)parts activeServer:(NSString *)activeServer activeClient:(IRCClient *)activeClient {
    if (!activeClient) {
        [self addSystemMessage:L(@"chat.message.linksNoConnection", @"No active server connection for /links.")];
        return;
    }
    if (!self.linksListWindowController) {
        self.linksListWindowController = [[LinksListWindowController alloc] init];
    }
    self.linksListServer = activeServer;
    [self.linksListWindowController beginReceivingForServer:activeServer];

    if (parts.count >= 2) {
        NSString *mask = parts[1];
        [activeClient sendRawCommand:[NSString stringWithFormat:@"LINKS %@", mask]];
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.linksRequestingFor", @"Requesting server links for: %@"), mask]];
    } else {
        [activeClient sendRawCommand:@"LINKS"];
        [self addSystemMessage:L(@"chat.message.linksRequesting", @"Requesting server links...")];
    }
}

- (void)handleListCommand:(NSArray *)parts activeServer:(NSString *)activeServer activeClient:(IRCClient *)activeClient {
    CVLog(@"ChatViewController: handleCommand /list called, parts.count=%lu, ircClient=%@", 
          (unsigned long)parts.count, activeClient ? @"set" : @"nil");
    if (parts.count >= 2) {
        NSString *pattern = parts[1];
        if (activeClient) {
            CVLog(@"ChatViewController: Sending LIST command with pattern: %@", pattern);
            self.channelListServer = activeServer;
            [activeClient sendRawCommand:[NSString stringWithFormat:@"LIST %@", pattern]];
            [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.channelListRequestingFor", @"Requesting channel list matching: %@"), pattern]];
        } else {
            CVLog(@"ChatViewController: ERROR - ircClient is nil!");
        }
    } else {
        if (activeClient) {
            CVLog(@"ChatViewController: Sending LIST command without pattern");
            self.channelListServer = activeServer;
            [activeClient sendRawCommand:@"LIST"];
            [self addSystemMessage:L(@"chat.message.channelListRequesting", @"Requesting channel list...")];
        } else {
            CVLog(@"ChatViewController: ERROR - ircClient is nil!");
        }
    }
}

#pragma mark - Autocomplete

- (void)handleCommandAutocomplete {
    if (!self.inputField) {
        return;
    }
    NSString *input = self.inputField.stringValue ?: @"";
    if (![input hasPrefix:@"/"]) {
        return;
    }
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }

    NSArray<NSString *> *commands = [self commandAutocompleteList];
    NSMutableArray<NSString *> *matches = [[NSMutableArray alloc] init];
    for (NSString *command in commands) {
        if ([command hasPrefix:trimmed]) {
            [matches addObject:command];
        }
    }

    if (matches.count == 1) {
        NSString *completed = matches.firstObject;
        if (![completed isEqualToString:trimmed]) {
            self.inputField.stringValue = [completed stringByAppendingString:@" "];
        } else if (![input hasSuffix:@" "]) {
            self.inputField.stringValue = [input stringByAppendingString:@" "];
        }
        [self updateAutocompleteMenuForInput:self.inputField.stringValue];
    } else if (matches.count > 1) {
        [self showAutocompleteMenuWithMatches:matches];
    }
}

- (void)updateAutocompleteMenuForInput:(NSString *)input {
    if (!self.inputField) {
        return;
    }
    if (!input || ![input hasPrefix:@"/"]) {
        return;
    }
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }
    NSArray<NSString *> *commands = [self commandAutocompleteList];
    NSMutableArray<NSString *> *matches = [[NSMutableArray alloc] init];
    for (NSString *command in commands) {
        if ([command hasPrefix:trimmed]) {
            [matches addObject:command];
        }
    }
    if (matches.count == 0) {
        return;
    }
    [self showAutocompleteMenuWithMatches:matches];
}

- (void)showAutocompleteMenuWithMatches:(NSArray<NSString *> *)matches {
    NSEvent *event = [NSApp currentEvent];
    if (!event || !self.inputField.window) {
        return;
    }
    self.autocompleteMenu = [[NSMenu alloc] initWithTitle:@"AutocompleteMenu"];
    for (NSString *match in matches) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:match
                                                      action:@selector(handleAutocompleteMenu:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = match;
        [self.autocompleteMenu addItem:item];
    }
    NSPoint location = NSMakePoint(0, -2);
    [self.autocompleteMenu popUpMenuPositioningItem:nil atLocation:location inView:self.inputField];
}

- (void)handleAutocompleteMenu:(id)sender {
    NSString *command = [sender representedObject];
    if (![command isKindOfClass:[NSString class]] || command.length == 0) {
        return;
    }
    self.inputField.stringValue = [command stringByAppendingString:@" "];
}

- (NSArray<NSString *> *)commandAutocompleteList {
    return @[
        @"/join",
        @"/part",
        @"/msg",
        @"/nick",
        @"/server",
        @"/links",
        @"/list",
        @"/raw",
        @"/quit",
        @"/help",
        @"/me"
    ];
}

#pragma mark - Input History

- (void)addToInputHistory:(NSString *)input {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self addToInputHistory:input];
        });
        return;
    }
    
    @try {
        if (!input || input.length == 0) {
            return;
        }
        
        if (!self.inputHistory) {
            self.inputHistory = [[NSMutableArray alloc] init];
        }
        
        if (self.inputHistory.count > 0 && [self.inputHistory.lastObject isEqualToString:input]) {
            return;
        }
        
        [self.inputHistory addObject:input];
        if (self.inputHistory.count > 100) {
            [self.inputHistory removeObjectAtIndex:0];
        }
    } @catch (NSException *exception) {
        CVLog(@"Error in addToInputHistory: %@", exception);
    }
}

- (void)navigateHistory:(BOOL)forward {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self navigateHistory:forward];
        });
        return;
    }
    
    @try {
        if (!self.inputField || !self.inputHistory) {
            return;
        }
        
        if (self.inputHistory.count == 0) {
            return;
        }
        
        if (self.inputHistoryIndex == -1) {
            self.originalInput = self.inputField.stringValue ?: @"";
            if (self.originalInput.length > 0 && self.inputHistory.count > 0 && ![self.inputHistory.lastObject isEqualToString:self.originalInput]) {
                [self addToInputHistory:self.originalInput];
            }
            self.inputHistoryIndex = self.inputHistory.count - 1;
        } else if (forward) {
            if (self.inputHistoryIndex < (NSInteger)self.inputHistory.count - 1) {
                self.inputHistoryIndex++;
            } else {
                self.inputHistoryIndex = -1;
                if (self.inputField) {
                    self.inputField.stringValue = self.originalInput ?: @"";
                }
                return;
            }
        } else {
            if (self.inputHistoryIndex > 0) {
                self.inputHistoryIndex--;
            } else {
                return;
            }
        }
        
        if (self.inputHistoryIndex >= 0 && self.inputHistoryIndex < (NSInteger)self.inputHistory.count && self.inputField) {
            NSString *historyItem = self.inputHistory[self.inputHistoryIndex];
            if (historyItem) {
                self.inputField.stringValue = historyItem;
            }
        }
    } @catch (NSException *exception) {
        CVLog(@"Error in navigateHistory: %@", exception);
        CVLog(@"Stack trace: %@", [exception callStackSymbols]);
    }
}

#pragma mark - Help

- (void)showHelp {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showHelp];
        });
        return;
    }
    
    NSArray<NSString *> *helpMessages = @[
        @"=== i3Chat IRC Client - Available Commands ===",
        @"",
        @"/join #channel          - Join a channel",
        @"/part [#channel] [msg]  - Leave a channel",
        @"/msg <user> <message>   - Send a private message",
        @"/me <action>            - Send ACTION (/me) message",
        @"/nick <newnick>         - Change your nickname",
        @"/server host:port       - Connect to a new server",
        @"/links [mask]           - Show server links list (tree view)",
        @"/list [pattern]         - List available channels (optionally matching pattern)",
        @"/raw <command>          - Send raw IRC command",
        @"/quit                   - Quit the application",
        @"/help                   - Show this help message",
        @"",
        @"Examples:",
        @"  /join #test",
        @"  /part #test",
        @"  /msg alice Hello!",
        @"  /nick newnickname",
        @"  /server irc.libera.chat:6697",
        @"  /links *.libera.chat",
        @"  /list #test*",
        @"  /raw WHOIS alice"
    ];
    
    for (NSString *message in helpMessages) {
        [self addSystemMessage:message];
    }
}

#pragma mark - Keyboard Navigation

- (BOOL)handleChannelListNavigation:(NSEvent *)event {
    if (!self.channelListView) {
        return NO;
    }
    
    if (!self.channelListView.superview || !self.channelListView.superview.superview) {
        return NO;
    }
    
    // Handle up arrow key (keyCode 126)
    if (event.keyCode == 126) {
        NSInteger currentRow = self.channelListView.selectedRow;
        if (currentRow > 0) {
            NSInteger nextRow = [self nextSelectableChannelRowFrom:currentRow direction:-1];
            if (nextRow >= 0) {
                [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:nextRow] byExtendingSelection:NO];
                [self.channelListView scrollRowToVisible:nextRow];
                return YES;
            }
        } else if (currentRow == -1 && self.channelListView.numberOfRows > 0) {
            NSInteger firstRow = [self firstSelectableChannelRow];
            if (firstRow >= 0) {
                [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:firstRow] byExtendingSelection:NO];
                [self.channelListView scrollRowToVisible:firstRow];
                return YES;
            }
        }
    }
    // Handle down arrow key (keyCode 125)
    else if (event.keyCode == 125) {
        NSInteger currentRow = self.channelListView.selectedRow;
        NSInteger totalRows = self.channelListView.numberOfRows;
        if (currentRow >= 0 && currentRow < totalRows - 1) {
            NSInteger nextRow = [self nextSelectableChannelRowFrom:currentRow direction:1];
            if (nextRow >= 0) {
                [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:nextRow] byExtendingSelection:NO];
                [self.channelListView scrollRowToVisible:nextRow];
                return YES;
            }
        } else if (currentRow == -1 && totalRows > 0) {
            NSInteger firstRow = [self firstSelectableChannelRow];
            if (firstRow >= 0) {
                [self.channelListView selectRowIndexes:[NSIndexSet indexSetWithIndex:firstRow] byExtendingSelection:NO];
                [self.channelListView scrollRowToVisible:firstRow];
                return YES;
            }
        }
    }
    
    return NO;
}

- (NSInteger)firstSelectableChannelRow {
    NSInteger totalRows = self.channelListView.numberOfRows;
    for (NSInteger row = 0; row < totalRows; row++) {
        ChannelTreeItem *item = [self.channelListView itemAtRow:row];
        if ([item isKindOfClass:[ChannelTreeItem class]] && item.type == ChannelTreeItemTypeChannel) {
            return row;
        }
    }
    return -1;
}

- (NSInteger)nextSelectableChannelRowFrom:(NSInteger)start direction:(NSInteger)direction {
    NSInteger totalRows = self.channelListView.numberOfRows;
    NSInteger row = start;
    while (true) {
        row += direction;
        if (row < 0 || row >= totalRows) {
            return -1;
        }
        ChannelTreeItem *item = [self.channelListView itemAtRow:row];
        if ([item isKindOfClass:[ChannelTreeItem class]] && item.type == ChannelTreeItemTypeChannel) {
            return row;
        }
    }
}

@end
