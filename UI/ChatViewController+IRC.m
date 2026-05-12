//
//  ChatViewController+IRC.m
//  i3Chat
//
//  IRC client delegate implementation for ChatViewController
//

#import "ChatViewController+Private.h"

@implementation ChatViewController (IRC)

#pragma mark - Helper Methods for User List Management

// Remove user from buffer.users by base nickname (handles all prefix variants)
- (BOOL)removeUserFromBuffer:(ChannelBuffer *)buffer byBaseNick:(NSString *)baseNick {
    if (!buffer || !buffer.users || !baseNick || baseNick.length == 0) {
        return NO;
    }
    
    BOOL didRemove = NO;
    NSMutableArray *toRemove = [[NSMutableArray alloc] init];
    
    // Find all entries that match the base nickname (with any prefix)
    for (NSString *user in buffer.users) {
        NSString *userBaseNick = [self baseNickFromUserListEntry:user];
        if ([userBaseNick caseInsensitiveCompare:baseNick] == NSOrderedSame) {
            [toRemove addObject:user];
            didRemove = YES;
        }
    }
    
    // Remove all matching entries
    for (NSString *userToRemove in toRemove) {
        [buffer.users removeObject:userToRemove];
    }
    
    return didRemove;
}

#pragma mark - IRCClientDelegate

- (void)ircClientDidConnect:(IRCClient *)client {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        [self.disconnectedServers removeObject:server];
        
        // Ensure server status buffer exists (not shown as a separate channel in the list)
        // The server address itself acts as the status window when clicked
        NSString *statusChannelKey = [self makeChannelKey:server channel:server];
        if (!self.channels[statusChannelKey]) {
            // Create buffer for server status window without adding to channel tree
            ChannelBuffer *buffer = [[ChannelBuffer alloc] initWithName:server server:server isPrivate:NO];
            self.channels[statusChannelKey] = buffer;
        }
        
        // Switch to server status window if:
        // 1. No channel is selected, or
        // 2. The current channel key is the server status (user was waiting for connection)
        if (!self.currentChannelKey || [self.currentChannelKey isEqualToString:statusChannelKey]) {
            [self switchToChannel:statusChannelKey];
        }
        
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.connected", @"Connected to %@"), server] forServer:server];
        [self reloadChannelListPreservingSelection];
        
        // Save server to login history so it appears in login window and menus
        // Use touchLoginHistoryWithServer to update last_connected time without modifying password
        if (server.length > 0) {
            IRCConfig *config = client.config;
            CVLog(@"ircClientDidConnect: Saving server %@ to history", server);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                BOOL success = [[ServerHistoryStorage sharedStorage] touchLoginHistoryWithServer:server
                                                                             nick:config.nick
                                                                          channel:config.channel
                                                                         realName:config.realName
                                                                           useTLS:config.useTLS];
                CVLog(@"ircClientDidConnect: touchLoginHistoryWithServer returned %@", success ? @"YES" : @"NO");
            });
        }
    });
}

- (void)ircClientDidDisconnect:(IRCClient *)client error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        [self.disconnectedServers addObject:server];
        [self clearUsersForServer:server];
        
        NSString *errorMsg = error ? [NSString stringWithFormat:@" (%@)", error.localizedDescription] : @"";
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.disconnected", @"Disconnected from %@%@"), server, errorMsg] forServer:server];
        [self reloadChannelListPreservingSelection];
    });
}

- (void)ircClient:(IRCClient *)client didReceiveSystemMessage:(NSString *)message {
    // System messages (welcome info, MOTD, WHOIS results, etc.) go to the server status window
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        [self addSystemMessage:message forServer:server];
    });
}

