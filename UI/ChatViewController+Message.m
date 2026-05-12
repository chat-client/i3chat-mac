//
//  ChatViewController+Message.m
//  i3Chat
//
//  Message processing and formatting for ChatViewController
//

#import "ChatViewController+Private.h"
#import "DebugLog.h"

// Custom attribute key for clickable nicknames
static NSString * const ChatNicknameAttributeKey = @"ChatNicknameAttribute";

@implementation ChatViewController (Message)

#pragma mark - Message Display

- (void)displayMessagesForChannel:(NSString *)channelKey {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self displayMessagesForChannel:channelKey];
        });
        return;
    }
    
    if (!channelKey || channelKey.length == 0 || !self.chatTextView) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer) {
        return;
    }
    
    // Only render the current channel
    BOOL isCurrentChannel = [channelKey isEqualToString:self.currentChannelKey];
    if (!isCurrentChannel) {
        return;
    }
    
    // Batch optimization: for incremental updates, delay execution to batch multiple calls
    // Full renders (channel switch) should execute immediately
    BOOL isSwitchingChannel = ![channelKey isEqualToString:self.lastDisplayedChannelKey];
    NSMutableArray<NSAttributedString *> *cachedMessages = self.cachedAttributedMessages[channelKey];
    BOOL hasCache = (cachedMessages != nil && cachedMessages.count > 0);
    if (!isSwitchingChannel && hasCache) {
        // Add to pending set
        if (!self.pendingDisplayChannels) {
            self.pendingDisplayChannels = [[NSMutableSet alloc] init];
        }
        [self.pendingDisplayChannels addObject:channelKey];

        // Merge refresh: if a timer is already scheduled, just enqueue and return.
        if (self.displayTimer) {
            return;
        }

        // Throttle redraw frequency to reduce CPU.
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval minInterval = self.userIsScrolling ? 0.30 : 0.15; // 300ms scrolling, 150ms otherwise
        NSTimeInterval sinceLast = now - self.lastDisplayTimestamp;
        NSUInteger delayMs = (sinceLast < minInterval)
            ? (NSUInteger)((minInterval - sinceLast) * 1000.0)
            : (self.userIsScrolling ? 200 : 80);

        // Create new timer to batch process after delay
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, delayMs * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 0);
        __weak ChatViewController *weakSelf = self;
        dispatch_source_set_event_handler(timer, ^{
            ChatViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            
            // If user is scrolling, defer further
            if (strongSelf.userIsScrolling) {
                dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 0);
                return;
            }
            
            // Process all pending channels
            NSArray<NSString *> *pending = [strongSelf.pendingDisplayChannels allObjects];
            [strongSelf.pendingDisplayChannels removeAllObjects];

            // Execute actual display for the current channel (if still current)
            for (NSString *key in pending) {
                if ([key isEqualToString:strongSelf.currentChannelKey]) {
                    [strongSelf displayMessagesForChannelImmediate:key];
                    strongSelf.lastDisplayTimestamp = [NSDate timeIntervalSinceReferenceDate];
                    break; // Only process current channel
                }
            }

            // If more updates arrived during rendering, schedule another merged refresh.
            if (strongSelf.pendingDisplayChannels.count > 0) {
                dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 0);
                return;
            }

            if (strongSelf.displayTimer) {
                dispatch_source_cancel(strongSelf.displayTimer);
                strongSelf.displayTimer = nil;
            }
        });
        dispatch_resume(timer);
        self.displayTimer = timer;
        return;
    }
    
    // For full renders or immediate needs, execute immediately
    [self displayMessagesForChannelImmediate:channelKey];
}