- (void)ircClient:(IRCClient *)client didReceiveMessage:(NSString *)message fromNick:(NSString *)nick inChannel:(NSString *)channel isPrivate:(BOOL)isPrivate {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSString *server = client.config.server ?: @"";
            
            // Validate channel name - skip invalid channel names
            // Valid channels start with # or & and don't contain : or spaces
            // Valid private message targets are nicknames (no # or & prefix, no : or spaces)
            if (channel.length == 0) {
                return;
            }
            BOOL isChannelTarget = [channel hasPrefix:@"#"] || [channel hasPrefix:@"&"];
            if (isChannelTarget) {
                // Channel names should not contain : (indicates malformed message)
                if ([channel containsString:@":"]) {
                    CVLog(@"Skipping invalid channel name: %@", channel);
                    return;
                }
            }
            
            NSString *channelKey = [self makeChannelKey:server channel:channel];
            
            ChannelBuffer *buffer = self.channels[channelKey];
            if (!buffer) {
                [self addChannel:server channel:channel isPrivate:isPrivate];
                buffer = self.channels[channelKey];
            }
            
            if (buffer) {
                NSString *timeStr = [self formatTime];
                NSString *formattedMessage = [NSString stringWithFormat:@"[%@] <%@> %@", timeStr, nick, message];
                // PERFORMANCE OPTIMIZATION: Batch deletion
                // addMessage returns the number of messages removed (0, or 100 when threshold reached)
                NSUInteger removedCount = [buffer addMessage:formattedMessage];
                
                if (removedCount > 0) {
                    NSMutableArray *cached = self.cachedAttributedMessages[channelKey];
                    if (cached && cached.count > 0) {
                        // Batch delete from cache
                        NSUInteger deleteCount = MIN(removedCount, cached.count);
                        NSRange deleteRange = NSMakeRange(0, deleteCount);
                        [cached removeObjectsInRange:deleteRange];
                    }
                    
                    if ([channelKey isEqualToString:self.currentChannelKey]) {
                        self.channelKeyWithTrimmedHead = channelKey;
                        self.trimmedHeadCount = removedCount;
                    }
                }
                
                if ([channelKey isEqualToString:self.currentChannelKey]) {
                    [self displayMessagesForChannel:channelKey];
                } else {
                    buffer.unreadCount++;
                    [self reloadChannelListPreservingSelection];
                }
                
                // Save to storage
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                     @try { ChannelBuffer *buffer = self.channels[channelKey];
                        if (buffer && buffer.allowMessageStorage) {
                            Message *msg = [[Message alloc] initWithWindowKey:channelKey
                                                                       sender:nick
                                                                      content:message
                                                                      msgType:isPrivate ? @"private" :@"other"
                                                                    timestamp:[NSDate date]];
                            [[MessageStorage sharedStorage] saveMessage:msg];
                        }
                    } @catch (NSException *exception) {
                        CVLog(@"Error saving message: %@", exception);
                    }
                });
            }
        } @catch (NSException *exception) {
            CVLog(@"Error in didReceiveMessage: %@", exception);
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveNotice:(NSString *)notice fromNick:(NSString *)nick {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        NSString *formattedMessage = [NSString stringWithFormat:@"[%@] *** Notice from %@: %@", [self formatTime], nick, notice];
        
        // Notice messages go to the server status window (like system messages)
        NSString *targetChannelKey = nil;
        
        if (server.length > 0) {
            // Use server address as the status channel name
            NSString *statusChannel = server;
            targetChannelKey = [self makeChannelKey:server channel:statusChannel];
            
            // Create server status buffer if it doesn't exist (without adding to channel tree)
            ChannelBuffer *existingBuffer = self.channels[targetChannelKey];
            if (!existingBuffer) {
                ChannelBuffer *buffer = [[ChannelBuffer alloc] initWithName:server server:server isPrivate:NO];
                self.channels[targetChannelKey] = buffer;
            }
        }
        
        // Fallback
        if (!targetChannelKey) {
            NSArray<NSString *> *serverChannels = self.serverChannelOrder[server];
            if (serverChannels && serverChannels.count > 0) {
                targetChannelKey = serverChannels[0];
            }
        }
        
        if (targetChannelKey) {
            ChannelBuffer *buffer = self.channels[targetChannelKey];
            if (buffer) {
                NSUInteger removedCount = [buffer addMessage:formattedMessage];
                if (removedCount > 0) {
                    NSMutableArray *cached = self.cachedAttributedMessages[targetChannelKey];
                    if (cached && cached.count > 0) {
                        NSUInteger deleteCount = MIN(removedCount, cached.count);
                        NSRange deleteRange = NSMakeRange(0, deleteCount);
                        [cached removeObjectsInRange:deleteRange];
                    }
                    if ([targetChannelKey isEqualToString:self.currentChannelKey]) {
                        self.channelKeyWithTrimmedHead = targetChannelKey;
                        self.trimmedHeadCount = removedCount;
                    }
                }
                if ([targetChannelKey isEqualToString:self.currentChannelKey]) {
                    [self displayMessagesForChannel:targetChannelKey];
                } else {
                    // Mark as unread if not currently viewing
                    buffer.unreadCount++;
                    [self reloadChannelListPreservingSelection];
                }
            }
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveAction:(NSString *)action from:(NSString *)sender inChannel:(NSString *)channel {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        
        // Validate channel name - skip invalid channel names
        if (channel.length == 0) {
            return;
        }
        BOOL isChannelTarget = [channel hasPrefix:@"#"] || [channel hasPrefix:@"&"];
        if (isChannelTarget && [channel containsString:@":"]) {
            CVLog(@"Skipping invalid channel name in action: %@", channel);
            return;
        }
        
        NSString *channelKey = [self makeChannelKey:server channel:channel];
        
        ChannelBuffer *buffer = self.channels[channelKey];
        if (!buffer) {
            BOOL isPrivate = !isChannelTarget;
            [self addChannel:server channel:channel isPrivate:isPrivate];
            buffer = self.channels[channelKey];
        }
        
        if (buffer) {
            NSString *timeStr = [self formatTime];
            NSString *formattedMessage = [NSString stringWithFormat:@"[%@] * %@ %@", timeStr, sender, action];
            NSUInteger removedCount = [buffer addMessage:formattedMessage];
            
            if (removedCount > 0) {
                NSMutableArray *cached = self.cachedAttributedMessages[channelKey];
                if (cached && cached.count > 0) {
                    NSUInteger deleteCount = MIN(removedCount, cached.count);
                    NSRange deleteRange = NSMakeRange(0, deleteCount);
                    [cached removeObjectsInRange:deleteRange];
                }
                if ([channelKey isEqualToString:self.currentChannelKey]) {
                    self.channelKeyWithTrimmedHead = channelKey;
                    self.trimmedHeadCount = removedCount;
                }
            }
            
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                [self displayMessagesForChannel:channelKey];
            } else {
                buffer.unreadCount++;
                [self reloadChannelListPreservingSelection];
            }

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                @try {
                    ChannelBuffer *buffer = self.channels[channelKey];
                    if (buffer && buffer.allowMessageStorage) {
                        Message *msg = [[Message alloc] initWithWindowKey:channelKey
                        sender:sender
                        content:action
                        msgType:@"action"
                        timestamp:[NSDate date]];
                        [[MessageStorage sharedStorage] saveMessage:msg];
                    }
                } @catch (NSException *exception) {
                    CVLog(@"Error saving action message: %@", exception);
                }
            });
        }
    });
}