- (void)displayMessagesForChannelImmediate:(NSString *)channelKey {
    // Performance measurement variables (declared outside macro for compatibility when macro is disabled)
    CHAT_PERF_MEASURE(NSDate *perfStart = [NSDate date];)
    CHAT_PERF_MEASURE(NSDate *tPrepare = [NSDate date];)
    NSTimeInterval prepareMs = 0;
    
    if (!channelKey || channelKey.length == 0 || !self.chatTextView) {
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer) {
        return;
    }

    // Skip UI updates when window is not visible to reduce CPU.
    if (self.view.window && [self.view.window respondsToSelector:@selector(occlusionState)]) {
        NSWindowOcclusionState state = self.view.window.occlusionState;
        if ((state & NSWindowOcclusionStateVisible) == 0) {
            return;
        }
    }

    NSArray<NSString *> *messages = buffer.messages ?: @[];
    NSUInteger messageCount = messages.count;
    
    // Get cached data
    NSMutableArray<NSAttributedString *> *cachedMessages = self.cachedAttributedMessages[channelKey];
    
    // Check if we need full re-render
    BOOL needsFullRender = NO;
    BOOL isSwitchingChannel = ![channelKey isEqualToString:self.lastDisplayedChannelKey];
    
    if (isSwitchingChannel) {
        needsFullRender = YES;
    }
    
    if (!cachedMessages) {
        cachedMessages = [[NSMutableArray alloc] init];
        self.cachedAttributedMessages[channelKey] = cachedMessages;
        needsFullRender = YES;
    }
    
    // If messages were removed (buffer trimmed), need full re-render
    if (cachedMessages.count > messageCount) {
        [cachedMessages removeAllObjects];
        needsFullRender = YES;
    }
    
    // Check if we have a trimmed head marker - this means old message was removed and new one added
    // In this case, even if cachedMessages.count == messageCount, we still need to parse and display the new message
    BOOL hasTrimmedHead = (self.channelKeyWithTrimmedHead && [self.channelKeyWithTrimmedHead isEqualToString:channelKey]);
    
    // No changes needed - but if hasTrimmedHead is set, we must continue even if counts match
    // This is because: buffer had old message removed and new one added (count stays same)
    // Cache had old message removed (count decreased by 1)
    // So: cachedMessages.count should be messageCount - 1, and we need to parse the new last message
    if (!needsFullRender && !hasTrimmedHead && cachedMessages.count == messageCount) {
        return;
    }
    
    CHAT_PERF_MEASURE(prepareMs = -[tPrepare timeIntervalSinceNow] * 1000.0;)
    NSTimeInterval parseMs = 0, buildMs = 0, highlightMs = 0, textStorageMs = 0, scrollMs = 0, deleteMs = 0, layoutMs = 0;
    NSTimeInterval commitPrepareMs = 0, commitCoreMs = 0, commitLayerSyncMs = 0, commitDisplayMs = 0, commitGPUMs = 0, commitRenderMs = 0;
    NSUInteger parsedCount = 0;
    NSUInteger deletedMessageCount = 0;
    BOOL wasTrimmed = NO;
    
    // Variables used in CVPerfLog - must be declared here so code compiles when CHAT_PERF_MEASURE_ENABLED=0
    NSTimeInterval beginEditMs = 0, endEditMs = 0, setAppendMs = 0, noticeMs = 0, appendMs = 0;
    NSUInteger textStorageLengthBefore = 0, textStorageLengthAfter = 0, finalStringLength = 0;
    NSUInteger appendCount = 0, totalAppendedLength = 0;
    
    // Parse only new messages
    // When hasTrimmedHead is true, it means an old message was removed and a new one was added
    // In this case, cachedMessages.count should be messageCount - 1, and we need to parse the last message
    NSUInteger startIndex = cachedMessages.count;
    
    // Special handling for trimmed messages: if trimmed, the last message is always new
    // When hasTrimmedHead is true and startIndex == messageCount, it means cache wasn't properly updated
    // In that case, we need to parse the last message (at index messageCount - 1)
    if (hasTrimmedHead && startIndex == messageCount && messageCount > 0) {
        // Cache wasn't properly updated, force parsing the last message
        startIndex = messageCount - 1;
    }
    
    if (startIndex < messageCount) {
        CHAT_PERF_MEASURE(NSDate *tParse = [NSDate date];)
        NSFont *font = self.chatTextView.font ?: [NSFont fontWithName:@"SF Mono" size:13] ?: [NSFont fontWithName:@"Menlo" size:13];
        NSColor *defaultColor = [NSColor colorWithWhite:0.15 alpha:1.0];
        NSColor *nicknameColor = [NSColor colorWithRed:0.0 green:0.4 blue:0.8 alpha:1.0];
        
        // Detailed parsing metrics
        CHAT_PERF_MEASURE(
            NSTimeInterval ircParseMs = 0;
            NSTimeInterval paraStyleMs = 0;
            NSTimeInterval linkDetectMs = 0;
            NSTimeInterval nicknameFormatMs = 0;
            NSUInteger totalChars = 0;
        )
        
        for (NSUInteger i = startIndex; i < messageCount; i++) {
            NSString *message = messages[i];
            CHAT_PERF_MEASURE(totalChars += message.length;)
            
            // Note: parseAndFormatMessage now has internal timing, but we can't easily access it
            // So we'll measure the total time and log it at a higher level
            NSAttributedString *attrStr = [self parseAndFormatMessage:message font:font defaultColor:defaultColor nicknameColor:nicknameColor];
            [cachedMessages addObject:attrStr];
        }
        CHAT_PERF_MEASURE(parseMs = -[tParse timeIntervalSinceNow] * 1000.0;)
        parsedCount = messageCount - startIndex;
        
        CHAT_PERF_MEASURE(
            if (parsedCount > 0) {
                CVPerfLog(@"[ChatPerf] �?  ├─ parseAndFormat breakdown:");
                CVPerfLog(@"[ChatPerf] �?  �?  ├─ totalChars: %lu (avg: %.1f chars/msg)", (unsigned long)totalChars, (double)totalChars / parsedCount);
                CVPerfLog(@"[ChatPerf] �?  �?  └─ Note: Detailed breakdown (IRC parse, link detect, nickname) measured inside parseAndFormatMessage");
            }
        )
    }
    
    // If user is actively scrolling, skip UI update to reduce CPU.
    if (self.userIsScrolling && !isSwitchingChannel) {
        return;
    }

    // Check if we should auto-scroll (before modifying text)
    BOOL isAtBottom = [self isScrollViewAtBottom];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    BOOL autoScrollSuppressed = (now < self.suppressAutoScrollUntil);
    BOOL shouldScrollToBottom = self.userPinnedToBottom && !self.userIsScrolling && isAtBottom && !autoScrollSuppressed && !self.preserveScrollOnNextRender;

    // If user is not pinned to bottom (reading history), don't update UI to avoid jumps.
    if ((!self.userPinnedToBottom || autoScrollSuppressed) && !isSwitchingChannel) {
        return;
    }
    
    // Build the final string efficiently using a single mutable string
    NSMutableAttributedString *finalString = nil;
    BOOL shouldUpdateTextView = NO;
    
    static const NSUInteger kMaxRenderMessages = 1000; // Render window size
    if (!self.renderStartIndexByChannel) {
        self.renderStartIndexByChannel = [[NSMutableDictionary alloc] init];
    }
    NSUInteger maxStartIndex = messageCount > kMaxRenderMessages ? (messageCount - kMaxRenderMessages) : 0;
    NSNumber *startNum = self.renderStartIndexByChannel[channelKey];
    NSUInteger renderStartIndex = startNum ? startNum.unsignedIntegerValue : maxStartIndex;
    if (renderStartIndex > maxStartIndex) {
        renderStartIndex = maxStartIndex;
    }
    if (self.userPinnedToBottom && isAtBottom && renderStartIndex != maxStartIndex) {
        renderStartIndex = maxStartIndex;
        self.renderStartIndexByChannel[channelKey] = @(renderStartIndex);
        needsFullRender = YES;
    }
    if (!self.renderStartIndexByChannel[channelKey]) {
        self.renderStartIndexByChannel[channelKey] = @(renderStartIndex);
    }

    // Adjust render window if messages were trimmed from head
    BOOL renderWindowAdjusted = NO;
    if (hasTrimmedHead && self.trimmedHeadCount > 0 && renderStartIndex > 0) {
        NSUInteger trim = MIN(renderStartIndex, self.trimmedHeadCount);
        renderStartIndex -= trim;
        self.renderStartIndexByChannel[channelKey] = @(renderStartIndex);
        needsFullRender = YES;
        renderWindowAdjusted = YES;
    }

    // PERFORMANCE OPTIMIZATION: Even if needsFullRender is YES, check if we can use incremental update
    // If we're just adding new messages (no deletion, no channel switch), use incremental update
    // This avoids the expensive setAttributedString operation (40ms+ for large documents)
    BOOL canUseIncrementalUpdate = NO;
    if (needsFullRender && !isSwitchingChannel && !hasTrimmedHead && !renderWindowAdjusted) {
        // Check if textStorage already has content and we're just appending
        NSUInteger currentTextStorageLength = self.chatTextView.textStorage.length;
        if (currentTextStorageLength > 0 && startIndex < messageCount) {
            // We can use incremental update: just append new messages
            canUseIncrementalUpdate = YES;
            CVLog(@"[ChatPerf] Optimization: Using incremental update instead of full render (textStorage: %lu chars, new msgs: %lu)", 
                  (unsigned long)currentTextStorageLength, (unsigned long)(messageCount - startIndex));
        }
    }

    if (needsFullRender && !canUseIncrementalUpdate) {
        // Full render: build all text at once
        // Performance optimization: limit rendering to recent messages if count is very high
        // This prevents CPU 100% when switching to channels with thousands of messages
        NSUInteger renderCount = cachedMessages.count;
        BOOL isTruncated = (renderStartIndex > 0);
        if (cachedMessages.count > kMaxRenderMessages) {
            renderCount = MIN(kMaxRenderMessages, cachedMessages.count - renderStartIndex);
        } else {
            renderStartIndex = 0;
            renderCount = cachedMessages.count;
        }
        
        // Pre-calculate total length for better performance
        NSUInteger totalLength = 0;
        for (NSUInteger i = renderStartIndex; i < cachedMessages.count; i++) {
            totalLength += cachedMessages[i].length + 1; // +1 for newline
        }
        
        CHAT_PERF_MEASURE(NSDate *tBuild = [NSDate date];)
        finalString = [[NSMutableAttributedString alloc] init];
        [finalString beginEditing];
        
        NSUInteger noticeLength = 0; // Used for highlight offset when truncation notice is shown
        CHAT_PERF_MEASURE(NSDate *tNotice = [NSDate date];)
        // Add truncation notice if we're not showing all messages
        if (renderStartIndex > 0) {
            NSColor *noticeColor = [NSColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:1.0];
            NSFont *noticeFont = [NSFont systemFontOfSize:11];
            NSString *noticeText = [NSString stringWithFormat:@"[Showing last %lu of %lu messages]\n", (unsigned long)renderCount, (unsigned long)cachedMessages.count];
            NSAttributedString *notice = [[NSAttributedString alloc] initWithString:noticeText attributes:@{
                NSFontAttributeName: noticeFont,
                NSForegroundColorAttributeName: noticeColor
            }];
            [finalString appendAttributedString:notice];
            noticeLength = notice.length;
        }
        CHAT_PERF_MEASURE(noticeMs = -[tNotice timeIntervalSinceNow] * 1000.0;)
        
        CHAT_PERF_MEASURE(
            NSDate *tAppend = [NSDate date];
            appendCount = 0;
            totalAppendedLength = 0;
        )
        
        // PERFORMANCE OPTIMIZATION: Pre-calculated totalLength helps with memory allocation
        // The system will use this information internally for better performance
        
        NSUInteger renderEnd = MIN(cachedMessages.count, renderStartIndex + renderCount);
        for (NSUInteger i = renderStartIndex; i < renderEnd; i++) {
            [finalString appendAttributedString:cachedMessages[i]];
            [finalString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
            CHAT_PERF_MEASURE(
                appendCount++;
                totalAppendedLength += cachedMessages[i].length + 1;
            )
        }
        CHAT_PERF_MEASURE(
            appendMs = -[tAppend timeIntervalSinceNow] * 1000.0;
            buildMs = -[tBuild timeIntervalSinceNow] * 1000.0;
            if (appendCount > 0) {
                CVPerfLog(@"[ChatPerf] �?  ├─ buildNotice: %.2f ms", noticeMs);
                CVPerfLog(@"[ChatPerf] �?  ├─ appendMessages: %.2f ms (%lu msgs, avg: %.3f ms/msg, %lu chars)", 
                          appendMs, (unsigned long)appendCount, appendMs / appendCount, (unsigned long)totalAppendedLength);
            }
        )
        
        // Apply highlight only if needed (only on rendered messages)
        if (self.highlightedNicknames.count > 0) {
            CHAT_PERF_MEASURE(NSDate *tH = [NSDate date];)
            NSArray *renderedMessages = renderStartIndex > 0 ? [messages subarrayWithRange:NSMakeRange(renderStartIndex, renderCount)] : messages;
            [self applyHighlightToAttributedString:finalString withMessages:renderedMessages startOffset:noticeLength];
            CHAT_PERF_MEASURE(highlightMs = -[tH timeIntervalSinceNow] * 1000.0;)
        }
        
        [finalString endEditing];
        shouldUpdateTextView = YES;
    } else if (startIndex < messageCount || canUseIncrementalUpdate) {
        // Incremental update: build only new messages
        CHAT_PERF_MEASURE(NSDate *tBuild = [NSDate date];)
        finalString = [[NSMutableAttributedString alloc] init];
        [finalString beginEditing];
        
        CHAT_PERF_MEASURE(
            NSDate *tAppend = [NSDate date];
            appendCount = 0;
            totalAppendedLength = 0;
        )
        
        // PERFORMANCE OPTIMIZATION: Pre-allocate capacity for better performance
        // Estimate total length to reduce reallocations during append
        // Note: NSMutableAttributedString doesn't expose mutableString directly,
        // but we can still optimize by pre-calculating the length
        
        for (NSUInteger i = startIndex; i < cachedMessages.count; i++) {
            [finalString appendAttributedString:cachedMessages[i]];
            [finalString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
            CHAT_PERF_MEASURE(
                appendCount++;
                totalAppendedLength += cachedMessages[i].length + 1;
            )
        }
        CHAT_PERF_MEASURE(
            appendMs = -[tAppend timeIntervalSinceNow] * 1000.0;
            buildMs = -[tBuild timeIntervalSinceNow] * 1000.0;
            if (appendCount > 0) {
                CVPerfLog(@"[ChatPerf] �?  ├─ appendMessages: %.2f ms (%lu msgs, avg: %.3f ms/msg, %lu chars)", 
                          appendMs, (unsigned long)appendCount, appendMs / appendCount, (unsigned long)totalAppendedLength);
            }
        )
        
        // Apply highlight only if needed
        if (self.highlightedNicknames.count > 0) {
            CHAT_PERF_MEASURE(NSDate *tH = [NSDate date];)
            NSArray *newMessages = [messages subarrayWithRange:NSMakeRange(startIndex, messageCount - startIndex)];
            [self applyHighlightToAttributedString:finalString withMessages:newMessages startOffset:0];
            CHAT_PERF_MEASURE(highlightMs = -[tH timeIntervalSinceNow] * 1000.0;)
        }
        
        [finalString endEditing];
        shouldUpdateTextView = YES;
    }
    
    // Only update the text view if we have changes
    if (shouldUpdateTextView && finalString) {
        // Disable animations and layout during update for better performance
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        
        // Temporarily disable scroll notifications
        self.chatScrollView.contentView.postsBoundsChangedNotifications = NO;
        
        CHAT_PERF_MEASURE(NSDate *tTex = [NSDate date];)
        CHAT_PERF_MEASURE(NSDate *tBeginEdit = [NSDate date];)
        [self.chatTextView.textStorage beginEditing];
        CHAT_PERF_MEASURE(beginEditMs = -[tBeginEdit timeIntervalSinceNow] * 1000.0;)
        
        CHAT_PERF_MEASURE(
            NSDate *tSetAppend = [NSDate date];
            textStorageLengthBefore = self.chatTextView.textStorage.length;
            finalStringLength = finalString.length;
        )
        if (needsFullRender && !canUseIncrementalUpdate) {
            if (self.channelKeyWithTrimmedHead && [self.channelKeyWithTrimmedHead isEqualToString:channelKey]) {
                self.channelKeyWithTrimmedHead = nil;
            }
            [self.chatTextView.textStorage setAttributedString:finalString];
            CHAT_PERF_MEASURE(
                setAppendMs = -[tSetAppend timeIntervalSinceNow] * 1000.0;
                CVPerfLog(@"[ChatPerf] �?  ├─ beginEditing: %.2f ms", beginEditMs);
                CVPerfLog(@"[ChatPerf] �?  ├─ setAttributedString: %.2f ms (length: %lu -> %lu)", 
                          setAppendMs, (unsigned long)textStorageLengthBefore, (unsigned long)finalStringLength);
            )
        } else if (canUseIncrementalUpdate) {
            // PERFORMANCE OPTIMIZATION: Use incremental update even when needsFullRender is YES
            // This avoids expensive setAttributedString for large documents
            NSUInteger currentLength = self.chatTextView.textStorage.length;
            NSRange appendRange = NSMakeRange(currentLength, 0); // Insert at end
            [self.chatTextView.textStorage replaceCharactersInRange:appendRange withAttributedString:finalString];
            
            CHAT_PERF_MEASURE(
                setAppendMs = -[tSetAppend timeIntervalSinceNow] * 1000.0;
                textStorageLengthAfter = self.chatTextView.textStorage.length;
                CVPerfLog(@"[ChatPerf] �?  ├─ beginEditing: %.2f ms", beginEditMs);
                CVPerfLog(@"[ChatPerf] �?  ├─ replaceCharactersInRange (optimized append): %.2f ms (length: %lu -> %lu, appended: %lu)", 
                          setAppendMs, (unsigned long)textStorageLengthBefore, (unsigned long)textStorageLengthAfter, (unsigned long)finalStringLength);
            )
        } else {
            // When buffer was trimmed from head, cache had elements removed by caller; we must delete message blocks from textStorage before appending the new one
            if (self.channelKeyWithTrimmedHead && [self.channelKeyWithTrimmedHead isEqualToString:channelKey]) {
                NSUInteger deleteCount = self.trimmedHeadCount > 0 ? self.trimmedHeadCount : 1; // Default to 1 if not set
                self.channelKeyWithTrimmedHead = nil;
                self.trimmedHeadCount = 0;
                wasTrimmed = YES;
                
                CHAT_PERF_MEASURE(NSDate *tDelete = [NSDate date];)
                // PERFORMANCE OPTIMIZATION: Batch deletion
                // Delete multiple messages at once (up to deleteCount, typically 100) to reduce layout calculations
                // This is the key optimization: instead of deleting 1 message 100 times (100 layout calculations),
                // we delete 100 messages once (1 layout calculation)
                NSString *s = self.chatTextView.textStorage.string;
                NSUInteger deletedMessages = 0;
                if (s.length > 0) {
                    NSUInteger deleteEndPos = 0;
                    NSUInteger maxSearchChars = MIN(deleteCount * 500, s.length); // Estimate: 500 chars per message
                    
                    // Find the end position of the last message to delete (up to deleteCount messages)
                    while (deletedMessages < deleteCount && deleteEndPos < maxSearchChars) {
                        NSRange searchRange = NSMakeRange(deleteEndPos, MIN(2000, s.length - deleteEndPos));
                        NSRange r = [s rangeOfString:@"\n" options:0 range:searchRange];
                        if (r.location != NSNotFound) {
                            // Found newline, this completes one message
                            deleteEndPos = r.location + 1;
                            deletedMessages++;
                        } else {
                            // No newline found in search range, try wider search
                            if (searchRange.length < s.length - deleteEndPos) {
                                NSRange widerRange = NSMakeRange(deleteEndPos, MIN(10000, s.length - deleteEndPos));
                                NSRange r2 = [s rangeOfString:@"\n" options:0 range:widerRange];
                                if (r2.location != NSNotFound) {
                                    deleteEndPos = r2.location + 1;
                                    deletedMessages++;
                                } else {
                                    // No newline found, delete up to maxSearchChars (shouldn't happen normally)
                                    deleteEndPos = maxSearchChars;
                                    deletedMessages++;
                                    break;
                                }
                            } else {
                                // Reached end of textStorage
                                break;
                            }
                        }
                    }
                    
                    // Delete all found messages at once (single operation = single layout calculation)
                    if (deleteEndPos > 0) {
                        NSRange deleteRange = NSMakeRange(0, deleteEndPos);
                        [self.chatTextView.textStorage deleteCharactersInRange:deleteRange];
                    }
                }
                CHAT_PERF_MEASURE(deleteMs = -[tDelete timeIntervalSinceNow] * 1000.0;)
                deletedMessageCount = deletedMessages; // Store for logging
            }
            
            // PERFORMANCE OPTIMIZATION: Use replaceCharactersInRange instead of appendAttributedString
            // This is more efficient for incremental updates as it avoids some internal overhead
            NSUInteger currentLength = self.chatTextView.textStorage.length;
            NSRange appendRange = NSMakeRange(currentLength, 0); // Insert at end
            [self.chatTextView.textStorage replaceCharactersInRange:appendRange withAttributedString:finalString];
            
            CHAT_PERF_MEASURE(
                setAppendMs = -[tSetAppend timeIntervalSinceNow] * 1000.0;
                textStorageLengthAfter = self.chatTextView.textStorage.length;
                CVPerfLog(@"[ChatPerf] �?  ├─ beginEditing: %.2f ms", beginEditMs);
                CVPerfLog(@"[ChatPerf] �?  ├─ replaceCharactersInRange (append): %.2f ms (length: %lu -> %lu, appended: %lu)", 
                          setAppendMs, (unsigned long)textStorageLengthBefore, (unsigned long)textStorageLengthAfter, (unsigned long)finalStringLength);
            )
        }
        
        CHAT_PERF_MEASURE(NSDate *tEndEdit = [NSDate date];)
        [self.chatTextView.textStorage endEditing];
        CHAT_PERF_MEASURE(
            endEditMs = -[tEndEdit timeIntervalSinceNow] * 1000.0;
            textStorageMs = -[tTex timeIntervalSinceNow] * 1000.0;
            CVPerfLog(@"[ChatPerf] �?  └─ endEditing: %.2f ms", endEditMs);
        )
        
        // PERFORMANCE OPTIMIZATION: Don't force immediate layout calculation
        // Layout will happen automatically when needed, and backgroundLayoutEnabled
        // will handle it in a background thread when possible
        // Only measure layout time if we need to force it (for performance measurement)
        CHAT_PERF_MEASURE(
            NSDate *tLayout = [NSDate date];
            // For incremental updates, don't force layout - let it happen naturally
            // For full renders, we may need to ensure layout is ready
            if (needsFullRender) {
                NSLayoutManager *layoutManager = self.chatTextView.layoutManager;
                if (layoutManager && self.chatTextView.textContainer) {
                    // Only access layout info if needed, don't force complete layout
                    // The background layout manager will handle this efficiently
                    NSRange glyphRange = [layoutManager glyphRangeForTextContainer:self.chatTextView.textContainer];
                    (void)glyphRange;
                }
            }
            layoutMs = -[tLayout timeIntervalSinceNow] * 1000.0;
        )
        
        // PERFORMANCE OPTIMIZATION: Reduce unnecessary operations for incremental updates
        // For incremental updates, avoid accessing layer properties which can trigger immediate rendering work
        BOOL isIncrementalUpdate = (!needsFullRender && !wasTrimmed) || canUseIncrementalUpdate;
        
        // Measure CATransaction commit time (subdivided)
        // PERFORMANCE OPTIMIZATION: For incremental updates, minimize rendering overhead
        CHAT_PERF_MEASURE(NSDate *tCommitPrep = [NSDate date];)
        
        // PERFORMANCE OPTIMIZATION: For incremental updates, don't explicitly trigger display
        // NSTextStorage changes automatically notify the layout manager, which will update the view
        // We only need to commit the transaction, but don't force immediate rendering
        CALayer *textLayer = nil;
        if (isIncrementalUpdate) {
            // For incremental updates, don't call setNeedsDisplay - let the system handle it naturally
            // The text storage change will automatically trigger necessary updates
            // This reduces the rendering overhead significantly
        } else {
            // For full renders or trimmed updates, explicitly mark as needing display
            [self.chatTextView setNeedsDisplay:YES];
            // Access layer to ensure it's ready for full renders
            textLayer = self.chatTextView.layer;
            (void)textLayer;
        }
        CHAT_PERF_MEASURE(commitPrepareMs = -[tCommitPrep timeIntervalSinceNow] * 1000.0;)
        
        // Core commit operation - this triggers the actual rendering pipeline
        // The commit operation itself is atomic and includes:
        // 1. Layer tree synchronization
        // 2. Display method calls (drawing)
        // 3. Render tree construction
        // 4. GPU submission
        
        // PERFORMANCE OPTIMIZATION: For incremental updates, the transaction commit will be lighter
        // because we didn't explicitly call setNeedsDisplay, so the system can optimize the rendering
        CHAT_PERF_MEASURE(NSDate *tCommitCore = [NSDate date];)
        [CATransaction commit];
        CHAT_PERF_MEASURE(commitCoreMs = -[tCommitCore timeIntervalSinceNow] * 1000.0;)
        
        // Note: The commit operation internally performs:
        // - Layer synchronization (happens during commit)
        // - View/layer drawing (happens during commit via display methods)
        // - Render tree building (happens during commit)
        // - GPU submission (happens during commit)
        // All of these are measured together as commitCoreMs
        
        // Set sub-components to 0 since they're all part of the atomic commit
        CHAT_PERF_MEASURE(commitLayerSyncMs = 0; commitDisplayMs = 0; commitGPUMs = 0;)
        
        // Post-commit: check if any synchronous rendering work completed
        // This measures any deferred rendering that happens immediately after commit
        // PERFORMANCE OPTIMIZATION: Skip layer bounds access for incremental updates
        CHAT_PERF_MEASURE(NSDate *tCommitRender = [NSDate date];)
        if (!isIncrementalUpdate && textLayer) {
            // Only access layer properties for full renders to detect deferred rendering
            CGRect bounds = textLayer.bounds;
            (void)bounds;
        }
        CHAT_PERF_MEASURE(commitRenderMs = -[tCommitRender timeIntervalSinceNow] * 1000.0;)
        
        // Restore scroll position if requested (e.g., highlight without jumping)
        if (self.preserveScrollOnNextRender && self.chatScrollView && self.chatScrollView.contentView) {
            [self.chatScrollView.contentView scrollToPoint:self.preservedScrollOrigin];
            [self.chatScrollView reflectScrolledClipView:self.chatScrollView.contentView];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.preserveScrollOnNextRender && self.chatScrollView && self.chatScrollView.contentView) {
                    [self.chatScrollView.contentView scrollToPoint:self.preservedScrollOrigin];
                    [self.chatScrollView reflectScrolledClipView:self.chatScrollView.contentView];
                    self.preserveScrollOnNextRender = NO;
                }
            });
        }

        // Re-enable scroll notifications after a short delay
        dispatch_async(dispatch_get_main_queue(), ^{
            self.chatScrollView.contentView.postsBoundsChangedNotifications = YES;
        });
    }
    
    // Update tracking
    self.lastRenderedMessageCount[channelKey] = @(messageCount);
    self.lastDisplayedChannelKey = channelKey;
    self.lastDisplayTimestamp = [NSDate timeIntervalSinceReferenceDate];
    
    // Scroll to bottom if needed
    if (shouldScrollToBottom) {
        CHAT_PERF_MEASURE(NSDate *tScroll = [NSDate date];)
        self.chatScrollView.contentView.postsBoundsChangedNotifications = NO;
        [self.chatTextView scrollToEndOfDocument:nil];
        CHAT_PERF_MEASURE(scrollMs = -[tScroll timeIntervalSinceNow] * 1000.0;)
        dispatch_async(dispatch_get_main_queue(), ^{
            self.chatScrollView.contentView.postsBoundsChangedNotifications = YES;
        });
    }
    
    // Calculate performance metrics (only if measurement is enabled)
    // Variables declared outside macro for compatibility
    NSTimeInterval totalMs = 0;
    NSTimeInterval commitMs = 0;
    NSTimeInterval processingTime = 0;
    NSTimeInterval otherTime = 0;
    CHAT_PERF_MEASURE(
        totalMs = -[perfStart timeIntervalSinceNow] * 1000.0;
        commitMs = commitPrepareMs + commitCoreMs + commitRenderMs;
        processingTime = prepareMs + parseMs + buildMs + highlightMs + deleteMs + textStorageMs + layoutMs + commitMs;
        otherTime = totalMs - processingTime - scrollMs;
    )
    
    // Detailed performance logging (controlled by CHAT_PERF_DEBUG_LOG)
    CVPerfLog(@"[ChatPerf] =====================================");
    CVPerfLog(@"[ChatPerf] ===== displayMessagesForChannel =====");
    CVPerfLog(@"[ChatPerf] Channel: %@", channelKey);
    CVPerfLog(@"[ChatPerf] Total messages: %lu, Cached: %lu, New: %lu", 
              (unsigned long)messageCount, 
              (unsigned long)startIndex, 
              (unsigned long)parsedCount);
    CVPerfLog(@"[ChatPerf] Render type: %@ (switching: %@)", 
              needsFullRender ? @"FULL" : @"INCREMENTAL",
              isSwitchingChannel ? @"YES" : @"NO");
    CHAT_PERF_MEASURE(
        if (finalString) {
            CVPerfLog(@"[ChatPerf] Final string length: %lu chars", (unsigned long)finalString.length);
        }
        if (self.chatTextView.textStorage) {
            CVPerfLog(@"[ChatPerf] TextStorage length before update: %lu chars", (unsigned long)self.chatTextView.textStorage.length);
        }
    )
    
    if (needsFullRender && cachedMessages.count > kMaxRenderMessages) {
        NSUInteger renderStartIndex = cachedMessages.count > kMaxRenderMessages ? cachedMessages.count - kMaxRenderMessages : 0;
        CVPerfLog(@"[ChatPerf] Render range: [%lu, %lu) (truncated from %lu)", 
                  (unsigned long)renderStartIndex, 
                  (unsigned long)cachedMessages.count,
                  (unsigned long)cachedMessages.count);
    }
    
    if (wasTrimmed) {
        CVPerfLog(@"[ChatPerf] Old messages trimmed: YES (%lu msgs deleted in batch)", (unsigned long)deletedMessageCount);
    }
    
    // Detailed timing breakdown (only log if measurement is enabled)
    CHAT_PERF_MEASURE(
        // Detailed timing breakdown
        if (prepareMs > 0) {
            CVPerfLog(@"[ChatPerf] ├─ prepare: %.2f ms", prepareMs);
        }
        if (parseMs > 0) {
            double avgParseMs = parsedCount > 0 ? parseMs / parsedCount : 0;
            CVPerfLog(@"[ChatPerf] ├─ parseAndFormat: %.2f ms (%lu msgs, avg: %.3f ms/msg)", 
                      parseMs, (unsigned long)parsedCount, avgParseMs);
        }
        if (buildMs > 0) {
            CVPerfLog(@"[ChatPerf] ├─ buildFinalString: %.2f ms", buildMs);
        }
        if (highlightMs > 0) {
            CVPerfLog(@"[ChatPerf] ├─ applyHighlight: %.2f ms", highlightMs);
        }
        if (deleteMs > 0) {
            CVPerfLog(@"[ChatPerf] ├─ deleteOldMessages: %.2f ms (%lu msgs)", deleteMs, (unsigned long)deletedMessageCount);
        }
        if (textStorageMs > 0) {
            CVPerfLog(@"[ChatPerf] ├─ textStorageUpdate: %.2f ms", textStorageMs);
            // Detailed breakdown (beginEditing, setAttributedString/appendAttributedString, endEditing) logged above
        }
        if (layoutMs > 0) {
            CHAT_PERF_MEASURE(
                NSLayoutManager *layoutMgr = self.chatTextView.layoutManager;
                NSTextContainer *container = self.chatTextView.textContainer;
                if (layoutMgr && container) {
                    NSRange glyphRange = [layoutMgr glyphRangeForTextContainer:container];
                    CVPerfLog(@"[ChatPerf] ├─ layoutCalculation: %.2f ms (glyphRange: %lu-%lu)", 
                              layoutMs, (unsigned long)glyphRange.location, (unsigned long)NSMaxRange(glyphRange));
                } else {
                    CVPerfLog(@"[ChatPerf] ├─ layoutCalculation: %.2f ms", layoutMs);
                }
            )
        }
        if (commitMs > 0) {
            CVPerfLog(@"[ChatPerf] ├─ CATransactionCommit: %.2f ms", commitMs);
            if (commitPrepareMs > 0 || commitCoreMs > 0 || commitRenderMs > 0) {
                CVPerfLog(@"[ChatPerf] �?  ├─ commitPrepare: %.2f ms (setNeedsDisplay + layer access)", commitPrepareMs);
                if (commitCoreMs > 0) {
                    CVPerfLog(@"[ChatPerf] �?  ├─ commitCore: %.2f ms", commitCoreMs);
                    CVPerfLog(@"[ChatPerf] �?  �?  └─ (includes: layerSync, display, render, gpuSubmit)");
                    CHAT_PERF_MEASURE(
                        if (commitCoreMs > 5.0) {
                            CVPerfLog(@"[ChatPerf] �?  �?  ⚠️  commitCore > 5ms - may indicate rendering bottleneck");
                        }
                    )
                }
                CVPerfLog(@"[ChatPerf] �?  └─ commitRender: %.2f ms (post-commit checks)", commitRenderMs);
            }
        }
        if (scrollMs > 0) {
            CVPerfLog(@"[ChatPerf] ├─ scroll: %.2f ms", scrollMs);
        }
        
        CVPerfLog(@"[ChatPerf] └─ TOTAL: %.2f ms", totalMs);
        
        // Percentage breakdown
        if (totalMs > 0 && processingTime > 0) {
            NSMutableString *breakdown = [NSMutableString stringWithString:@"    Breakdown: "];
            BOOL hasAny = NO;
            
            if (prepareMs > 0) {
                [breakdown appendFormat:@"prepare=%.1f%%", (prepareMs / totalMs) * 100];
                hasAny = YES;
            }
            if (parseMs > 0) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"parse=%.1f%%", (parseMs / totalMs) * 100];
                hasAny = YES;
            }
            if (buildMs > 0) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"build=%.1f%%", (buildMs / totalMs) * 100];
                hasAny = YES;
            }
            if (highlightMs > 0) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"highlight=%.1f%%", (highlightMs / totalMs) * 100];
                hasAny = YES;
            }
            if (deleteMs > 0) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"delete=%.1f%%", (deleteMs / totalMs) * 100];
                hasAny = YES;
            }
            if (textStorageMs > 0) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"textStorage=%.1f%%", (textStorageMs / totalMs) * 100];
                hasAny = YES;
            }
            if (layoutMs > 0) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"layout=%.1f%%", (layoutMs / totalMs) * 100];
                hasAny = YES;
            }
            if (commitMs > 0) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"commit=%.1f%%", (commitMs / totalMs) * 100];
                if (commitPrepareMs > 0 || commitCoreMs > 0 || commitRenderMs > 0) {
                    [breakdown appendFormat:@"(prep=%.1f%%,core=%.1f%%,render=%.1f%%)", 
                     (commitPrepareMs / totalMs) * 100,
                     (commitCoreMs / totalMs) * 100,
                     (commitRenderMs / totalMs) * 100];
                }
                hasAny = YES;
            }
            if (scrollMs > 0) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"scroll=%.1f%%", (scrollMs / totalMs) * 100];
                hasAny = YES;
            }
            if (otherTime > 0.1) {
                if (hasAny) [breakdown appendString:@", "];
                [breakdown appendFormat:@"other=%.1f%%", (otherTime / totalMs) * 100];
            }
            
            if (hasAny || otherTime > 0.1) {
                CVPerfLog(@"[ChatPerf] %@", breakdown);
            }
        }
        
        CVPerfLog(@"[ChatPerf] =====================================");
    )
    
    // Detailed timing breakdown
    if (prepareMs > 0) {
        CVPerfLog(@"[ChatPerf] ├─ prepare: %.2f ms", prepareMs);
    }
    if (parseMs > 0) {
        double avgParseMs = parsedCount > 0 ? parseMs / parsedCount : 0;
        CVPerfLog(@"[ChatPerf] ├─ parseAndFormat: %.2f ms (%lu msgs, avg: %.3f ms/msg)", 
                  parseMs, (unsigned long)parsedCount, avgParseMs);
    }
    if (buildMs > 0) {
        CVPerfLog(@"[ChatPerf] ├─ buildFinalString: %.2f ms", buildMs);
    }
    if (highlightMs > 0) {
        CVPerfLog(@"[ChatPerf] ├─ applyHighlight: %.2f ms", highlightMs);
    }
    if (deleteMs > 0) {
        CVPerfLog(@"[ChatPerf] ├─ deleteOldMessages: %.2f ms (%lu msgs)", deleteMs, (unsigned long)deletedMessageCount);
    }
    if (textStorageMs > 0) {
        CVPerfLog(@"[ChatPerf] ├─ textStorageUpdate: %.2f ms", textStorageMs);
    }
    if (layoutMs > 0) {
        CVPerfLog(@"[ChatPerf] ├─ layoutCalculation: %.2f ms", layoutMs);
    }
    if (commitMs > 0) {
        CVPerfLog(@"[ChatPerf] ├─ CATransactionCommit: %.2f ms", commitMs);
        if (commitPrepareMs > 0 || commitCoreMs > 0 || commitRenderMs > 0) {
            CVPerfLog(@"[ChatPerf] �?  ├─ commitPrepare: %.2f ms", commitPrepareMs);
            if (commitCoreMs > 0) {
                CVPerfLog(@"[ChatPerf] �?  ├─ commitCore: %.2f ms", commitCoreMs);
                CVPerfLog(@"[ChatPerf] �?  �?  └─ (includes: layerSync, display, render, gpuSubmit)");
            }
            CVPerfLog(@"[ChatPerf] �?  └─ commitRender: %.2f ms", commitRenderMs);
        }
    }
    if (scrollMs > 0) {
        CVPerfLog(@"[ChatPerf] ├─ scroll: %.2f ms", scrollMs);
    }
    
    CVPerfLog(@"[ChatPerf] └─ TOTAL: %.2f ms", totalMs);
    
    // Percentage breakdown
    if (totalMs > 0 && processingTime > 0) {
        NSMutableString *breakdown = [NSMutableString stringWithString:@"    Breakdown: "];
        BOOL hasAny = NO;
        
        if (prepareMs > 0) {
            [breakdown appendFormat:@"prepare=%.1f%%", (prepareMs / totalMs) * 100];
            hasAny = YES;
        }
        if (parseMs > 0) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"parse=%.1f%%", (parseMs / totalMs) * 100];
            hasAny = YES;
        }
        if (buildMs > 0) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"build=%.1f%%", (buildMs / totalMs) * 100];
            hasAny = YES;
        }
        if (highlightMs > 0) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"highlight=%.1f%%", (highlightMs / totalMs) * 100];
            hasAny = YES;
        }
        if (deleteMs > 0) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"delete=%.1f%%", (deleteMs / totalMs) * 100];
            hasAny = YES;
        }
        if (textStorageMs > 0) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"textStorage=%.1f%%", (textStorageMs / totalMs) * 100];
            hasAny = YES;
        }
        if (layoutMs > 0) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"layout=%.1f%%", (layoutMs / totalMs) * 100];
            hasAny = YES;
        }
        if (commitMs > 0) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"commit=%.1f%%", (commitMs / totalMs) * 100];
            if (commitPrepareMs > 0 || commitCoreMs > 0 || commitRenderMs > 0) {
                [breakdown appendFormat:@"(prep=%.1f%%,core=%.1f%%,render=%.1f%%)", 
                 (commitPrepareMs / totalMs) * 100,
                 (commitCoreMs / totalMs) * 100,
                 (commitRenderMs / totalMs) * 100];
            }
            hasAny = YES;
        }
        if (scrollMs > 0) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"scroll=%.1f%%", (scrollMs / totalMs) * 100];
            hasAny = YES;
        }
        if (otherTime > 0.1) {
            if (hasAny) [breakdown appendString:@", "];
            [breakdown appendFormat:@"other=%.1f%%", (otherTime / totalMs) * 100];
        }
        
        if (hasAny || otherTime > 0.1) {
            CVPerfLog(@"[ChatPerf] %@", breakdown);
        }
    }
    
    CVPerfLog(@"[ChatPerf] =====================================");
}

// Parse and format a single message (for caching) - includes link detection
- (NSAttributedString *)parseAndFormatMessage:(NSString *)message font:(NSFont *)font defaultColor:(NSColor *)defaultColor nicknameColor:(NSColor *)nicknameColor {
    NSMutableAttributedString *attrStr = [[self parseIRCFormattingString:message font:font defaultColor:defaultColor] mutableCopy];
    
    // Apply paragraph spacing between messages
    CGFloat spacing = self.messageLineSpacing;
    if (spacing < 0) spacing = 0;
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.paragraphSpacing = spacing;
    paragraphStyle.paragraphSpacingBefore = 0;
    paragraphStyle.lineSpacing = 0;
    [attrStr addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, attrStr.length)];
    
    // Make the nickname clickable
    NSString *extractedNick = [self extractNicknameFromMessage:message];
    if (extractedNick.length > 0) {
        NSRange nickRange = [self findNicknameRange:extractedNick inMessage:message];
        if (nickRange.location != NSNotFound && nickRange.location + nickRange.length <= attrStr.length) {
            [attrStr addAttribute:NSForegroundColorAttributeName value:nicknameColor range:nickRange];
            [attrStr addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:nickRange];
            [attrStr addAttribute:ChatNicknameAttributeKey value:extractedNick range:nickRange];
            [attrStr addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:nickRange];
        }
    }
    
    // Apply link detection to this single message (cached with links)
    [self applyLinkDetectionToAttributedString:attrStr];
    
    return attrStr;
}