- (void)ircClient:(IRCClient *)client didJoinChannel:(NSString *)channel {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        
        // Validate channel name - skip invalid channel names
        // Valid channels start with # or & and don't contain : or spaces
        if (channel.length == 0) {
            return;
        }
        if ([channel containsString:@":"]) {
            CVLog(@"Skipping invalid channel name in didJoinChannel: %@", channel);
            return;
        }
        
        [self addChannel:server channel:channel isPrivate:NO];
        
        NSMutableSet<NSString *> *joinedSet = [self joinedChannelSetForServer:server createIfNeeded:YES];
        [joinedSet addObject:channel];
        
        NSMutableSet<NSString *> *autoJoinSet = [self autoJoinChannelSetForServer:server createIfNeeded:YES];
        [autoJoinSet addObject:channel];
        
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.joined", @"Joined %@"), channel] forServer:server];
        
        // Never auto-switch to joined channel - just reload to show it in the list
        // User must manually click to switch to the channel
        [self reloadChannelListPreservingSelection];
        
        [self persistServersAndChannels];
    });
}

- (void)ircClient:(IRCClient *)client didPartChannel:(NSString *)channel {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        NSString *channelKey = [self makeChannelKey:server channel:channel];
        
        NSMutableSet<NSString *> *joinedSet = [self joinedChannelSetForServer:server createIfNeeded:NO];
        [joinedSet removeObject:channel];
        
        NSMutableSet<NSString *> *autoJoinSet = [self autoJoinChannelSetForServer:server createIfNeeded:NO];
        [autoJoinSet removeObject:channel];
        
        ChannelBuffer *buffer = self.channels[channelKey];
        if (buffer && buffer.users) {
            [buffer.users removeAllObjects];
        }
        
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.left", @"Left %@"), channel] forServer:server];
        
        [self reloadChannelListPreservingSelection];
        if ([channelKey isEqualToString:self.currentChannelKey]) {
            [self updateUserListForChannel:channelKey];
        }
        [self persistServersAndChannels];
    });
}

- (void)ircClient:(IRCClient *)client userJoined:(NSString *)nick inChannel:(NSString *)channel {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        NSString *channelKey = [self makeChannelKey:server channel:channel];
        
        ChannelBuffer *buffer = self.channels[channelKey];
        if (buffer) {
            // Ensure buffer.users is initialized
            if (!buffer.users) {
                buffer.users = [[NSMutableArray alloc] init];
            }
            
            // Check if user already exists (by base nickname, ignoring prefixes)
            BOOL userExists = NO;
            NSString *normalizedNick = [nick lowercaseString];
            for (NSString *existingUser in buffer.users) {
                NSString *existingBaseNick = [self baseNickFromUserListEntry:existingUser];
                if ([[existingBaseNick lowercaseString] isEqualToString:normalizedNick]) {
                    userExists = YES;
                    break;
                }
            }
            
            if (!userExists) {
                [buffer.users addObject:nick];
                [buffer.users sortUsingSelector:@selector(compare:)];
            }
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                [self updateUserListForChannel:channelKey];
            }
        }
        
        NSString *timeStr = [self formatTime];
        NSString *formattedMessage = [NSString stringWithFormat:@"[%@] *** %@ %@", timeStr, nick, L(@"chat.message.userJoined", @"has joined")];
        if (buffer) {
            NSUInteger removedCount = [buffer addMessage:formattedMessage];
            if (removedCount > 0) {
                NSMutableArray *cached = self.cachedAttributedMessages[channelKey];
                if (cached && cached.count > 0) {
                    NSUInteger deleteCount = MIN(removedCount, cached.count);
                    NSRange deleteRange = NSMakeRange(0, deleteCount);
                    [cached removeObjectsInRange:deleteRange];
                }
                if ([channelKey isEqualToString:self.currentChannelKey]) {
                    self.channelKeyWithTrimmedHead = channelKey;
                    self.trimmedHeadCount = removedCount;
                }
            }
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                [self displayMessagesForChannel:channelKey];
            }
        }
    });
}

- (void)ircClient:(IRCClient *)client userParted:(NSString *)nick fromChannel:(NSString *)channel reason:(NSString *)reason {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        NSString *channelKey = [self makeChannelKey:server channel:channel];
        
        ChannelBuffer *buffer = self.channels[channelKey];
        if (buffer && buffer.users) {
            // Use improved removal method that handles all prefix variants
            BOOL didRemove = [self removeUserFromBuffer:buffer byBaseNick:nick];
            if (didRemove && [channelKey isEqualToString:self.currentChannelKey]) {
                [self updateUserListForChannel:channelKey];
            }
        }
        
        NSString *reasonStr = reason.length > 0 ? [NSString stringWithFormat:@" (%@)", reason] : @"";
        NSString *timeStr = [self formatTime];
        NSString *formattedMessage = [NSString stringWithFormat:@"[%@] *** %@ %@%@", timeStr, nick, L(@"chat.message.userLeft", @"has left"), reasonStr];
        if (buffer) {
            NSUInteger removedCount = [buffer addMessage:formattedMessage];
            if (removedCount > 0) {
                NSMutableArray *cached = self.cachedAttributedMessages[channelKey];
                if (cached && cached.count > 0) {
                    NSUInteger deleteCount = MIN(removedCount, cached.count);
                    NSRange deleteRange = NSMakeRange(0, deleteCount);
                    [cached removeObjectsInRange:deleteRange];
                }
                if ([channelKey isEqualToString:self.currentChannelKey]) {
                    self.channelKeyWithTrimmedHead = channelKey;
                    self.trimmedHeadCount = removedCount;
                }
            }
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                [self displayMessagesForChannel:channelKey];
            }
        }
    });
}

- (void)ircClient:(IRCClient *)client userQuit:(NSString *)nick reason:(NSString *)reason {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        
        for (NSString *channelKey in self.serverChannelOrder[server]) {
            ChannelBuffer *buffer = self.channels[channelKey];
            if (buffer && buffer.users) {
                BOOL didRemove = [buffer.users containsObject:nick];
                [buffer.users removeObject:nick];
                NSArray<NSString *> *prefixedNicks = @[
                    [@"@" stringByAppendingString:nick],
                    [@"+" stringByAppendingString:nick],
                    [@"%" stringByAppendingString:nick],
                    [@"&" stringByAppendingString:nick],
                    [@"~" stringByAppendingString:nick]
                ];
                for (NSString *prefixed in prefixedNicks) {
                    if ([buffer.users containsObject:prefixed]) {
                        [buffer.users removeObject:prefixed];
                        didRemove = YES;
                    }
                }
                
                if (didRemove) {
                    NSString *reasonStr = reason.length > 0 ? [NSString stringWithFormat:@" (%@)", reason] : @"";
                    NSString *timeStr = [self formatTime];
                    NSString *formattedMessage = [NSString stringWithFormat:@"[%@] *** %@ %@%@", timeStr, nick, L(@"chat.message.userQuit", @"has quit"), reasonStr];
                    NSUInteger removedCount = [buffer addMessage:formattedMessage];
                    if (removedCount > 0) {
                        NSMutableArray *cached = self.cachedAttributedMessages[channelKey];
                        if (cached && cached.count > 0) {
                            NSUInteger deleteCount = MIN(removedCount, cached.count);
                            NSRange deleteRange = NSMakeRange(0, deleteCount);
                            [cached removeObjectsInRange:deleteRange];
                        }
                        if ([channelKey isEqualToString:self.currentChannelKey]) {
                            self.channelKeyWithTrimmedHead = channelKey;
                            self.trimmedHeadCount = removedCount;
                        }
                    }
                    if ([channelKey isEqualToString:self.currentChannelKey]) {
                        [self displayMessagesForChannel:channelKey];
                        [self updateUserListForChannel:channelKey];
                    }
                }
            }
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveUsers:(NSArray<NSString *> *)users forChannel:(NSString *)channel {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        NSString *channelKey = [self makeChannelKey:server channel:channel];
        
        ChannelBuffer *buffer = self.channels[channelKey];
        if (buffer) {
            if (!buffer.users) {
                buffer.users = [[NSMutableArray alloc] init];
            }
            for (NSString *user in users) {
                if (![buffer.users containsObject:user]) {
                    [buffer.users addObject:user];
                }
            }
            [buffer.users sortUsingSelector:@selector(compare:)];
            
            CVLog(@"didReceiveUsers: Channel %@ now has %lu users", channel, (unsigned long)buffer.users.count);
            
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                [self updateUserListForChannel:channelKey];
            }
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveTopic:(NSString *)topic forChannel:(NSString *)channel {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        NSString *channelKey = [self makeChannelKey:server channel:channel];
        
        ChannelBuffer *buffer = self.channels[channelKey];
        if (buffer) {
            NSString *timeStr = [self formatTime];
            NSString *formattedMessage = [NSString stringWithFormat:@"[%@] *** %@: %@", timeStr, L(@"chat.message.topic", @"Topic"), topic];
            NSUInteger removedCount = [buffer addMessage:formattedMessage];
            if (removedCount > 0) {
                NSMutableArray *cached = self.cachedAttributedMessages[channelKey];
                if (cached && cached.count > 0) {
                    NSUInteger deleteCount = MIN(removedCount, cached.count);
                    NSRange deleteRange = NSMakeRange(0, deleteCount);
                    [cached removeObjectsInRange:deleteRange];
                }
                if ([channelKey isEqualToString:self.currentChannelKey]) {
                    self.channelKeyWithTrimmedHead = channelKey;
                    self.trimmedHeadCount = removedCount;
                }
            }
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                [self displayMessagesForChannel:channelKey];
            }
        }
    });
}