// Apply link detection to attributed string
- (void)applyLinkDetectionToAttributedString:(NSMutableAttributedString *)attrString {
    if (!attrString || attrString.length == 0) return;
    
    // Quick check: skip link detection if message doesn't contain common URL patterns
    NSString *plainText = attrString.string;
    BOOL mightHaveURL = [plainText containsString:@"http://"] || 
                        [plainText containsString:@"https://"] ||
                        [plainText containsString:@"www."] ||
                        [plainText containsString:@"ftp://"] ||
                        [plainText containsString:@"://"] ||
                        [plainText rangeOfString:@"[a-zA-Z0-9]+\\.[a-zA-Z]{2,}" options:NSRegularExpressionSearch].location != NSNotFound;
    
    if (!mightHaveURL) {
        return; // Skip expensive NSDataDetector for messages without URL patterns
    }
    
    static NSDataDetector *detector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    });
    
    if (detector) {
        NSArray<NSTextCheckingResult *> *matches = [detector matchesInString:plainText options:0 range:NSMakeRange(0, plainText.length)];
        for (NSTextCheckingResult *match in matches) {
            if (match.URL) {
                [attrString addAttribute:NSLinkAttributeName value:match.URL range:match.range];
            }
        }
    }
}

// Apply highlight styling if any nicknames are highlighted
- (void)applyHighlightToAttributedString:(NSMutableAttributedString *)attrString withMessages:(NSArray<NSString *> *)messages startOffset:(NSUInteger)startOffset {
    NSSet<NSString *> *highlightedNicks = self.highlightedNicknames;
    if (highlightedNicks.count == 0) return;
    
    NSColor *dimmedColor = [NSColor colorWithWhite:0.65 alpha:1.0];
    NSColor *highlightBackgroundColor = [NSColor colorWithRed:1.0 green:0.95 blue:0.6 alpha:1.0];
    NSColor *highlightTextColor = [NSColor colorWithWhite:0.10 alpha:1.0];
    NSColor *highlightNicknameColor = [NSColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0];
    
    NSString *fullText = attrString.string;
    NSUInteger currentLocation = startOffset;
    for (NSString *message in messages) {
        if (currentLocation >= fullText.length) {
            break;
        }
        // Find end of this rendered line in the attributed string (newline boundary)
        NSRange searchRange = NSMakeRange(currentLocation, fullText.length - currentLocation);
        NSRange newlineRange = [fullText rangeOfString:@"\n" options:0 range:searchRange];
        NSUInteger lineEnd = (newlineRange.location != NSNotFound) ? newlineRange.location : fullText.length;
        if (lineEnd < currentLocation) {
            break;
        }
        NSRange messageRange = NSMakeRange(currentLocation, lineEnd - currentLocation);
        if (messageRange.length == 0) {
            currentLocation = (newlineRange.location != NSNotFound) ? (lineEnd + 1) : lineEnd;
            continue;
        }
        
        NSString *extractedNick = [self extractNicknameFromMessage:message];
        if (extractedNick) {
            if ([self isNicknameHighlighted:extractedNick]) {
                // Highlight this message
                [attrString addAttribute:NSForegroundColorAttributeName value:highlightTextColor range:messageRange];
                [attrString addAttribute:NSBackgroundColorAttributeName value:highlightBackgroundColor range:messageRange];
                
                // Update nickname color by searching within rendered line text
                NSRange nickInLine = [fullText rangeOfString:extractedNick options:0 range:messageRange];
                if (nickInLine.location != NSNotFound) {
                    [attrString addAttribute:NSForegroundColorAttributeName value:highlightNicknameColor range:nickInLine];
                }
            } else {
                // Dim this message
                [attrString addAttribute:NSForegroundColorAttributeName value:dimmedColor range:messageRange];
            }
        }
        
        currentLocation = (newlineRange.location != NSNotFound) ? (lineEnd + 1) : lineEnd;
    }
}