- (void)ircClient:(IRCClient *)client didChangeNick:(NSString *)oldNick toNick:(NSString *)newNick inChannels:(NSArray<NSString *> *)channels {
    NSString *server = client.config.server ?: @"";
    NSString *normalizedOldNick = [oldNick lowercaseString];
    NSCharacterSet *modePrefixes = [NSCharacterSet characterSetWithCharactersInString:@"@+%&~"];
    BOOL updatedCurrent = NO;
    NSMutableSet<NSString *> *processedChannels = [[NSMutableSet alloc] init];

    // First, process channels from the IRCClient (from namesMap)
    for (NSString *channel in channels) {
        NSString *channelKey = [self makeChannelKey:server channel:channel];
        [processedChannels addObject:channelKey];
        ChannelBuffer *buffer = self.channels[channelKey];
        if (!buffer || !buffer.users) {
            continue;
        }
        BOOL updatedBuffer = NO;
        for (NSUInteger i = 0; i < buffer.users.count; i++) {
            NSString *user = buffer.users[i];
            if (!user) continue;
            NSString *baseUser = user;
            while (baseUser.length > 0) {
                unichar firstChar = [baseUser characterAtIndex:0];
                if (![modePrefixes characterIsMember:firstChar]) break;
                baseUser = [baseUser substringFromIndex:1];
            }
            if (baseUser.length == 0) continue;
            if ([[baseUser lowercaseString] isEqualToString:normalizedOldNick]) {
                NSString *prefix = [user substringToIndex:user.length - baseUser.length];
                buffer.users[i] = [NSString stringWithFormat:@"%@%@", prefix, newNick];
                updatedBuffer = YES;
            }
        }
        if (updatedBuffer) {
            [buffer.users sortUsingSelector:@selector(compare:)];
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                updatedCurrent = YES;
            }
        }
    }

    // Also check all buffers for this server to catch any channels that might have been missed
    // This is especially important when we change our own nickname, as namesMap might not be fully synced
    for (NSString *channelKey in self.channels.allKeys) {
        if ([processedChannels containsObject:channelKey]) {
            continue; // Already processed
        }
        ChannelBuffer *buffer = self.channels[channelKey];
        if (!buffer || ![buffer.server isEqualToString:server] || !buffer.users) {
            continue;
        }
        BOOL updatedBuffer = NO;
        for (NSUInteger i = 0; i < buffer.users.count; i++) {
            NSString *user = buffer.users[i];
            if (!user) continue;
            NSString *baseUser = user;
            while (baseUser.length > 0) {
                unichar firstChar = [baseUser characterAtIndex:0];
                if (![modePrefixes characterIsMember:firstChar]) break;
                baseUser = [baseUser substringFromIndex:1];
            }
            if (baseUser.length == 0) continue;
            if ([[baseUser lowercaseString] isEqualToString:normalizedOldNick]) {
                NSString *prefix = [user substringToIndex:user.length - baseUser.length];
                buffer.users[i] = [NSString stringWithFormat:@"%@%@", prefix, newNick];
                updatedBuffer = YES;
            }
        }
        if (updatedBuffer) {
            [buffer.users sortUsingSelector:@selector(compare:)];
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                updatedCurrent = YES;
            }
        }
    }

    if (updatedCurrent && self.currentChannelKey) {
        [self updateUserListForChannel:self.currentChannelKey];
    }
    if ([server isEqualToString:self.currentServer]) {
        [self updateStatus];
        ChannelBuffer *currentBuffer = self.channels[self.currentChannelKey];
        if (currentBuffer) {
            [self updateWindowTitleForChatName:currentBuffer.name];
        }
    }
}

- (void)ircClient:(IRCClient *)client nicknameInUse:(NSString *)nick {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addSystemMessage:[NSString stringWithFormat:L(@"chat.message.nickInUse", @"Nickname %@ is already in use"), nick]];
    });
}

- (void)ircClientDidRegister:(IRCClient *)client {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addSystemMessage:L(@"chat.message.registered", @"Registered with server")];

        NSString *server = client.config.server ?: @"";
        if (server.length == 0) {
            return;
        }
        NSMutableSet<NSString *> *autoJoinSet = [self autoJoinChannelSetForServer:server createIfNeeded:NO];
        if (autoJoinSet.count > 0) {
            for (NSString *channel in autoJoinSet) {
                if (![channel hasPrefix:@"#"] && ![channel hasPrefix:@"&"]) {
                    [client joinChannel:[@"#" stringByAppendingString:channel]];
                } else {
                    [client joinChannel:channel];
                }
            }
        }
    });
}

- (ChannelListWindowController *)channelListWindowControllerForClient:(IRCClient *)client {
    NSString *server = client.config.server;
    if (!server || server.length == 0) {
        return nil;
    }
    
    ChannelListWindowController *controller = self.channelListWindowControllers[server];
    if (!controller) {
        controller = [[ChannelListWindowController alloc] initWithServerAddress:server];
        controller.delegate = self;
        self.channelListWindowControllers[server] = controller;
    }
    return controller;
}

- (void)ircClientDidReceiveChannelListStart:(IRCClient *)client {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server;
        CVLog(@"Channel list start received from server: %@", server);
        
        ChannelListWindowController *controller = [self channelListWindowControllerForClient:client];
        if (controller) {
            // Reset the channel list for new data
            [controller clearChannels];
            // Show the window immediately so user sees it's loading
            [controller showWindow:nil];
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveChannelListItem:(NSString *)channel userCount:(NSInteger)userCount topic:(NSString *)topic {
    dispatch_async(dispatch_get_main_queue(), ^{
        ChannelListWindowController *controller = [self channelListWindowControllerForClient:client];
        if (controller) {
            [controller addChannel:channel userCount:userCount topic:topic];
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveChannelList:(NSArray<NSDictionary<NSString *, id> *> *)channels {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server;
        CVLog(@"Received complete channel list with %lu channels from server: %@", (unsigned long)channels.count, server);
        
        ChannelListWindowController *controller = [self channelListWindowControllerForClient:client];
        if (controller) {
            // Use setChannelList: to set all channels at once - this will:
            // 1. Replace all existing channels with the complete list
            // 2. Trigger background sorting by user count
            // 3. Refresh the table view after sorting
            [controller setChannelList:channels];
        }
    });
}

- (void)ircClientDidReceiveChannelListEnd:(IRCClient *)client {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server;
        CVLog(@"Channel list end received from server: %@", server);
        
        // Note: setChannelList: already handles sorting, so we just ensure window is shown
        // finalizeChannels would cause redundant sorting after setChannelList:
        ChannelListWindowController *controller = self.channelListWindowControllers[server];
        if (controller) {
            // Ensure window is visible and brought to front
            [controller showWindow:nil];
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveLinksItemWithServer:(NSString *)server mask:(NSString *)mask hopCount:(NSInteger)hopCount info:(NSString *)info {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.linksListWindowController) {
            [self.linksListWindowController addLinkWithServer:server mask:mask hopCount:hopCount info:info];
        }
    });
}

- (void)ircClientDidReceiveLinksEnd:(IRCClient *)client {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.linksListWindowController) {
            [self.linksListWindowController finalizeLinks];
            [self.linksListWindowController showWindow:nil];
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveWhoisInfo:(NSDictionary<NSString *, id> *)info forNick:(NSString *)nick {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Check if this is the nick we're waiting for
        if (self.pendingWhoisNick && [self.pendingWhoisNick caseInsensitiveCompare:nick] == NSOrderedSame) {
            // Create window if needed
            if (!self.whoisWindowController || ![self.whoisWindowController.nickname isEqualToString:nick]) {
                NSString *server = self.pendingWhoisServer ?: client.config.server;
                self.whoisWindowController = [[WhoisWindowController alloc] initWithNickname:nick server:server];
                self.whoisWindowController.delegate = self;
            }
            [self.whoisWindowController setWhoisInfo:info];
            [self.whoisWindowController showWindow:nil];
            [self.whoisWindowController.window makeKeyAndOrderFront:nil];
            self.pendingWhoisNick = nil;
            self.pendingWhoisServer = nil;
        }
    });
}

- (void)ircClient:(IRCClient *)client didReceiveRawMessage:(NSString *)rawMessage {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Debug logging to understand the issue
        CVLog(@"[RAW MESSAGE] Received: %@", rawMessage);
        CVLog(@"[RAW MESSAGE] logTextView: %@, logWindowVisible: %@", self.logTextView ? @"YES" : @"NO", self.logWindowVisible ? @"YES" : @"NO");
        
        // Only show raw server messages in the log window when it's visible
        if (self.logTextView && self.logWindowVisible) {
            NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", [self formatTime], rawMessage];
            [self.logTextView.textStorage.mutableString appendString:logEntry];
            BOOL shouldScroll = self.logUserPinnedToBottom || !self.logUserIsScrolling;
            if (shouldScroll) {
                [self.logTextView scrollToEndOfDocument:nil];
            }
            CVLog(@"[RAW MESSAGE] Appended to log window");
        }
    });
}