// Check if scroll view is at bottom
- (BOOL)isScrollViewAtBottom {
    if (!self.chatScrollView) {
        return YES;
    }
    
    NSClipView *clipView = self.chatScrollView.contentView;
    NSView *documentView = self.chatScrollView.documentView;
    
    if (!clipView || !documentView) {
        return YES;
    }
    
    CGFloat contentHeight = documentView.frame.size.height;
    CGFloat visibleHeight = clipView.bounds.size.height;
    CGFloat scrollPosition = clipView.bounds.origin.y;
    
    // Consider "at bottom" if within 20 pixels of the bottom
    CGFloat threshold = 20.0;
    CGFloat maxScroll = contentHeight - visibleHeight;
    
    return (maxScroll <= 0) || (scrollPosition >= maxScroll - threshold);
}

// Check if scroll view is at top
- (BOOL)isScrollViewAtTop {
    if (!self.chatScrollView) {
        return YES;
    }
    
    NSClipView *clipView = self.chatScrollView.contentView;
    NSView *documentView = self.chatScrollView.documentView;
    
    if (!clipView || !documentView) {
        return YES;
    }
    
    CGFloat scrollPosition = clipView.bounds.origin.y;
    return scrollPosition <= 5.0;
}

// Called when scroll view bounds change (user scrolling only)
- (void)chatScrollViewBoundsDidChange:(NSNotification *)notification {
    // Only update when the notification is from our scroll view's content view
    if (notification.object != self.chatScrollView.contentView) {
        return;
    }
    
    // Simple check - just update the flag based on scroll position
    // This is very lightweight and shouldn't cause CPU issues
    BOOL atBottom = [self isScrollViewAtBottom];
    self.userIsScrolling = !atBottom;
    self.userPinnedToBottom = atBottom;
    self.lastScrollEventTime = [NSDate timeIntervalSinceReferenceDate];

    // If user is at top, load older messages into render window.
    if ([self isScrollViewAtTop] && self.currentChannelKey) {
        if (!self.renderStartIndexByChannel) {
            self.renderStartIndexByChannel = [[NSMutableDictionary alloc] init];
        }
        NSNumber *startNum = self.renderStartIndexByChannel[self.currentChannelKey];
        NSUInteger startIndex = startNum ? startNum.unsignedIntegerValue : 0;
        if (startIndex > 0) {
            static const NSUInteger kPageSize = 200;
            NSUInteger newStart = startIndex > kPageSize ? (startIndex - kPageSize) : 0;
            if (newStart != startIndex) {
                self.renderStartIndexByChannel[self.currentChannelKey] = @(newStart);
                self.lastDisplayedChannelKey = nil; // force full render
                [self displayMessagesForChannel:self.currentChannelKey];
                return;
            }
        }
    }

    // If user stopped scrolling and is pinned to bottom, refresh current channel once.
    if (!self.userIsScrolling && self.userPinnedToBottom && self.currentChannelKey) {
        [self displayMessagesForChannel:self.currentChannelKey];
    }
}

// Check if log scroll view is at bottom
- (BOOL)isLogScrollViewAtBottom {
    if (!self.logScrollView) {
        return YES;
    }
    
    NSClipView *clipView = self.logScrollView.contentView;
    NSView *documentView = self.logScrollView.documentView;
    if (!clipView || !documentView) {
        return YES;
    }
    
    CGFloat contentHeight = documentView.frame.size.height;
    CGFloat visibleHeight = clipView.bounds.size.height;
    CGFloat scrollPosition = clipView.bounds.origin.y;
    CGFloat threshold = 20.0;
    CGFloat maxScroll = contentHeight - visibleHeight;
    
    return (maxScroll <= 0) || (scrollPosition >= maxScroll - threshold);
}