#pragma mark - User List Updates

- (void)ircClient:(IRCClient *)client didUpdateUserList:(NSArray<NSString *> *)users forChannel:(NSString *)channel {
    CVLog(@"=== didUpdateUserList START ===");
    CVLog(@"didUpdateUserList: Received %lu users for channel %@", (unsigned long)users.count, channel);
    CVLog(@"didUpdateUserList: Users: %@", users);
    NSString *server = client.config.server ?: @"";
    CVLog(@"didUpdateUserList: currentServer = %@", self.currentServer);
    
    NSString *channelKey = [self makeChannelKey:server channel:channel];
    CVLog(@"didUpdateUserList: Generated channelKey = %@", channelKey);
    CVLog(@"didUpdateUserList: currentChannelKey = %@", self.currentChannelKey);
    CVLog(@"didUpdateUserList: Available channelKeys: %@", [self.channels allKeys]);
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (buffer) {
        CVLog(@"didUpdateUserList: Found buffer for channelKey");
        buffer.users = [users mutableCopy];
        CVLog(@"didUpdateUserList: Updated buffer.users with %lu users: %@", (unsigned long)buffer.users.count, buffer.users);
        
        // Always update UI if this is the current channel
        BOOL isCurrentChannel = [channelKey isEqualToString:self.currentChannelKey];
        CVLog(@"didUpdateUserList: Channel match check: %@ == %@ ? %@", channelKey, self.currentChannelKey, isCurrentChannel ? @"YES" : @"NO");
        
        if (isCurrentChannel) {
            CVLog(@"didUpdateUserList: Channel matches current, updating UI");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateUserListForChannel:channelKey];
            });
        } else {
            CVLog(@"didUpdateUserList: Channel does not match current");
            // Also update if no current channel is set
            if (!self.currentChannelKey) {
                CVLog(@"didUpdateUserList: No current channel set, setting it to %@", channelKey);
                [self switchToChannel:channelKey];
            }
        }
    } else {
        CVLog(@"ERROR: No buffer found for channelKey %@", channelKey);
        // Try to create buffer if channel exists (but validate first)
        if (channel && channel.length > 0 && ![channel containsString:@":"]) {
            CVLog(@"didUpdateUserList: Creating buffer for channel %@", channel);
            [self addChannel:server channel:channel isPrivate:NO];
            buffer = self.channels[channelKey];
            if (buffer) {
                CVLog(@"didUpdateUserList: Buffer created successfully");
                buffer.users = [users mutableCopy];
                if (!self.currentChannelKey) {
                    [self switchToChannel:channelKey];
                } else if ([channelKey isEqualToString:self.currentChannelKey]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self updateUserListForChannel:channelKey];
                    });
                }
            } else {
                CVLog(@"ERROR: Failed to create buffer");
            }
        }
    }
    CVLog(@"=== didUpdateUserList END ===");
}

- (void)ircClient:(IRCClient *)client didAddUser:(NSString *)user toChannel:(NSString *)channel {
    NSString *server = client.config.server ?: @"";
    NSString *channelKey = [self makeChannelKey:server channel:channel];
    ChannelBuffer *buffer = self.channels[channelKey];
    if (buffer) {
        // Ensure buffer.users is initialized
        if (!buffer.users) {
            buffer.users = [[NSMutableArray alloc] init];
        }
        
        // Check if user already exists (by base nickname, ignoring prefixes)
        BOOL userExists = NO;
        NSString *normalizedUser = [[self baseNickFromUserListEntry:user] lowercaseString];
        for (NSString *existingUser in buffer.users) {
            NSString *existingBaseNick = [self baseNickFromUserListEntry:existingUser];
            if ([[existingBaseNick lowercaseString] isEqualToString:normalizedUser]) {
                userExists = YES;
                break;
            }
        }
        
        if (!userExists) {
            [buffer.users addObject:user];
            [buffer.users sortUsingSelector:@selector(compare:)];
            if ([channelKey isEqualToString:self.currentChannelKey]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateUserListForChannel:channelKey];
                });
            }
        }
    }
}

- (void)ircClient:(IRCClient *)client didRemoveUserFromAllChannels:(NSString *)user reason:(NSString *)reason {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *server = client.config.server ?: @"";
        
        // Iterate through all channels for this server and remove the user
        for (NSString *channelKey in self.channels.allKeys) {
            ChannelBuffer *buffer = self.channels[channelKey];
            // Only process channels for this server (skip private chats and server status)
            if (buffer && [buffer.server isEqualToString:server] && !buffer.isPrivate && buffer.users) {
                // Use improved removal method that handles all prefix variants
                BOOL didRemove = [self removeUserFromBuffer:buffer byBaseNick:user];
                
                // Display quit message in channel (similar to PART command)
                if (didRemove) {
                    NSString *reasonStr = reason.length > 0 ? [NSString stringWithFormat:@" (%@)", reason] : @"";
                    NSString *timeStr = [self formatTime];
                    NSString *formattedMessage = [NSString stringWithFormat:@"[%@] *** %@ %@%@", timeStr, user, L(@"chat.message.userQuit", @"has quit"), reasonStr];
                    NSUInteger removedCount = [buffer addMessage:formattedMessage];
                    if (removedCount > 0) {
                        NSMutableArray *cached = self.cachedAttributedMessages[channelKey];
                        if (cached && cached.count > 0) {
                            NSUInteger deleteCount = MIN(removedCount, cached.count);
                            NSRange deleteRange = NSMakeRange(0, deleteCount);
                            [cached removeObjectsInRange:deleteRange];
                        }
                        if ([channelKey isEqualToString:self.currentChannelKey]) {
                            self.channelKeyWithTrimmedHead = channelKey;
                            self.trimmedHeadCount = removedCount;
                        }
                    }
                    if ([channelKey isEqualToString:self.currentChannelKey]) {
                        [self displayMessagesForChannel:channelKey];
                        [self updateUserListForChannel:channelKey];
                    }
                }
            }
        }
    });
}

- (void)ircClient:(IRCClient *)client didRemoveUser:(NSString *)user fromChannel:(NSString *)channel {
    NSString *server = client.config.server ?: @"";
    NSString *channelKey = [self makeChannelKey:server channel:channel];
    ChannelBuffer *buffer = self.channels[channelKey];
    if (buffer && buffer.users) {
        // Use improved removal method that handles all prefix variants
        BOOL didRemove = [self removeUserFromBuffer:buffer byBaseNick:user];
        if (didRemove && [channelKey isEqualToString:self.currentChannelKey]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateUserListForChannel:channelKey];
            });
        }
    }
}

#pragma mark - ChannelListWindowControllerDelegate

- (void)channelListWindowController:(ChannelListWindowController *)controller didSelectChannel:(NSString *)channel {
    if (!channel || channel.length == 0) {
        return;
    }
    
    // Use the controller's serverAddress to determine which server to join the channel on
    NSString *server = controller.serverAddress;
    if (!server || server.length == 0) {
        // Fallback to channelListServer or currentServer
        server = self.channelListServer;
        if (!server || server.length == 0) {
            server = self.currentServer;
        }
    }
    
    IRCClient *client = [self clientForServer:server];
    if (client && client.isConnected && ![self.disconnectedServers containsObject:server]) {
        [client joinChannel:channel];
    }
}

- (void)channelListWindowControllerDidRequestRefresh:(ChannelListWindowController *)controller {
    // Use the controller's serverAddress to determine which server to request channel list from
    NSString *server = controller.serverAddress;
    if (!server || server.length == 0) {
        // Fallback to channelListServer or currentServer
        server = self.channelListServer;
        if (!server || server.length == 0) {
            server = self.currentServer;
        }
    }
    
    IRCClient *client = [self clientForServer:server];
    if (client && client.isConnected && ![self.disconnectedServers containsObject:server]) {
        // Send LIST command to refresh channel list
        [client sendRawCommand:@"LIST"];
    }
}

@end