// Called when log scroll view bounds change (user scrolling only)
- (void)logScrollViewBoundsDidChange:(NSNotification *)notification {
    if (notification.object != self.logScrollView.contentView) {
        return;
    }
    
    BOOL atBottom = [self isLogScrollViewAtBottom];
    self.logUserIsScrolling = !atBottom;
    self.logUserPinnedToBottom = atBottom;
    self.logLastScrollEventTime = [NSDate timeIntervalSinceReferenceDate];
}

#pragma mark - Nickname Extraction Helpers

// Extract nickname from message format: [HH:mm:ss] <nick> message or [HH:mm:ss] * nick action or [HH:mm:ss] *** nick ...
- (NSString *)extractNicknameFromMessage:(NSString *)message {
    if (!message || message.length == 0) {
        return nil;
    }
    
    // Pattern 1: [HH:mm:ss] <nick> message
    NSRange angleBracketStart = [message rangeOfString:@"<"];
    NSRange angleBracketEnd = [message rangeOfString:@">"];
    if (angleBracketStart.location != NSNotFound && angleBracketEnd.location != NSNotFound &&
        angleBracketEnd.location > angleBracketStart.location) {
        NSRange nickRange = NSMakeRange(angleBracketStart.location + 1, 
                                        angleBracketEnd.location - angleBracketStart.location - 1);
        return [message substringWithRange:nickRange];
    }
    
    // Pattern 2: [HH:mm:ss] * nick action (ACTION message)
    NSRegularExpression *actionRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[\\d{2}:\\d{2}:\\d{2}\\] \\* (\\S+) "
                                                                                 options:0 error:nil];
    if (actionRegex) {
        NSTextCheckingResult *match = [actionRegex firstMatchInString:message options:0 range:NSMakeRange(0, message.length)];
        if (match && match.numberOfRanges > 1) {
            return [message substringWithRange:[match rangeAtIndex:1]];
        }
    }
    
    return nil;
}

// Find the range of nickname in the message string
- (NSRange)findNicknameRange:(NSString *)nickname inMessage:(NSString *)message {
    if (!nickname || !message) {
        return NSMakeRange(NSNotFound, 0);
    }
    
    // Pattern 1: <nick>
    NSString *bracketedNick = [NSString stringWithFormat:@"<%@>", nickname];
    NSRange bracketRange = [message rangeOfString:bracketedNick];
    if (bracketRange.location != NSNotFound) {
        // Return the range of just the nickname (without < and >)
        return NSMakeRange(bracketRange.location + 1, nickname.length);
    }
    
    // Pattern 2: * nick (for ACTION messages)
    NSString *actionPattern = [NSString stringWithFormat:@"* %@ ", nickname];
    NSRange actionRange = [message rangeOfString:actionPattern];
    if (actionRange.location != NSNotFound) {
        // Return the range of just the nickname (after "* ")
        return NSMakeRange(actionRange.location + 2, nickname.length);
    }
    
    return NSMakeRange(NSNotFound, 0);
}

#pragma mark - Nickname Highlight

- (void)toggleHighlightForNickname:(NSString *)nickname {
    if (!nickname || nickname.length == 0) {
        return;
    }
    // Suppress auto-scroll briefly so highlight doesn't jump the view
    self.suppressAutoScrollUntil = [NSDate timeIntervalSinceReferenceDate] + 0.6;
    if (self.chatScrollView && self.chatScrollView.contentView) {
        self.preservedScrollOrigin = self.chatScrollView.contentView.bounds.origin;
        self.preserveScrollOnNextRender = YES;
    }
    
    // Check if this nickname is already highlighted (case-insensitive)
    NSString *existingNick = nil;
    for (NSString *highlightedNick in self.highlightedNicknames) {
        if ([highlightedNick caseInsensitiveCompare:nickname] == NSOrderedSame) {
            existingNick = highlightedNick;
            break;
        }
    }
    
    if (existingNick) {
        // Remove from highlighted set
        [self.highlightedNicknames removeObject:existingNick];
    } else {
        // Add to highlighted set
        [self.highlightedNicknames addObject:nickname];
    }
    
    // Force full re-render by clearing the last displayed channel key
    // This ensures highlights are applied correctly
    if (self.currentChannelKey) {
        self.lastDisplayedChannelKey = nil;
        [self displayMessagesForChannel:self.currentChannelKey];
    }
}

- (void)clearAllNicknameHighlights {
    if (self.highlightedNicknames.count > 0) {
        [self.highlightedNicknames removeAllObjects];

        // Suppress auto-scroll briefly so highlight doesn't jump the view
        self.suppressAutoScrollUntil = [NSDate timeIntervalSinceReferenceDate] + 0.6;
        if (self.chatScrollView && self.chatScrollView.contentView) {
            self.preservedScrollOrigin = self.chatScrollView.contentView.bounds.origin;
            self.preserveScrollOnNextRender = YES;
        }
        
        // Force full re-render by clearing the last displayed channel key
        if (self.currentChannelKey) {
            self.lastDisplayedChannelKey = nil;
            [self displayMessagesForChannel:self.currentChannelKey];
        }
    }
}

- (BOOL)isNicknameHighlighted:(NSString *)nickname {
    if (!nickname || nickname.length == 0) {
        return NO;
    }
    
    for (NSString *highlightedNick in self.highlightedNicknames) {
        if ([highlightedNick caseInsensitiveCompare:nickname] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

- (void)openPrivateChatWithNickname:(NSString *)nickname {
    if (!nickname || nickname.length == 0) {
        return;
    }
    
    // Get current server
    NSString *server = self.currentServer;
    if (!server || server.length == 0) {
        ChannelBuffer *buffer = self.currentChannelKey ? self.channels[self.currentChannelKey] : nil;
        server = buffer.server;
    }
    
    if (!server || server.length == 0) {
        return;
    }
    
    // Create private chat channel
    [self addChannel:server channel:nickname isPrivate:YES];
    NSString *channelKey = [self makeChannelKey:server channel:nickname];
    [self switchToChannel:channelKey];
}

- (NSString *)extractNicknameAtPoint:(NSPoint)point inTextView:(NSTextView *)textView {
    if (!textView || !textView.textStorage || textView.textStorage.length == 0) {
        return nil;
    }
    
    // Convert point to text container coordinates
    NSPoint textContainerPoint = point;
    textContainerPoint.x -= textView.textContainerInset.width;
    textContainerPoint.y -= textView.textContainerInset.height;
    
    // Get the character index at the point
    NSUInteger charIndex = [textView.layoutManager characterIndexForPoint:textContainerPoint
                                                         inTextContainer:textView.textContainer
                                fractionOfDistanceBetweenInsertionPoints:NULL];
    
    NSUInteger textLength = textView.textStorage.length;
    if (charIndex >= textLength) {
        return nil;
    }
    
    // Check if this character has our nickname attribute
    // Use a small local range instead of the entire text to avoid performance issues
    id nicknameValue = [textView.textStorage attribute:ChatNicknameAttributeKey 
                                               atIndex:charIndex 
                                        effectiveRange:NULL];
    
    if (nicknameValue && [nicknameValue isKindOfClass:[NSString class]]) {
        return (NSString *)nicknameValue;
    }
    
    return nil;
}

#pragma mark - System Messages

- (void)addSystemMessage:(NSString *)message {
    NSString *server = self.currentServer ?: (self.serverOrder.count > 0 ? self.serverOrder[0] : @"");
    [self addSystemMessage:message forServer:server];
}

- (void)addSystemMessage:(NSString *)message forServer:(NSString *)server {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self addSystemMessage:message forServer:server];
        });
        return;
    }
    
    if (!message || message.length == 0) {
        return;
    }
    
    // System messages always go to the server status window (server address as channel name)
    // This keeps system messages separate from channel chat messages
    NSString *targetChannelKey = nil;
    
    if (server.length > 0) {
        // Use server address as the status channel name (e.g., "irc.dal.net:6667")
        NSString *statusChannel = server;
        targetChannelKey = [self makeChannelKey:server channel:statusChannel];
        
        // Create server status buffer if it doesn't exist (without adding to channel tree)
        ChannelBuffer *existingBuffer = self.channels[targetChannelKey];
        if (!existingBuffer) {
            // Create buffer directly without calling addChannel to avoid adding to channel list
            ChannelBuffer *buffer = [[ChannelBuffer alloc] initWithName:server server:server isPrivate:NO];
            self.channels[targetChannelKey] = buffer;
        }
    }
    
    // Fallback: if no server specified, use the first available channel
    if (!targetChannelKey) {
        for (NSString *serverKey in self.serverOrder) {
            NSArray<NSString *> *serverChannels = self.serverChannelOrder[serverKey];
            if (serverChannels && serverChannels.count > 0) {
                targetChannelKey = serverChannels[0];
                break;
            }
        }
    }
    
    if (targetChannelKey) {
        ChannelBuffer *buffer = self.channels[targetChannelKey];
        if (buffer) {
            NSString *formattedMessage = [NSString stringWithFormat:@"[%@] *** %@", [self formatTime], message];
            BOOL removedOldest = [buffer addMessage:formattedMessage];

            if (removedOldest) {
                NSMutableArray *cached = self.cachedAttributedMessages[targetChannelKey];
                if (cached && cached.count > 0) [cached removeObjectAtIndex:0];
                if ([targetChannelKey isEqualToString:self.currentChannelKey]) self.channelKeyWithTrimmedHead = targetChannelKey;
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
}

#pragma mark - Time Formatting

- (NSString *)formatTime {
    @try {
        static NSDateFormatter *formatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"HH:mm:ss"];
        });
        
        NSDate *now = [NSDate date];
        if (now && formatter) {
            return [formatter stringFromDate:now] ?: @"00:00:00";
        }
        return @"00:00:00";
    } @catch (NSException *exception) {
        CVLog(@"Error in formatTime: %@", exception);
        return @"00:00:00";
    }
}

- (NSString *)formatTimestamp:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"HH:mm:ss"];
    });
    if (!date) {
        return @"00:00:00";
    }
    return [formatter stringFromDate:date] ?: @"00:00:00";
}

- (NSString *)formattedMessageFromStoredMessage:(Message *)message {
    NSString *timeStr = [self formatTimestamp:message.timestamp];
    NSString *sender = message.sender ?: @"";
    NSString *content = message.content ?: @"";
    NSString *msgType = message.msgType ?: @"";

    if ([msgType isEqualToString:@"system"]) {
        return [NSString stringWithFormat:@"[%@] *** %@", timeStr, content];
    }
    if ([msgType isEqualToString:@"notice"]) {
        return [NSString stringWithFormat:@"[%@] *** %@", timeStr, content];
    }
    if ([msgType isEqualToString:@"action"]) {
        return [NSString stringWithFormat:@"[%@] * %@ %@", timeStr, sender, content];
    }
    return [NSString stringWithFormat:@"[%@] <%@> %@", timeStr, sender, content];
}

- (void)loadRecentMessagesIfNeededForChannelKey:(NSString *)channelKey {
    if (!channelKey || channelKey.length == 0) {
        return;
    }
    ChannelBuffer *buffer = self.channels[channelKey];
    if (!buffer || buffer.messages.count > 0) {
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSArray<Message *> *messages = [[MessageStorage sharedStorage] loadRecentMessagesForWindowKey:channelKey limit:20];
        if (messages.count == 0) {
            return;
        }
        NSMutableArray<NSString *> *formatted = [[NSMutableArray alloc] initWithCapacity:messages.count];
        [self.cachedAttributedMessages removeObjectForKey:channelKey];
        [self.lastRenderedMessageCount removeObjectForKey:channelKey];
        for (Message *msg in messages) {
            NSString *line = [self formattedMessageFromStoredMessage:msg];
            [formatted addObject:line];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            ChannelBuffer *buf = self.channels[channelKey];
            if (buf && buf.messages.count == 0) {
                [buf.messages addObjectsFromArray:formatted];
                [buf trimMessagesToLimit];  // Apply message limit after loading history
                if ([channelKey isEqualToString:self.currentChannelKey]) {
                    [self displayMessagesForChannel:channelKey];
                }
            }
        });
    });
}

#pragma mark - IRC Formatting Parser

- (NSAttributedString *)parseIRCFormattingString:(NSString *)message font:(NSFont *)font defaultColor:(NSColor *)defaultColor {
    if (!message || message.length == 0) {
        return [[NSAttributedString alloc] initWithString:@"" attributes:@{NSFontAttributeName: font}];
    }
    
    // Fast path: check if message has no IRC control codes
    BOOL hasControlCodes = NO;
    for (NSUInteger i = 0; i < message.length; i++) {
        unichar c = [message characterAtIndex:i];
        if (c < 0x20 || (c >= 0x7F && c <= 0x9F)) {
            hasControlCodes = YES;
            break;
        }
    }
    if (!hasControlCodes) {
        // No IRC formatting, create simple attributed string
        NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: defaultColor};
        return [[NSAttributedString alloc] initWithString:message attributes:attrs];
    }
    
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray<NSColor *> *ircColors = [self ircColorTable];
    
    // Cache for font conversions
    static NSMutableDictionary<NSString *, NSFont *> *fontCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fontCache = [[NSMutableDictionary alloc] init];
    });
    
    NSColor *currentForeground = defaultColor;
    NSColor *currentBackground = nil;
    BOOL boldEnabled = NO;
    BOOL italicEnabled = NO;
    BOOL underlineEnabled = NO;
    BOOL strikeEnabled = NO;
    
    // Batch processing: collect characters with same attributes into segments
    NSMutableString *currentSegment = [[NSMutableString alloc] init];
    __block NSFont *currentFont = font;
    __block NSColor *currentSegmentForeground = defaultColor;
    __block NSColor *currentSegmentBackground = nil;
    __block BOOL currentSegmentUnderline = NO;
    __block BOOL currentSegmentStrike = NO;
    
    void (^flushSegment)(void) = ^{
        if (currentSegment.length > 0) {
            NSMutableDictionary *attrs = [[NSMutableDictionary alloc] init];
            attrs[NSFontAttributeName] = currentFont;
            attrs[NSForegroundColorAttributeName] = currentSegmentForeground;
            if (currentSegmentBackground) {
                attrs[NSBackgroundColorAttributeName] = currentSegmentBackground;
            }
            if (currentSegmentUnderline) {
                attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
            }
            if (currentSegmentStrike) {
                attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
            }
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:[currentSegment copy] attributes:attrs]];
            [currentSegment setString:@""];
        }
    };
    
    // Helper to update segment attributes based on current state
    void (^updateSegmentAttributes)(void) = ^{
        NSFontTraitMask traits = 0;
        if (boldEnabled) traits |= NSBoldFontMask;
        if (italicEnabled) traits |= NSItalicFontMask;
        
        if (traits != 0) {
            NSString *cacheKey = [NSString stringWithFormat:@"%@-%.1f-%lu", font.fontName, font.pointSize, (unsigned long)traits];
            NSFont *cachedFont = fontCache[cacheKey];
            if (cachedFont) {
                currentFont = cachedFont;
            } else {
                NSFont *converted = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:traits];
                if (converted) {
                    currentFont = converted;
                    fontCache[cacheKey] = converted;
                } else {
                    currentFont = font;
                }
            }
        } else {
            currentFont = font;
        }
        
        NSColor *effectiveForeground = currentForeground ?: defaultColor;
        NSColor *effectiveBackground = currentBackground;
        
        // Check if foreground and background have sufficient contrast
        if (effectiveBackground && ![self hasSufficientContrastBetween:effectiveForeground and:effectiveBackground]) {
            effectiveBackground = nil;
        }
        
        currentSegmentForeground = effectiveForeground;
        currentSegmentBackground = effectiveBackground;
        currentSegmentUnderline = underlineEnabled;
        currentSegmentStrike = strikeEnabled;
    };
    
    NSUInteger index = 0;
    while (index < message.length) {
        unichar c = [message characterAtIndex:index];
        
        if (c == 0x02) { // Bold
            flushSegment();
            boldEnabled = !boldEnabled;
            updateSegmentAttributes();
            index++;
            continue;
        }
        if (c == 0x1D) { // Italic
            flushSegment();
            italicEnabled = !italicEnabled;
            updateSegmentAttributes();
            index++;
            continue;
        }
        if (c == 0x1F) { // Underline
            flushSegment();
            underlineEnabled = !underlineEnabled;
            updateSegmentAttributes();
            index++;
            continue;
        }
        if (c == 0x1E) { // Strikethrough
            flushSegment();
            strikeEnabled = !strikeEnabled;
            updateSegmentAttributes();
            index++;
            continue;
        }
        if (self.showChannelColors && c == 0x16) { // Reverse
            flushSegment();
            NSColor *temp = currentForeground;
            currentForeground = currentBackground ?: defaultColor;
            currentBackground = temp;
            updateSegmentAttributes();
            index++;
            continue;
        }
        if (self.showChannelColors && c == 0x03) { // Color code
            flushSegment();
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
            } else {
                // IRC spec: \x03 with no digits resets colors
                currentForeground = defaultColor;
                currentBackground = nil;
                index++;
            }
            updateSegmentAttributes();
            continue;
        }

        if (c == 0x0F) {
            flushSegment();
            currentForeground = defaultColor;
            currentBackground = nil;
            boldEnabled = NO;
            italicEnabled = NO;
            underlineEnabled = NO;
            strikeEnabled = NO;
            updateSegmentAttributes();
            index++;
            continue;
        }
        
        // If channel colors are disabled, always use default foreground color
        if (!self.showChannelColors) {
            currentForeground = defaultColor;
            currentBackground = nil;
        }

        // Check if attributes changed, flush if needed
        NSFontTraitMask traits = 0;
        if (boldEnabled) traits |= NSBoldFontMask;
        if (italicEnabled) traits |= NSItalicFontMask;
        
        NSFont *resolvedFont = font;
        if (traits != 0) {
            NSString *cacheKey = [NSString stringWithFormat:@"%@-%.1f-%lu", font.fontName, font.pointSize, (unsigned long)traits];
            NSFont *cachedFont = fontCache[cacheKey];
            if (cachedFont) {
                resolvedFont = cachedFont;
            } else {
                NSFont *converted = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:traits];
                if (converted) {
                    resolvedFont = converted;
                    fontCache[cacheKey] = converted;
                }
            }
        }
        
        NSColor *effectiveForeground = currentForeground ?: defaultColor;
        NSColor *effectiveBackground = currentBackground;
        
        if (effectiveBackground && ![self hasSufficientContrastBetween:effectiveForeground and:effectiveBackground]) {
            effectiveBackground = nil;
        }
        
        // Check if we need to flush (attributes changed)
        BOOL needFlush = NO;
        if (resolvedFont != currentFont) needFlush = YES;
        if (![effectiveForeground isEqual:currentSegmentForeground]) needFlush = YES;
        BOOL backgroundChanged = NO;
        if (effectiveBackground == nil && currentSegmentBackground == nil) {
            backgroundChanged = NO;
        } else if (effectiveBackground == nil || currentSegmentBackground == nil) {
            backgroundChanged = YES;
        } else {
            backgroundChanged = ![effectiveBackground isEqual:currentSegmentBackground];
        }
        if (backgroundChanged) needFlush = YES;
        if (underlineEnabled != currentSegmentUnderline) needFlush = YES;
        if (strikeEnabled != currentSegmentStrike) needFlush = YES;
        
        if (needFlush) {
            flushSegment();
            currentFont = resolvedFont;
            currentSegmentForeground = effectiveForeground;
            currentSegmentBackground = effectiveBackground;
            currentSegmentUnderline = underlineEnabled;
            currentSegmentStrike = strikeEnabled;
        } else if (currentSegment.length == 0) {
            // First character: ensure attributes are set
            currentFont = resolvedFont;
            currentSegmentForeground = effectiveForeground;
            currentSegmentBackground = effectiveBackground;
            currentSegmentUnderline = underlineEnabled;
            currentSegmentStrike = strikeEnabled;
        }
        
        [currentSegment appendFormat:@"%C", c];
        index++;
    }
    
    flushSegment(); // Flush remaining segment
    
    return result;
}

- (NSString *)normalizedIRCFormattingString:(NSString *)message {
    if (message.length == 0) {
        return message;
    }
    NSMutableString *mutable = [message mutableCopy];
    [mutable replaceOccurrencesOfString:@"\\x01" withString:[NSString stringWithFormat:@"%C", (unichar)0x01]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\x02" withString:[NSString stringWithFormat:@"%C", (unichar)0x02]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\x03" withString:[NSString stringWithFormat:@"%C", (unichar)0x03]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\x04" withString:[NSString stringWithFormat:@"%C", (unichar)0x04]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\x0f" withString:[NSString stringWithFormat:@"%C", (unichar)0x0F]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\x1d" withString:[NSString stringWithFormat:@"%C", (unichar)0x1D]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\x1f" withString:[NSString stringWithFormat:@"%C", (unichar)0x1F]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\x16" withString:[NSString stringWithFormat:@"%C", (unichar)0x16]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\x1e" withString:[NSString stringWithFormat:@"%C", (unichar)0x1E]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];

    [mutable replaceOccurrencesOfString:@"\\u0001" withString:[NSString stringWithFormat:@"%C", (unichar)0x01]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\u0002" withString:[NSString stringWithFormat:@"%C", (unichar)0x02]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\u0003" withString:[NSString stringWithFormat:@"%C", (unichar)0x03]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\u0004" withString:[NSString stringWithFormat:@"%C", (unichar)0x04]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\u000f" withString:[NSString stringWithFormat:@"%C", (unichar)0x0F]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\u001d" withString:[NSString stringWithFormat:@"%C", (unichar)0x1D]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\u001f" withString:[NSString stringWithFormat:@"%C", (unichar)0x1F]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\u0016" withString:[NSString stringWithFormat:@"%C", (unichar)0x16]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\\u001e" withString:[NSString stringWithFormat:@"%C", (unichar)0x1E]
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, mutable.length)];

    // Control Pictures (U+2400 series) -> actual control codes
    [mutable replaceOccurrencesOfString:@"\u2401" withString:[NSString stringWithFormat:@"%C", (unichar)0x01]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\u2402" withString:[NSString stringWithFormat:@"%C", (unichar)0x02]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\u2403" withString:[NSString stringWithFormat:@"%C", (unichar)0x03]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\u2404" withString:[NSString stringWithFormat:@"%C", (unichar)0x04]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\u240F" withString:[NSString stringWithFormat:@"%C", (unichar)0x0F]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\u241D" withString:[NSString stringWithFormat:@"%C", (unichar)0x1D]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\u241F" withString:[NSString stringWithFormat:@"%C", (unichar)0x1F]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\u2416" withString:[NSString stringWithFormat:@"%C", (unichar)0x16]
                                options:0 range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\u241E" withString:[NSString stringWithFormat:@"%C", (unichar)0x1E]
                                options:0 range:NSMakeRange(0, mutable.length)];

    return [mutable copy];
}

#pragma mark - Color Helpers

- (BOOL)isValidHexColorString:(NSString *)string {
    if (string.length != 6) {
        return NO;
    }
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"];
    return ([string rangeOfCharacterFromSet:[hexSet invertedSet]].location == NSNotFound);
}

- (NSColor *)colorFromHexString:(NSString *)string {
    if (![self isValidHexColorString:string]) {
        return nil;
    }
    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:string];
    if (![scanner scanHexInt:&value]) {
        return nil;
    }
    CGFloat red = ((value >> 16) & 0xFF) / 255.0;
    CGFloat green = ((value >> 8) & 0xFF) / 255.0;
    CGFloat blue = (value & 0xFF) / 255.0;
    return [NSColor colorWithRed:red green:green blue:blue alpha:1.0];
}

// Calculate relative luminance using WCAG formula
- (CGFloat)colorLuminance:(NSColor *)color {
    if (!color) {
        return 1.0; // Default to white luminance
    }
    NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgbColor) {
        rgbColor = color;
    }
    
    CGFloat r = rgbColor.redComponent;
    CGFloat g = rgbColor.greenComponent;
    CGFloat b = rgbColor.blueComponent;
    
    // Apply gamma correction
    r = (r <= 0.03928) ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4);
    g = (g <= 0.03928) ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4);
    b = (b <= 0.03928) ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4);
    
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// Check if two colors have sufficient contrast (WCAG AA requires 4.5:1 for normal text)
// We use a lower threshold of 1.5:1 to avoid completely unreadable combinations
- (BOOL)hasSufficientContrastBetween:(NSColor *)color1 and:(NSColor *)color2 {
    if (!color1 || !color2) {
        return YES;
    }
    
    CGFloat lum1 = [self colorLuminance:color1];
    CGFloat lum2 = [self colorLuminance:color2];
    
    CGFloat lighter = MAX(lum1, lum2);
    CGFloat darker = MIN(lum1, lum2);
    
    // Contrast ratio formula: (L1 + 0.05) / (L2 + 0.05)
    CGFloat ratio = (lighter + 0.05) / (darker + 0.05);
    
    // Use a minimum contrast ratio of 1.5:1 to ensure basic readability
    return ratio >= 1.5;
}

- (NSArray<NSColor *> *)ircColorTable {
    static NSArray<NSColor *> *colors = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSColor *> *mutable = [[NSMutableArray alloc] initWithCapacity:100];
        // 0-15: mIRC base palette (fixed)
        [mutable addObject:[NSColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0]];      // 0 white
        [mutable addObject:[NSColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0]];      // 1 black
        [mutable addObject:[NSColor colorWithRed:0.0 green:0.0 blue:0.498 alpha:1.0]];    // 2 navy
        [mutable addObject:[NSColor colorWithRed:0.0 green:0.576 blue:0.0 alpha:1.0]];    // 3 green
        [mutable addObject:[NSColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0]];      // 4 red
        [mutable addObject:[NSColor colorWithRed:0.498 green:0.0 blue:0.0 alpha:1.0]];    // 5 brown
        [mutable addObject:[NSColor colorWithRed:0.611 green:0.0 blue:0.611 alpha:1.0]];  // 6 purple
        [mutable addObject:[NSColor colorWithRed:0.988 green:0.498 blue:0.0 alpha:1.0]];  // 7 orange
        [mutable addObject:[NSColor colorWithRed:1.0 green:1.0 blue:0.0 alpha:1.0]];      // 8 yellow
        [mutable addObject:[NSColor colorWithRed:0.0 green:0.988 blue:0.0 alpha:1.0]];    // 9 light green
        [mutable addObject:[NSColor colorWithRed:0.0 green:0.576 blue:0.576 alpha:1.0]];  // 10 teal
        [mutable addObject:[NSColor colorWithRed:0.0 green:1.0 blue:1.0 alpha:1.0]];      // 11 light cyan
        [mutable addObject:[NSColor colorWithRed:0.0 green:0.0 blue:0.988 alpha:1.0]];    // 12 blue
        [mutable addObject:[NSColor colorWithRed:1.0 green:0.0 blue:1.0 alpha:1.0]];      // 13 pink
        [mutable addObject:[NSColor colorWithRed:0.498 green:0.498 blue:0.498 alpha:1.0]];// 14 gray
        [mutable addObject:[NSColor colorWithRed:0.824 green:0.824 blue:0.824 alpha:1.0]];// 15 light gray

        NSArray<NSNumber *> *steps = @[@0, @95, @135, @175, @215, @255];
        for (NSInteger idx = 16; idx <= 99; idx++) {
            NSInteger cubeIndex = idx - 16;
            NSInteger r = cubeIndex / 36;
            NSInteger g = (cubeIndex / 6) % 6;
            NSInteger b = cubeIndex % 6;
            CGFloat red = steps[r].doubleValue / 255.0;
            CGFloat green = steps[g].doubleValue / 255.0;
            CGFloat blue = steps[b].doubleValue / 255.0;
            [mutable addObject:[NSColor colorWithRed:red green:green blue:blue alpha:1.0]];
        }
        colors = [mutable copy];
    });
    return colors;
}

#pragma mark - User List

- (void)updateUserListForChannel:(NSString *)channelKey {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateUserListForChannel:channelKey];
        });
        return;
    }
    
    ChannelBuffer *buffer = self.channels[channelKey];
    if (buffer) {
        NSInteger userCount = buffer.users ? buffer.users.count : 0;
        CVLog(@"updateUserListForChannel: Reloading user list for %@, users count: %lu", channelKey, (unsigned long)userCount);
        if (buffer.users) {
            CVLog(@"updateUserListForChannel: Users: %@", buffer.users);
        }
        
        if (self.userCountLabel) {
            self.userCountLabel.stringValue = [NSString stringWithFormat:L(@"chat.userCount.format", @"Users: %ld"), (long)userCount];
        }
        
        if (self.userListView) {
            CVLog(@"updateUserListForChannel: Calling reloadData on userListView");
            [self.userListView reloadData];
            [self.userListView setNeedsDisplay:YES];
            [self.userListView displayIfNeeded];
        } else {
            CVLog(@"Warning: userListView is nil!");
        }
    } else {
        CVLog(@"Warning: No buffer found for channelKey %@", channelKey);
        if (self.userCountLabel) {
            self.userCountLabel.stringValue = [NSString stringWithFormat:L(@"chat.userCount.format", @"Users: %ld"), 0L];
        }
    }
}

- (void)handleUserSearchChanged:(id)sender {
    NSString *query = @"";
    if ([sender isKindOfClass:[NSSearchField class]]) {
        NSSearchField *field = (NSSearchField *)sender;
        query = field.stringValue ?: @"";
    }
    query = [[query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    self.userSearchQuery = query.length > 0 ? query : nil;
    if (self.userListView) {
        [self.userListView reloadData];
    }
}

- (NSArray<NSString *> *)displayedUsersForCurrentChannel {
    if (!self.currentChannelKey) {
        return @[];
    }
    ChannelBuffer *buffer = self.channels[self.currentChannelKey];
    if (!buffer || !buffer.users) {
        return @[];
    }
    NSString *query = self.userSearchQuery ?: @"";
    NSMutableArray<NSString *> *source = [[NSMutableArray alloc] init];
    if (query.length == 0) {
        [source addObjectsFromArray:buffer.users];
        if (source.count == 0) {
            return @[];
        }
        // IRC role order: ~ (owner), & (admin), @ (op), % (halfop), + (voice), then normal.
        NSArray<NSString *> *sorted = [source sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSInteger aRank = [self ircRoleRankForUserListEntry:a];
            NSInteger bRank = [self ircRoleRankForUserListEntry:b];
            if (aRank != bRank) {
                return (aRank > bRank) ? NSOrderedAscending : NSOrderedDescending;
            }
            NSString *aBase = [self baseNickFromUserListEntry:a] ?: @"";
            NSString *bBase = [self baseNickFromUserListEntry:b] ?: @"";
            NSComparisonResult result = [aBase caseInsensitiveCompare:bBase];
            if (result != NSOrderedSame) {
                return result;
            }
            return [a compare:b];
        }];
        return sorted;
    }
    NSString *lowerQuery = [query lowercaseString];
    for (NSString *user in buffer.users) {
        if (!user) {
            continue;
        }
        NSString *baseUser = [self baseNickFromUserListEntry:user];
        NSString *lowerUser = [user lowercaseString];
        NSString *lowerBase = [baseUser lowercaseString];
        if ([lowerUser containsString:lowerQuery] || [lowerBase containsString:lowerQuery]) {
            [source addObject:user];
        }
    }
    return source.count > 0 ? source : @[];
}

- (NSInteger)ircRoleRankForUserListEntry:(NSString *)user {
    if (!user) {
        return 0;
    }
    NSString *trimmed = [user stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return 0;
    }
    unichar firstChar = [trimmed characterAtIndex:0];
    switch (firstChar) {
        case '~':
            return 5;
        case '&':
            return 4;
        case '@':
            return 3;
        case '%':
            return 2;
        case '+':
            return 1;
        default:
            return 0;
    }
}

#pragma mark - Status

- (void)updateStatus {
    IRCConfig *config = [self configForServer:self.currentServer];
    NSString *nick = config ? config.nick : @"";
    NSString *status = [NSString stringWithFormat:L(@"chat.status.format", @"Server: %@ | Nick: %@ | Channel: %@"),
                       self.currentServer,
                       nick,
                       self.currentChannelKey ? [self channelFromChannelKey:self.currentChannelKey] : L(@"chat.status.none", @"None")];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusField.stringValue = status;
    });
}

@end
