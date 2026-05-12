//
//  IRCClient.m
//  i3Chat
//

#import "IRCClient.h"
#import <Foundation/Foundation.h>
#import "DebugLog.h"

@interface IRCClient () <NSStreamDelegate>

@property (nonatomic, strong) IRCConfig *config;
@property (nonatomic, strong, nullable) NSInputStream *inputStream;
@property (nonatomic, strong, nullable) NSOutputStream *outputStream;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) BOOL registered;  // Registered with server (received 001 RPL_WELCOME)
@property (nonatomic, assign) BOOL joined;
@property (nonatomic, strong) NSMutableString *readBuffer;
@property (nonatomic, strong) dispatch_queue_t messageQueue;
@property (nonatomic, strong, nullable) NSTimer *pingTimer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *namesMap; // channel -> users
@property (nonatomic, strong) NSThread *streamThread;
@property (nonatomic, strong) NSRunLoop *streamRunLoop;
@property (nonatomic, assign) BOOL inputStreamOpen;
@property (nonatomic, assign) BOOL outputStreamOpen;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *serverChannelList; // Accumulate channel list before sending to UI
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *allChannelsList; // Accumulate ALL channels (including sent batches) for final complete list
@property (nonatomic, assign) NSInteger channelListBatchSize; // Batch size for incremental channel list updates
@property (nonatomic, assign) BOOL isReceivingChannelList; // Flag to track if we're currently receiving a channel list
@property (nonatomic, assign) NSUInteger channelList322Count; // Counter to track number of 322 messages received
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *pendingWhoisInfo; // Accumulate WHOIS info per nick

@end

@implementation IRCClient

- (instancetype)initWithConfig:(IRCConfig *)config {
    self = [super init];
    if (self) {
        _config = config;
        _readBuffer = [[NSMutableString alloc] init];
        _messageQueue = dispatch_queue_create("com.i3chat.irc.message", DISPATCH_QUEUE_SERIAL);
        _namesMap = [[NSMutableDictionary alloc] init];
        _inputStreamOpen = NO;
        _outputStreamOpen = NO;
        _registered = NO; // Not registered until 001 RPL_WELCOME received
        _serverChannelList = [[NSMutableArray alloc] init];
        _allChannelsList = [[NSMutableArray alloc] init];
        _channelListBatchSize = 50; // Default batch size for incremental updates
        _isReceivingChannelList = NO; // Not receiving channel list initially
        _pendingWhoisInfo = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (BOOL)connect {
    NSArray *components = [self.config.server componentsSeparatedByString:@":"];
    if (components.count != 2) {
        return NO;
    }
    
    NSString *host = components[0];
    NSInteger port = [components[1] integerValue];
    
    if (port == 0) {
        port = self.config.useTLS ? 6697 : 6667;
    }
    
    // Log connection info
    IRCLog(@"🌐 [CONNECTION] Starting connection to server: %@", self.config.server);
    IRCLog(@"🌐 [CONNECTION] Host: %@, Port: %ld, TLS: %@, Nick: %@", 
          host, (long)port, self.config.useTLS ? @"YES" : @"NO", self.config.nick);
    
    if ([self.delegate respondsToSelector:@selector(ircClient:didReceiveSystemMessage:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate ircClient:self didReceiveSystemMessage:[NSString stringWithFormat:@"Connecting to %@...", self.config.server]];
        });
    }
    
    // Create streams on background queue to avoid blocking
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CFReadStreamRef readStream;
        CFWriteStreamRef writeStream;
        
        CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, (UInt32)port, &readStream, &writeStream);
        
        NSInputStream *inputStream = (__bridge_transfer NSInputStream *)readStream;
        NSOutputStream *outputStream = (__bridge_transfer NSOutputStream *)writeStream;
        
        if (self.config.useTLS) {
            [inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                              forKey:NSStreamSocketSecurityLevelKey];
            [outputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                                forKey:NSStreamSocketSecurityLevelKey];
        }
        
        // Create a dedicated thread for stream processing to avoid blocking main thread
        self.streamThread = [[NSThread alloc] initWithBlock:^{
            @autoreleasepool {
                NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
                self.streamRunLoop = runLoop;
                
                IRCLog(@"🧵 [STREAM THREAD] Started stream thread run loop");
                
                self.inputStream = inputStream;
                self.outputStream = outputStream;
                
                self.inputStream.delegate = self;
                self.outputStream.delegate = self;
                
                [self.inputStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
                [self.outputStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
                
                [self.inputStream open];
                [self.outputStream open];
                
                // Keep the run loop running until the thread is cancelled
                while (![[NSThread currentThread] isCancelled]) {
                    @autoreleasepool {
                        [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                    }
                }
                
                IRCLog(@"🧵 [STREAM THREAD] Exiting stream thread run loop");
            }
        }];
        [self.streamThread start];
    });
    
    return YES;
}

- (void)disconnect {
    if (self.pingTimer) {
        [self.pingTimer invalidate];
        self.pingTimer = nil;
    }
    
    self.connected = NO;
    self.registered = NO;  // Reset registration status on disconnect
    
    [self sendRawCommand:@"QUIT :Goodbye!"];
    
    // Close streams on stream thread
    if (self.streamThread && self.streamThread.isExecuting) {
        [self performSelector:@selector(closeStreams) onThread:self.streamThread withObject:nil waitUntilDone:NO];
        [self.streamThread cancel];
    } else {
        [self closeStreams];
    }
}

- (void)closeStreams {
    if (self.inputStream) {
        [self.inputStream close];
        [self.inputStream removeFromRunLoop:self.streamRunLoop ?: [NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        self.inputStream = nil;
    }
    if (self.outputStream) {
        [self.outputStream close];
        [self.outputStream removeFromRunLoop:self.streamRunLoop ?: [NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        self.outputStream = nil;
    }
    self.connected = NO;
    self.registered = NO;  // Reset registration status
    self.joined = NO;
    self.inputStreamOpen = NO;
    self.outputStreamOpen = NO;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    // Stream delegate is called on stream thread (background thread)
    // This avoids blocking the main UI thread
    NSString *streamName = (aStream == self.inputStream) ? @"INPUT" : @"OUTPUT";
    NSString *eventName = @"UNKNOWN";
    switch (eventCode) {
        case NSStreamEventNone:
            eventName = @"None";
            break;
        case NSStreamEventOpenCompleted:
            eventName = @"OpenCompleted";
            if (aStream == self.inputStream) {
                IRCLog(@"✅ [STREAM] Input stream opened");
                self.inputStreamOpen = YES;
            } else if (aStream == self.outputStream) {
                IRCLog(@"✅ [STREAM] Output stream opened");
                self.outputStreamOpen = YES;
            }
            
            // Set connected only when both streams are open
            if (self.inputStreamOpen && self.outputStreamOpen && !self.connected) {
                IRCLog(@"✅ [STREAM] Both streams open, setting connected=YES");
                IRCLog(@"✅✅✅ [CONNECTION SUCCESS] Successfully connected to server: %@", self.config.server);
                IRCLog(@"✅✅✅ [CONNECTION SUCCESS] Server: %@, Port: %ld, TLS: %@", 
                      self.config.server, 
                      (long)([self.config.server componentsSeparatedByString:@":"].count > 1 ? 
                             [[self.config.server componentsSeparatedByString:@":"][1] integerValue] : 0),
                      self.config.useTLS ? @"YES" : @"NO");
                self.connected = YES;
                // Authenticate on background thread
                IRCLog(@"🔐 [LOGIN] Starting login process...");
                dispatch_async(self.messageQueue, ^{
                    [self authenticate];
                });
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(ircClient:didConnectToServer:)]) {
                        [self.delegate ircClient:self didConnectToServer:self.config.server];
                    }
                });
            }
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream == self.inputStream) {
                IRCLog(@"📥 [STREAM EVENT] HasBytesAvailable on input stream");
                // Read data on stream thread (not main thread)
                [self readData];
            } else {
                IRCLog(@"📥 [STREAM EVENT] HasBytesAvailable on output stream (unexpected)");
            }
            break;
            
        case NSStreamEventHasSpaceAvailable:
            IRCLog(@"📤 [STREAM EVENT] HasSpaceAvailable on %@ stream", streamName);
            // Ready to write
            break;
            
        case NSStreamEventErrorOccurred:
            eventName = @"ErrorOccurred";
            IRCLog(@"🔴 [STREAM EVENT] ErrorOccurred on %@ stream", streamName);
            if (aStream == self.inputStream) {
                self.inputStreamOpen = NO;
            } else if (aStream == self.outputStream) {
                self.outputStreamOpen = NO;
            }
            self.connected = NO;
            self.registered = NO;  // Reset registration status on error
            self.joined = NO;
            {
                NSError *error = [aStream streamError];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(ircClient:didDisconnectWithError:)]) {
                        [self.delegate ircClient:self didDisconnectWithError:error];
                    }
                });
            }
            break;
            
        case NSStreamEventEndEncountered:
            eventName = @"EndEncountered";
            IRCLog(@"🔴 [STREAM EVENT] EndEncountered on %@ stream", streamName);
            if (aStream == self.inputStream) {
                self.inputStreamOpen = NO;
            } else if (aStream == self.outputStream) {
                self.outputStreamOpen = NO;
            }
            self.connected = NO;
            self.registered = NO;  // Reset registration status on disconnect
            self.joined = NO;
            {
                NSError *error = [aStream streamError];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(ircClient:didDisconnectWithError:)]) {
                        [self.delegate ircClient:self didDisconnectWithError:error];
                    }
                });
            }
            break;
            
        default:
            IRCLog(@"⚠️ [STREAM EVENT] Unknown event %lu on %@ stream", (unsigned long)eventCode, streamName);
            break;
    }
}

- (void)readData {
    // Read data on current thread (stream thread, not main thread)
    // This avoids blocking the main UI thread
    IRCLog(@"📖 [READ DATA] Attempting to read from input stream");
    uint8_t buffer[4096];
    NSInteger bytesRead = [self.inputStream read:buffer maxLength:sizeof(buffer)];
    
    IRCLog(@"📖 [READ DATA] Read %ld bytes, stream status: %lu", 
          (long)bytesRead, (unsigned long)self.inputStream.streamStatus);
    
    if (bytesRead > 0) {
        // Try UTF-8 first, then fallback to ISO Latin 1 (common in IRC)
        NSString *data = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSUTF8StringEncoding];
        if (!data) {
            // Fallback to ISO Latin 1 (covers most Western European characters)
            data = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSISOLatin1StringEncoding];
            if (data) {
                IRCLog(@"⚠️ [READ WARNING] UTF-8 decode failed, using ISO Latin 1");
            }
        }
        if (!data) {
            // Last resort: ASCII with lossy conversion
            data = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSASCIIStringEncoding];
            if (data) {
                IRCLog(@"⚠️ [READ WARNING] ISO Latin 1 decode failed, using ASCII");
            }
        }
        
        if (data) {
            // Log raw data received from server
            IRCLog(@"🔵 [SERVER RAW DATA] Received %ld bytes: %@", (long)bytesRead, [data stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"]);
            
            // Append to buffer and process on background queue
            dispatch_async(self.messageQueue, ^{
                @synchronized(self.readBuffer) {
                    [self.readBuffer appendString:data];
                }
                // Process buffer on background queue
                [self processBuffer];
            });
        } else {
            IRCLog(@"🔴 [READ ERROR] Failed to convert bytes to string with any encoding");
        }
    } else if (bytesRead == 0) {
        IRCLog(@"⚠️ [READ WARNING] Read 0 bytes (stream may be closed or empty)");
    } else if (bytesRead < 0) {
        // Error reading
        NSError *error = [self.inputStream streamError];
        IRCLog(@"🔴 [SERVER ERROR] Read error: %@", error);
        if (error && [self.delegate respondsToSelector:@selector(ircClient:didDisconnectWithError:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate ircClient:self didDisconnectWithError:error];
            });
        }
    }
}

- (void)processBuffer {
    // Process buffer on message queue (background thread)
    NSMutableArray *completeLines = [NSMutableArray array];
    
    @synchronized(self.readBuffer) {
        // IRC protocol uses \r\n as line terminator, but some servers may use just \n or \r
        // Normalize the buffer: replace \r\n with \n, then replace standalone \r with \n
        NSMutableString *normalizedBuffer = [NSMutableString stringWithString:self.readBuffer];
        [normalizedBuffer replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, normalizedBuffer.length)];
        [normalizedBuffer replaceOccurrencesOfString:@"\r" withString:@"\n" options:0 range:NSMakeRange(0, normalizedBuffer.length)];
        
        // Update the read buffer with normalized content
        [self.readBuffer setString:normalizedBuffer];
        
        NSArray *lines = [self.readBuffer componentsSeparatedByString:@"\n"];
        
        // Process all complete lines (all but the last one)
        // The last element after split is either empty (if ended with \n) or incomplete
        for (NSInteger i = 0; i < (NSInteger)lines.count - 1; i++) {
            NSString *line = lines[i];
            if (line.length > 0) {
                [completeLines addObject:line];
            }
        }
        
        // Keep the last incomplete line in the buffer (or empty if buffer ended with \n)
        if (lines.count > 0) {
            NSString *lastLine = [lines lastObject];
            [self.readBuffer setString:lastLine ?: @""];
        } else {
            [self.readBuffer setString:@""];
        }
    }
    
    // Process complete lines outside the synchronized block
    // Use exception handling to ensure one bad message doesn't stop processing others
    for (NSString *line in completeLines) {
        @try {
            IRCLog(@"📥 [SERVER MESSAGE] %@", line);
            
            // Notify delegate about raw message
            if ([self.delegate respondsToSelector:@selector(ircClient:didReceiveRawMessage:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate ircClient:self didReceiveRawMessage:line];
                });
            }
            
            [self handleMessage:line];
        } @catch (NSException *exception) {
            // Log error but continue processing other messages
            IRCLog(@"🔴 [MESSAGE PROCESSING ERROR] Exception while processing message: %@", exception);
            IRCLog(@"🔴 [MESSAGE PROCESSING ERROR] Message was: %@", line);
            IRCLog(@"🔴 [MESSAGE PROCESSING ERROR] Stack trace: %@", [exception callStackSymbols]);
            // Continue processing next message - don't let one bad message stop the flow
        }
    }
}

// Parse IRC message according to RFC 1459 format:
// [":" prefix SPACE] command [SPACE params] [":" trailing] CRLF
- (NSArray *)parseIRCMessage:(NSString *)line {
    @try {
        NSMutableArray *result = [NSMutableArray array];
        NSMutableArray *params = [NSMutableArray array];
        NSString *prefix = nil;
        NSString *command = nil;
        NSString *trailing = nil;
        
        // Trim CRLF
        line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (line.length == 0) {
            return nil;
        }
    
    NSInteger pos = 0;
    NSInteger len = line.length;
    
    // Parse prefix (if present, starts with ':')
    if (pos < len && [line characterAtIndex:pos] == ':') {
        NSInteger prefixStart = pos + 1;
        NSRange spaceRange = [line rangeOfString:@" " options:0 range:NSMakeRange(prefixStart, len - prefixStart)];
        if (spaceRange.location != NSNotFound) {
            prefix = [line substringWithRange:NSMakeRange(prefixStart, spaceRange.location - prefixStart)];
            pos = spaceRange.location + 1;
        } else {
            // No space found, entire rest is prefix
            prefix = [line substringFromIndex:prefixStart];
            pos = len;
        }
    }
    
    // Parse command (next token until space or end)
    if (pos < len) {
        NSInteger commandStart = pos;
        NSRange spaceRange = [line rangeOfString:@" " options:0 range:NSMakeRange(commandStart, len - commandStart)];
        if (spaceRange.location != NSNotFound) {
            command = [line substringWithRange:NSMakeRange(commandStart, spaceRange.location - commandStart)];
            pos = spaceRange.location + 1;
        } else {
            command = [line substringFromIndex:commandStart];
            pos = len;
        }
    }
    
    // Parse params and trailing
    // According to IRC protocol, trailing starts with ':' and must follow a space
    if (pos < len) {
        while (pos < len) {
            // Check if current position starts with ':' (trailing marker)
            // The ':' must be at the start of a token (after space or at start of params)
            if ([line characterAtIndex:pos] == ':') {
                // Found trailing marker - everything after ':' is trailing (can contain spaces)
                trailing = [line substringFromIndex:pos + 1];
                break;
            }
            
            // Find next space
            NSRange spaceRange = [line rangeOfString:@" " options:0 range:NSMakeRange(pos, len - pos)];
            if (spaceRange.location != NSNotFound) {
                NSString *param = [line substringWithRange:NSMakeRange(pos, spaceRange.location - pos)];
                if (param.length > 0) {
                    [params addObject:param];
                }
                pos = spaceRange.location + 1;
                // After space, check if next char is ':' for trailing
                if (pos < len && [line characterAtIndex:pos] == ':') {
                    trailing = [line substringFromIndex:pos + 1];
                    break;
                }
            } else {
                // Last param (no trailing)
                NSString *param = [line substringFromIndex:pos];
                if (param.length > 0) {
                    [params addObject:param];
                }
                break;
            }
        }
    }
    
    // Build result array: [prefix, command, param1, param2, ..., trailing]
    if (prefix) {
        [result addObject:[NSString stringWithFormat:@":%@", prefix]];
    } else {
        [result addObject:@""];
    }
    
    if (command) {
        [result addObject:command];
    } else {
        [result addObject:@""];
    }
    
    [result addObjectsFromArray:params];
    
        if (trailing) {
            [result addObject:[NSString stringWithFormat:@":%@", trailing]];
        }
        
        return result;
    } @catch (NSException *exception) {
        // Log parsing error but return nil to allow handleMessage to handle gracefully
        IRCLog(@"🔴 [PARSE ERROR] Exception while parsing IRC message: %@", exception);
        IRCLog(@"🔴 [PARSE ERROR] Message was: %@", line);
        IRCLog(@"🔴 [PARSE ERROR] Stack trace: %@", [exception callStackSymbols]);
        return nil;
    }
}

- (void)handleMessage:(NSString *)line {
    // Wrap entire message handling in exception handler to prevent one bad message
    // from interrupting LIST command processing or other message flows
    @try {
        // Save delegate reference to avoid race conditions
        id<IRCClientDelegate> delegate = self.delegate;
        
        // Log every message for debugging（仅输出到控制台，不一定写入 UI）
        static NSInteger messageCount = 0;
        messageCount++;
        IRCLog(@"🔍 [HANDLE MESSAGE #%ld] Processing: %@", (long)messageCount, line);
        
        // Parse IRC message correctly according to RFC 1459
        NSArray *parts = [self parseIRCMessage:line];
        if (!parts || parts.count < 2) {
            // 对无效行，仍然可以简单写一条到 UI 日志（如果需要）
            if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveLogMessage:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [delegate ircClient:self didReceiveLogMessage:[NSString stringWithFormat:@"← %@", line]];
                });
            }
            return;
        }
    
    // 对于 LIST 相关的大量回复（321/322/323），避免把每一行都写入 UI 日志，减轻主线程压力
    NSString *codeForLog = parts.count > 1 ? parts[1] : @"";
    BOOL isListFlood =
        [codeForLog isEqualToString:@"321"] || // RPL_LISTSTART
        [codeForLog isEqualToString:@"322"] || // RPL_LIST
        [codeForLog isEqualToString:@"323"];   // RPL_LISTEND
    
    // 仅当不是 LIST 洪水时，才把原始行发给界面线程的日志窗口
    if (!isListFlood && delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveLogMessage:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate ircClient:self didReceiveLogMessage:[NSString stringWithFormat:@"← %@", line]];
        });
    }
    
    // Handle PING
    // PING format: "PING :server" or ":server PING :token"
    // With new parser: parts[1]="PING", parts[2]=":server" or ":token"
    if (parts.count >= 2 && [parts[1] isEqualToString:@"PING"]) {
        NSString *pong = [line stringByReplacingOccurrencesOfString:@"PING" withString:@"PONG"];
        [self sendRawCommand:pong];
        return;
    }
    
    // Handle server responses
    if (parts.count >= 2) {
        NSString *code = parts[1];
        
        // Handle login/registration responses
        if ([code isEqualToString:@"001"]) {
            // RPL_WELCOME - Welcome message
            IRCLog(@"✅✅✅ [LOGIN SUCCESS] 001 RPL_WELCOME - Registration successful!");
            IRCLog(@"✅ [LOGIN RESPONSE] Full message: %@", line);
            
            // Mark as registered with server
            self.registered = YES;
            
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(ircClient:didReceiveSystemMessage:)]) {
                    if (serverMsg.length > 0) {
                        [self.delegate ircClient:self didReceiveSystemMessage:serverMsg];
                    } else {
                        [self.delegate ircClient:self didReceiveSystemMessage:@"Registered with server"];
                    }
                }
                
                if ([self.delegate respondsToSelector:@selector(ircClientDidRegister:)]) {
                    [self.delegate ircClientDidRegister:self];
                }
            });
            
            if (self.config.channel.length > 0) {
                IRCLog(@"🔐 [LOGIN] Auto-joining channel: %@", self.config.channel);
                [self joinChannel:self.config.channel];
            }
            
            [self startPingTimer];
        }
        else if ([code isEqualToString:@"002"]) {
            // RPL_YOURHOST - Your host information
            IRCLog(@"✅ [LOGIN RESPONSE] 002 RPL_YOURHOST - Host info: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"003"]) {
            // RPL_CREATED - Server creation date
            IRCLog(@"✅ [LOGIN RESPONSE] 003 RPL_CREATED - Server created: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"004"]) {
            // RPL_MYINFO - Server information
            IRCLog(@"✅ [LOGIN RESPONSE] 004 RPL_MYINFO - Server info: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"005"]) {
            // RPL_ISUPPORT - Server supported features
            IRCLog(@"✅ [LOGIN RESPONSE] 005 RPL_ISUPPORT - Server features: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"251"]) {
            // RPL_LUSERCLIENT - User count information
            IRCLog(@"✅ [LOGIN RESPONSE] 251 RPL_LUSERCLIENT - User info: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"252"]) {
            // RPL_LUSEROP - Operator count
            IRCLog(@"✅ [LOGIN RESPONSE] 252 RPL_LUSEROP - Operator info: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"254"]) {
            // RPL_LUSERCHANNELS - Channel count
            IRCLog(@"✅ [LOGIN RESPONSE] 254 RPL_LUSERCHANNELS - Channel info: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"255"]) {
            // RPL_LUSERME - User information
            IRCLog(@"✅ [LOGIN RESPONSE] 255 RPL_LUSERME - User info: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"265"]) {
            // RPL_LOCALUSERS - Local user count
            IRCLog(@"✅ [LOGIN RESPONSE] 265 RPL_LOCALUSERS - Local user info: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"266"]) {
            // RPL_GLOBALUSERS - Global user count
            IRCLog(@"✅ [LOGIN RESPONSE] 266 RPL_GLOBALUSERS - Global user info: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"375"]) {
            // RPL_MOTDSTART - MOTD start
            IRCLog(@"✅ [LOGIN RESPONSE] 375 RPL_MOTDSTART - MOTD start: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"372"]) {
            // RPL_MOTD - MOTD line
            IRCLog(@"✅ [LOGIN RESPONSE] 372 RPL_MOTD - MOTD line: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        else if ([code isEqualToString:@"376"]) {
            // RPL_ENDOFMOTD - End of MOTD
            IRCLog(@"✅ [LOGIN RESPONSE] 376 RPL_ENDOFMOTD - End of MOTD: %@", line);
            NSString *serverMsg = [self extractNumericReplyMessage:parts];
            if (serverMsg.length > 0) {
                [self dispatchSystemMessage:serverMsg];
            }
        }
        // 433 ERR_NICKNAMEINUSE is handled later with retry logic
        else if ([code isEqualToString:@"JOIN"]) {
            if (parts.count >= 3) {
                NSString *prefix = parts[0];
                NSString *channel = parts[2];
                // Remove leading colon if present (IRC protocol uses colon for trailing parameters)
                if ([channel hasPrefix:@":"]) {
                    channel = [channel substringFromIndex:1];
                }
                
                // Validate channel name - must start with # or & and not contain :
                // Skip invalid channel names like "#a:bifrost.ca.us.dal.net"
                BOOL isValidChannel = ([channel hasPrefix:@"#"] || [channel hasPrefix:@"&"]) && ![channel containsString:@":"];
                if (!isValidChannel) {
                    IRCLog(@"⚠️ [JOIN] Skipping invalid channel name: %@", channel);
                } else {
                    NSString *nick = [self extractNickFromPrefix:prefix];
                    
                    // Check if this is the current user joining (compare extracted nick with our nick)
                    if ([nick isEqualToString:self.config.nick]) {
                        self.joined = YES;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if ([self.delegate respondsToSelector:@selector(ircClient:didJoinChannel:)]) {
                                [self.delegate ircClient:self didJoinChannel:channel];
                            }
                        });
                    }
                    
                    NSMutableSet *users = self.namesMap[channel];
                    if (!users) {
                        users = [[NSMutableSet alloc] init];
                        self.namesMap[channel] = users;
                    }
                    [users addObject:nick];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([self.delegate respondsToSelector:@selector(ircClient:didAddUser:toChannel:)]) {
                            [self.delegate ircClient:self didAddUser:nick toChannel:channel];
                        }
                    });
                }
            }
        }
        else if ([code isEqualToString:@"PART"]) {
            if (parts.count >= 3) {
                NSString *prefix = parts[0];
                NSString *channel = parts[2];
                // Remove leading colon if present (IRC protocol uses colon for trailing parameters)
                if ([channel hasPrefix:@":"]) {
                    channel = [channel substringFromIndex:1];
                }
                NSString *nick = [self extractNickFromPrefix:prefix];
                
                NSMutableSet *users = self.namesMap[channel];
                if (users) {
                    [users removeObject:nick];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(ircClient:didRemoveUser:fromChannel:)]) {
                        [self.delegate ircClient:self didRemoveUser:nick fromChannel:channel];
                    }
                });

                if ([nick isEqualToString:self.config.nick]) {
                    [self.namesMap removeObjectForKey:channel];
                    self.joined = self.namesMap.count > 0;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([self.delegate respondsToSelector:@selector(ircClient:didPartChannel:)]) {
                            [self.delegate ircClient:self didPartChannel:channel];
                        }
                    });
                }
            }
        }
        else if ([code isEqualToString:@"QUIT"]) {
            if (parts.count >= 2) {
                NSString *prefix = parts[0];
                NSString *nick = [self extractNickFromPrefix:prefix];
                
                // Extract reason from trailing parameter (if present)
                NSString *reason = @"";
                if (parts.count >= 3) {
                    reason = [self trailingTextFromParts:parts startIndex:2];
                }
                
                // Remove user from all channels in namesMap
                for (NSString *channel in self.namesMap.allKeys) {
                    NSMutableSet *users = self.namesMap[channel];
                    if (users) {
                        [users removeObject:nick];
                    }
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(ircClient:didRemoveUserFromAllChannels:reason:)]) {
                        [self.delegate ircClient:self didRemoveUserFromAllChannels:nick reason:reason];
                    }
                });
            }
        }
        else if ([code isEqualToString:@"KICK"]) {
            // Handle KICK command: user is kicked from channel
            // Format: ":kicker!user@host KICK #channel kicked_user :reason"
            if (parts.count >= 4) {
                NSString *prefix = parts[0];
                NSString *channel = parts[2];
                // Remove leading colon if present
                if ([channel hasPrefix:@":"]) {
                    channel = [channel substringFromIndex:1];
                }
                NSString *kickedNick = parts[3];
                // Remove leading colon if present (reason may start with colon)
                if ([kickedNick hasPrefix:@":"]) {
                    kickedNick = [kickedNick substringFromIndex:1];
                }
                
                // Remove kicked user from namesMap
                NSMutableSet *users = self.namesMap[channel];
                if (users) {
                    [users removeObject:kickedNick];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(ircClient:didRemoveUser:fromChannel:)]) {
                        [self.delegate ircClient:self didRemoveUser:kickedNick fromChannel:channel];
                    }
                });
            }
        }
        else if ([code isEqualToString:@"PRIVMSG"]) {
            if (parts.count >= 4) {
                NSString *prefix = parts[0];
                NSString *target = parts[2];
                NSArray *messageParts = [parts subarrayWithRange:NSMakeRange(3, parts.count - 3)];
                NSString *message = [[messageParts componentsJoinedByString:@" "]
                                     stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
                NSString *nick = [self extractNickFromPrefix:prefix];
                
                BOOL isPrivate = ![target hasPrefix:@"#"] && ![target hasPrefix:@"&"];
                
                // For private messages, use the sender's nick as the channel name
                // (target is our own nick, but we want to display sender's nick)
                NSString *channel = isPrivate ? nick : target;
                
                id<IRCClientDelegate> delegate = self.delegate;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveMessage:fromNick:inChannel:isPrivate:)]) {
                        [delegate ircClient:self didReceiveMessage:message fromNick:nick inChannel:channel isPrivate:isPrivate];
                    }
                });
            }
        }
        else if ([code isEqualToString:@"NOTICE"]) {
            if (parts.count >= 4) {
                NSString *prefix = parts[0];
                NSArray *noticeParts = [parts subarrayWithRange:NSMakeRange(3, parts.count - 3)];
                NSString *notice = [[noticeParts componentsJoinedByString:@" "]
                                     stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
                NSString *nick = [self extractNickFromPrefix:prefix];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(ircClient:didReceiveNotice:fromNick:)]) {
                        [self.delegate ircClient:self didReceiveNotice:notice fromNick:nick];
                    }
                });
            }
        }
        else if ([code isEqualToString:@"NICK"]) {
            // Handle NICK change response
            // Format: ":oldnick!user@host NICK :newnick"
            if (parts.count >= 3) {
                NSString *prefix = parts[0];
                NSString *oldNick = [self extractNickFromPrefix:prefix];
                NSString *newNick = parts[2];
                // Remove leading colon if present
                if ([newNick hasPrefix:@":"]) {
                    newNick = [newNick substringFromIndex:1];
                }
                
                // Update user lists in all channels
                NSMutableArray<NSString *> *affectedChannels = [[NSMutableArray alloc] init];
                for (NSString *channel in self.namesMap.allKeys) {
                    NSMutableSet *users = self.namesMap[channel];
                    if (users && [users containsObject:oldNick]) {
                        [users removeObject:oldNick];
                        [users addObject:newNick];
                        [affectedChannels addObject:channel];
                    }
                }

                // Check if this is our own nickname change
                if ([oldNick isEqualToString:self.config.nick]) {
                    IRCLog(@"✅ [NICK CHANGE] Nickname changed from %@ to %@", oldNick, newNick);
                    self.config.nick = newNick;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([self.delegate respondsToSelector:@selector(ircClient:didReceiveSystemMessage:)]) {
                            [self.delegate ircClient:self didReceiveSystemMessage:[NSString stringWithFormat:@"Nickname changed to %@", newNick]];
                        }
                    });
                } else {
                    IRCLog(@"ℹ️ [NICK CHANGE] %@ changed nickname to %@", oldNick, newNick);
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(ircClient:didChangeNick:toNick:inChannels:)]) {
                        [self.delegate ircClient:self didChangeNick:oldNick toNick:newNick inChannels:affectedChannels];
                    }
                });
            }
        }
        else if ([code isEqualToString:@"353"]) {
            // RPL_NAMREPLY
            // Format: ":server 353 nick [=@] #channel :user1 user2 user3"
            // Example: ":singleton.oftc.net 353 user-i3chat = #test2 :user-i3chat @KGB"
            // parts[0] = ":singleton.oftc.net"
            // parts[1] = "353"
            // parts[2] = "user-i3chat" (nickname)
            // parts[3] = "=" (channel type indicator: = for public, @ for secret, * for private)
            // parts[4] = "#test2" (channel name)
            // parts[5] = ":user-i3chat" (user list starts with colon)
            // parts[6] = "@KGB" (more users)
            if (parts.count >= 6) {
                NSString *channel = parts[4];
                // Remove leading colon if present
                channel = [channel stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
                
                NSMutableSet *users = self.namesMap[channel];
                if (!users) {
                    users = [[NSMutableSet alloc] init];
                    self.namesMap[channel] = users;
                }
                
                // Parse user list starting from parts[5]
                // The first user part starts with colon, remove it
                NSMutableArray *userArray = [[NSMutableArray alloc] init];
                for (NSInteger i = 5; i < parts.count; i++) {
                    NSString *userPart = parts[i];
                    if (i == 5) {
                        // First part starts with colon, remove it
                        if ([userPart hasPrefix:@":"]) {
                            userPart = [userPart substringFromIndex:1];
                        }
                    }
                    if (userPart.length > 0) {
                        [userArray addObject:userPart];
                    }
                }
                
                // Now split each part by spaces (in case there are multiple users in one part)
                for (NSString *userPart in userArray) {
                    NSArray *usersInPart = [userPart componentsSeparatedByString:@" "];
                    for (NSString *user in usersInPart) {
                        if (user.length > 0) {
                            // Remove mode prefixes (@, +, %, &, ~, etc.)
                            NSString *cleanUser = user;
                            // Remove all mode prefixes from the beginning
                            while (cleanUser.length > 0 && [@"@+%&~" rangeOfString:[cleanUser substringToIndex:1]].location != NSNotFound) {
                                cleanUser = [cleanUser substringFromIndex:1];
                            }
                            if (cleanUser.length > 0) {
                                [users addObject:cleanUser];
                            }
                        }
                    }
                }
                
                // Don't send update here - wait for 366 (ENDOFNAMES)
                IRCLog(@"353 RPL_NAMREPLY: Added users for channel %@, total: %lu", channel, (unsigned long)users.count);
            }
        }
        else if ([code isEqualToString:@"366"]) {
            // RPL_ENDOFNAMES - End of NAMES list
            // Format: ":server 366 nick #channel :End of /NAMES list"
            if (parts.count >= 4) {
                NSString *channel = parts[3];
                // Remove leading colon if present
                channel = [channel stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
                
                NSMutableSet *users = self.namesMap[channel];
                if (users) {
                    NSArray *sortedUsers = [[users allObjects] sortedArrayUsingSelector:@selector(compare:)];
                    IRCLog(@"366 RPL_ENDOFNAMES: Sending user list for channel %@ with %lu users", channel, (unsigned long)sortedUsers.count);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([self.delegate respondsToSelector:@selector(ircClient:didUpdateUserList:forChannel:)]) {
                            [self.delegate ircClient:self didUpdateUserList:sortedUsers forChannel:channel];
                        } else {
                            IRCLog(@"Warning: delegate does not respond to didUpdateUserList:forChannel:");
                        }
                    });
                    [self.namesMap removeObjectForKey:channel];
                } else {
                    IRCLog(@"Warning: No users found for channel %@ in namesMap", channel);
                }
            }
        }
        else if ([code isEqualToString:@"301"]) {
            // RPL_AWAY
            if (parts.count >= 5) {
                NSString *target = parts[3];
                NSString *awayMessage = [self trailingTextFromParts:parts startIndex:4];
                // Store in pending whois info
                NSMutableDictionary *info = [self pendingWhoisInfoForNick:target];
                info[@"awayMessage"] = awayMessage ?: @"";
                // Also send system message
                NSString *message = [NSString stringWithFormat:@"WHOIS %@: away - %@", target, awayMessage];
                [self dispatchSystemMessage:message];
            }
        }
        else if ([code isEqualToString:@"311"]) {
            // RPL_WHOISUSER
            if (parts.count >= 6) {
                NSString *target = parts[3] ?: @"";
                NSString *user = parts[4] ?: @"";
                NSString *host = parts[5] ?: @"";
                NSString *realName = @"";
                if (parts.count >= 7) {
                    realName = [self trailingTextFromParts:parts startIndex:6];
                    if ([realName hasPrefix:@"* "]) {
                        realName = [realName substringFromIndex:2];
                    } else if ([realName hasPrefix:@"*"]) {
                        realName = [realName substringFromIndex:1];
                    }
                    realName = [realName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                }
                // Store in pending whois info
                NSMutableDictionary *info = [self pendingWhoisInfoForNick:target];
                info[@"nick"] = target;
                info[@"user"] = user;
                info[@"host"] = host;
                info[@"realName"] = realName;
                // Also send system message
                NSString *message = realName.length > 0
                    ? [NSString stringWithFormat:@"WHOIS %@: %@%@%@ (%@)", target, user, @"@", host, realName]
                    : [NSString stringWithFormat:@"WHOIS %@: %@%@%@", target, user, @"@", host];
                [self dispatchSystemMessage:message];
            }
        }
        else if ([code isEqualToString:@"312"]) {
            // RPL_WHOISSERVER
            if (parts.count >= 5) {
                NSString *target = parts[3] ?: @"";
                NSString *server = parts[4] ?: @"";
                NSString *serverInfo = [self trailingTextFromParts:parts startIndex:5];
                // Store in pending whois info
                NSMutableDictionary *info = [self pendingWhoisInfoForNick:target];
                info[@"server"] = server;
                info[@"serverInfo"] = serverInfo ?: @"";
                // Also send system message
                NSString *message = serverInfo.length > 0
                    ? [NSString stringWithFormat:@"WHOIS %@: server %@ (%@)", target, server, serverInfo]
                    : [NSString stringWithFormat:@"WHOIS %@: server %@", target, server];
                [self dispatchSystemMessage:message];
            }
        }
        else if ([code isEqualToString:@"313"]) {
            // RPL_WHOISOPERATOR
            if (parts.count >= 4) {
                NSString *target = parts[3] ?: @"";
                NSString *operatorInfo = [self trailingTextFromParts:parts startIndex:4];
                // Store in pending whois info
                NSMutableDictionary *info = [self pendingWhoisInfoForNick:target];
                info[@"isOperator"] = @YES;
                info[@"operatorInfo"] = operatorInfo ?: @"";
                // Also send system message
                NSString *message = operatorInfo.length > 0
                    ? [NSString stringWithFormat:@"WHOIS %@: %@", target, operatorInfo]
                    : [NSString stringWithFormat:@"WHOIS %@: is an IRC operator", target];
                [self dispatchSystemMessage:message];
            }
        }
        else if ([code isEqualToString:@"317"]) {
            // RPL_WHOISIDLE
            if (parts.count >= 6) {
                NSString *target = parts[3] ?: @"";
                NSString *idleSecondsStr = parts[4] ?: @"";
                NSString *signonTimeStr = parts[5] ?: @"";
                // Store in pending whois info
                NSMutableDictionary *info = [self pendingWhoisInfoForNick:target];
                info[@"idleSeconds"] = @([idleSecondsStr integerValue]);
                info[@"signonTime"] = @([signonTimeStr integerValue]);
                // Also send system message
                NSString *message = [NSString stringWithFormat:@"WHOIS %@: idle %@s, signon %@", target, idleSecondsStr, signonTimeStr];
                [self dispatchSystemMessage:message];
            }
        }
        else if ([code isEqualToString:@"318"]) {
            // RPL_ENDOFWHOIS
            if (parts.count >= 4) {
                NSString *target = parts[3] ?: @"";
                // Get the collected whois info and notify delegate
                NSDictionary *whoisInfo = [self.pendingWhoisInfo[target] copy];
                [self.pendingWhoisInfo removeObjectForKey:target];
                
                id<IRCClientDelegate> delegate = self.delegate;
                if (whoisInfo && delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveWhoisInfo:forNick:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [delegate ircClient:self didReceiveWhoisInfo:whoisInfo forNick:target];
                    });
                }
                // Also send system message
                NSString *message = [NSString stringWithFormat:@"WHOIS %@: End of WHOIS", target];
                [self dispatchSystemMessage:message];
            }
        }
        else if ([code isEqualToString:@"319"]) {
            // RPL_WHOISCHANNELS
            if (parts.count >= 5) {
                NSString *target = parts[3] ?: @"";
                NSString *channels = [self trailingTextFromParts:parts startIndex:4];
                // Store in pending whois info
                NSMutableDictionary *info = [self pendingWhoisInfoForNick:target];
                NSString *existingChannels = info[@"channels"] ?: @"";
                if (existingChannels.length > 0 && channels.length > 0) {
                    info[@"channels"] = [existingChannels stringByAppendingFormat:@" %@", channels];
                } else {
                    info[@"channels"] = channels ?: @"";
                }
                // Also send system message
                NSString *message = [NSString stringWithFormat:@"WHOIS %@: channels %@", target, channels];
                [self dispatchSystemMessage:message];
            }
        }
        else if ([code isEqualToString:@"401"]) {
            // ERR_NOSUCHNICK
            if (parts.count >= 4) {
                NSString *target = parts[3] ?: @"";
                NSString *reason = [self trailingTextFromParts:parts startIndex:4];
                // Store error in pending whois info and finalize
                NSMutableDictionary *info = [self pendingWhoisInfoForNick:target];
                info[@"error"] = reason.length > 0 ? reason : @"No such nick/channel";
                
                NSDictionary *whoisInfo = [info copy];
                [self.pendingWhoisInfo removeObjectForKey:target];
                
                id<IRCClientDelegate> delegate = self.delegate;
                if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveWhoisInfo:forNick:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [delegate ircClient:self didReceiveWhoisInfo:whoisInfo forNick:target];
                    });
                }
                // Also send system message
                NSString *message = reason.length > 0
                    ? [NSString stringWithFormat:@"WHOIS %@: %@", target, reason]
                    : [NSString stringWithFormat:@"WHOIS %@: No such nick/channel", target];
                [self dispatchSystemMessage:message];
            }
        }
        else if ([code isEqualToString:@"321"]) {
            // RPL_LISTSTART - Channel list start
            // This marks the beginning of a LIST command response sequence:
            // 321 -> 322 (multiple) -> 323
            // Processing flow:
            // 1. Reset channel list caches (only if not already receiving)
            // 2. Set isReceivingChannelList = YES (protects 322 processing from other messages)
            // 3. Notify UI to create/show channel list window
            
            // Only reset if we're not already receiving a list (protect against multiple LIST commands)
            // This ensures that if other messages interrupt the LIST flow, we don't lose accumulated data
            BOOL shouldReset = !self.isReceivingChannelList;
            
            // Ensure arrays exist (should be initialized in init, but be safe)
            if (!self.serverChannelList) {
                IRCLog(@"IRCClient: WARNING - serverChannelList is nil, initializing");
                self.serverChannelList = [[NSMutableArray alloc] init];
            }
            if (!self.allChannelsList) {
                IRCLog(@"IRCClient: WARNING - allChannelsList is nil, initializing");
                self.allChannelsList = [[NSMutableArray alloc] init];
            }
            
            if (shouldReset) {
                @synchronized(self.serverChannelList) {
                    [self.serverChannelList removeAllObjects];
                }
                @synchronized(self.allChannelsList) {
                    [self.allChannelsList removeAllObjects];
                }
                self.channelList322Count = 0; // Reset counter
                IRCLog(@"IRCClient: Received 321 RPL_LISTSTART - Reset channel list caches (new LIST command)");
            } else {
                IRCLog(@"IRCClient: Received 321 RPL_LISTSTART - Already receiving list (isReceivingChannelList=YES), preserving cached data");
                IRCLog(@"IRCClient: Current cache state - serverChannelList: %lu, allChannelsList: %lu, 322 count: %lu", 
                      (unsigned long)self.serverChannelList.count, (unsigned long)self.allChannelsList.count, (unsigned long)self.channelList322Count);
            }
            
            // Mark that we're receiving a channel list (protects 322 processing)
            self.isReceivingChannelList = YES;
            
            id<IRCClientDelegate> delegate = self.delegate;
            IRCLog(@"IRCClient: Received 321 RPL_LISTSTART, resetting=%d, current thread: %@, delegate: %@", 
                  shouldReset, [NSThread isMainThread] ? @"main" : @"background", delegate ? @"set" : @"nil");
            dispatch_async(dispatch_get_main_queue(), ^{
                IRCLog(@"IRCClient: Dispatching 321 to main thread, delegate: %@", delegate ? @"set" : @"nil");
                if (delegate && [delegate respondsToSelector:@selector(ircClientDidReceiveChannelListStart:)]) {
                    IRCLog(@"IRCClient: Calling ircClientDidReceiveChannelListStart");
                    [delegate ircClientDidReceiveChannelListStart:self];
                } else {
                    IRCLog(@"IRCClient: ERROR - delegate is nil or doesn't respond to selector");
                }
            });
        }
        else if ([code isEqualToString:@"322"]) {
            // RPL_LIST - Channel list item
            // Format: ":server 322 nick #channel user_count :topic"
            // With new parser: parts[0]=":server", parts[1]="322", parts[2]="nick", parts[3]="#channel", parts[4]="user_count", parts[5]=":topic" (if exists)
            // Processing flow:
            // 1. Check if we're receiving a channel list (protected by isReceivingChannelList flag)
            // 2. Parse channel info (channel name, user count, topic)
            // 3. Cache to both serverChannelList (for batch sending) and allChannelsList (complete cache)
            // 4. Every 50 channels: send batch incrementally to UI (for performance)
            // 5. All channels cached in allChannelsList (protected from other messages)
            
            // Some servers don't send 321 (RPL_LISTSTART), they directly send 322 messages.
            // If we receive a 322 but isReceivingChannelList=NO, auto-initialize the channel list.
            if (!self.isReceivingChannelList) {
                IRCLog(@"IRCClient: Received 322 RPL_LIST but isReceivingChannelList=NO - auto-initializing (server may have skipped 321)");
                self.isReceivingChannelList = YES;
                self.channelList322Count = 0;
                
                // Initialize arrays
                if (!self.serverChannelList) {
                    self.serverChannelList = [[NSMutableArray alloc] init];
                } else {
                    @synchronized(self.serverChannelList) {
                        [self.serverChannelList removeAllObjects];
                    }
                }
                if (!self.allChannelsList) {
                    self.allChannelsList = [[NSMutableArray alloc] init];
                } else {
                    @synchronized(self.allChannelsList) {
                        [self.allChannelsList removeAllObjects];
                    }
                }
                
                // Notify UI to show channel list window
                id<IRCClientDelegate> delegate = self.delegate;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (delegate && [delegate respondsToSelector:@selector(ircClientDidReceiveChannelListStart:)]) {
                        [delegate ircClientDidReceiveChannelListStart:self];
                    }
                });
            }
            
            // Verify that allChannelsList exists
            if (!self.allChannelsList) {
                IRCLog(@"IRCClient: ERROR - allChannelsList is nil! Initializing now.");
                self.allChannelsList = [[NSMutableArray alloc] init];
            }
            
            // Accumulate channel info in serverChannelList (for batch sending) and allChannelsList (complete cache)
            IRCLog(@"IRCClient: Parsing 322 RPL_LIST - Original line: %@", line);
            IRCLog(@"IRCClient: Parsed parts count: %lu, parts: %@", (unsigned long)parts.count, parts);
            
            if (parts.count >= 5) {
                NSString *channel = parts.count > 3 ? parts[3] : @"";
                // Remove leading colon if present (shouldn't happen in RPL_LIST, but be safe)
                if ([channel hasPrefix:@":"]) {
                    channel = [channel substringFromIndex:1];
                }
                
                // Validate channel name - must not be empty
                if (!channel || channel.length == 0) {
                    IRCLog(@"IRCClient: ERROR - Channel name is empty! parts[3]='%@', parts=%@", parts.count > 3 ? parts[3] : @"<nil>", parts);
                    return;
                }
                
                // Parse user count - be lenient, just try to extract a number
                NSString *userCountStr = parts.count > 4 ? parts[4] : @"0";
                NSInteger userCount = [userCountStr integerValue];
                
                // Topic is the trailing part (starts with ':'), may contain spaces
                // In IRC protocol, trailing can be the last parameter if it starts with ':'
                NSString *topic = @"";
                if (parts.count > 5) {
                    // The trailing part is already correctly parsed and includes the ':'
                    NSString *trailing = parts[5];
                    if ([trailing hasPrefix:@":"]) {
                        topic = [trailing substringFromIndex:1];
                    } else {
                        // If no colon prefix, this might be a parameter, not trailing
                        // But in RPL_LIST, topic should always be trailing, so use it anyway
                        topic = trailing;
                    }
                    IRCLog(@"IRCClient: Extracted topic from trailing: '%@' (length: %lu)", topic, (unsigned long)topic.length);
                } else {
                    IRCLog(@"IRCClient: No trailing part found (parts.count=%lu), topic will be empty", (unsigned long)parts.count);
                }
                
                // Accumulate channel info (like Go code: c.serverChannelList = append(c.serverChannelList, info))
                NSDictionary *channelInfo = @{
                    @"channel": channel ?: @"",
                    @"userCount": @(userCount),
                    @"topic": topic ?: @""
                };
                
                NSArray *batchToSend = nil;
                NSUInteger allChannelsListCountBefore = 0;
                NSUInteger allChannelsListCountAfter = 0;
                
                @synchronized(self.serverChannelList) {
                    @synchronized(self.allChannelsList) {
                        // Track count before adding
                        allChannelsListCountBefore = self.allChannelsList.count;
                        
                        // Add to serverChannelList (for batch sending - cleared after each batch)
                        [self.serverChannelList addObject:channelInfo];
                        
                        // Add to allChannelsList (complete cache - never cleared until 323)
                        // This ensures ALL channels are preserved, even if other messages interrupt
                        [self.allChannelsList addObject:channelInfo];
                        
                        // Track count after adding
                        allChannelsListCountAfter = self.allChannelsList.count;
                        
                        // Verify that the channel was actually added
                        if (allChannelsListCountAfter != allChannelsListCountBefore + 1) {
                            IRCLog(@"IRCClient: ERROR - Failed to add channel to allChannelsList! Before: %lu, After: %lu", 
                                  (unsigned long)allChannelsListCountBefore, (unsigned long)allChannelsListCountAfter);
                            // Don't increment counter if add failed
                        } else {
                            // Only increment counter if channel was successfully added
                            self.channelList322Count++;
                        }
                        
                        // Performance optimization: Every 50 channels, send batch incrementally to UI
                        // This improves window drawing efficiency by reducing frequent updates
                        if (self.serverChannelList.count >= self.channelListBatchSize) {
                            batchToSend = [self.serverChannelList copy];
                            [self.serverChannelList removeAllObjects]; // Clear batch buffer, but allChannelsList keeps all
                        }
                    }
                }
                
                IRCLog(@"IRCClient: Accumulated 322 RPL_LIST #%lu - channel: '%@', users: %ld, topic: '%@' (length: %lu), pending batch: %lu, total cached: %lu (was %lu)", 
                      (unsigned long)self.channelList322Count, channel, (long)userCount, topic, (unsigned long)topic.length, 
                      (unsigned long)self.serverChannelList.count, (unsigned long)allChannelsListCountAfter, (unsigned long)allChannelsListCountBefore);
                
                // Send batch incrementally if threshold reached (50 channels)
                // This improves window drawing efficiency by reducing frequent updates
                if (batchToSend && batchToSend.count > 0) {
                    id<IRCClientDelegate> delegate = self.delegate;
                    IRCLog(@"IRCClient: Batch threshold reached (%lu channels), sending incrementally to UI for performance", (unsigned long)batchToSend.count);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // Use deprecated method for incremental updates (it supports incremental adding)
                        // This allows the UI to show channels as they arrive, improving user experience
                        if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveChannelListItem:userCount:topic:)]) {
                            for (NSDictionary *info in batchToSend) {
                                NSString *ch = info[@"channel"] ?: @"";
                                NSInteger count = [info[@"userCount"] integerValue];
                                NSString *top = info[@"topic"] ?: @"";
                                [delegate ircClient:self didReceiveChannelListItem:ch userCount:count topic:top];
                            }
                        }
                    });
                }
            } else {
                IRCLog(@"IRCClient: ERROR - Received 322 RPL_LIST with insufficient parts (count: %lu), parts: %@", (unsigned long)parts.count, parts);
                IRCLog(@"IRCClient: ERROR - This 322 message will NOT be added to allChannelsList, which may cause missing channels!");
                // Even if parsing fails, we should still increment the counter to track the issue
                // But we can't add invalid data to the list
            }
        }
        else if ([code isEqualToString:@"323"]) {
            // RPL_LISTEND - Channel list end
            // Processing flow:
            // 1. 321 (RPL_LISTSTART) -> Reset arrays, set isReceivingChannelList = YES
            // 2. 322 (RPL_LIST) -> Accumulate to serverChannelList and allChannelsList
            //    - Every 50 channels: send batch via didReceiveChannelListItem (incremental update)
            //    - All channels cached in allChannelsList (protected from other messages)
            // 3. 323 (RPL_LISTEND) -> Send complete list and trigger window redraw
            //    - Send completeChannelList via didReceiveChannelList (replaces all, triggers redraw)
            //    - This ensures ALL channels are displayed, even if other messages interrupted
            
            // Only process if we're actually receiving a channel list
            if (!self.isReceivingChannelList) {
                IRCLog(@"IRCClient: Received 323 RPL_LISTEND but not receiving channel list, ignoring");
                return;
            }
            
            // Mark that we're no longer receiving a channel list
            self.isReceivingChannelList = NO;
            
            // Get complete list of ALL channels (including all batches sent incrementally)
            // This ensures we have ALL channels that were received, even if other messages interrupted
            NSArray *completeChannelList = nil;
            NSArray *remainingChannels = nil;
            NSUInteger totalChannelsReceived = 0;
            
            @synchronized(self.serverChannelList) {
                @synchronized(self.allChannelsList) {
                    // Get remaining channels that haven't been sent yet (for backward compatibility)
                    if (self.serverChannelList.count > 0) {
                        remainingChannels = [self.serverChannelList copy];
                        [self.serverChannelList removeAllObjects];
                    }
                    
                    // Get complete list of ALL channels (including all batches)
                    // This is the critical cache: contains ALL channels received, regardless of interruptions
                    // IMPORTANT: allChannelsList should contain ALL channels, including:
                    // - Channels sent in batches (every 50)
                    // - Remaining channels (less than 50)
                    // - All channels received between 321 and 323
                    if (self.allChannelsList.count > 0) {
                        completeChannelList = [self.allChannelsList copy];
                        totalChannelsReceived = completeChannelList.count;
                        
                        // Verify that completeChannelList contains all channels
                        // remainingChannels should be a subset of completeChannelList
                        if (remainingChannels && remainingChannels.count > 0) {
                            NSUInteger remainingCount = remainingChannels.count;
                            IRCLog(@"IRCClient: Verification - remainingChannels (%lu) should be subset of completeChannelList (%lu)", 
                                  (unsigned long)remainingCount, (unsigned long)totalChannelsReceived);
                            
                            // Verify all remaining channels are in complete list
                            NSMutableSet *completeChannelNames = [NSMutableSet setWithCapacity:completeChannelList.count];
                            NSMutableSet *completeChannelInfoSet = [NSMutableSet setWithCapacity:completeChannelList.count];
                            
                            for (NSDictionary *info in completeChannelList) {
                                NSString *ch = info[@"channel"];
                                if (ch) {
                                    [completeChannelNames addObject:ch];
                                    // Also create a unique key combining channel name and user count for better verification
                                    NSString *uniqueKey = [NSString stringWithFormat:@"%@|%ld", ch, (long)[info[@"userCount"] integerValue]];
                                    [completeChannelInfoSet addObject:uniqueKey];
                                }
                            }
                            
                            // Check for duplicates in complete list
                            if (completeChannelNames.count != completeChannelList.count) {
                                IRCLog(@"IRCClient: WARNING - Found %lu duplicate channels in complete list! (total: %lu)", 
                                      (unsigned long)(completeChannelList.count - completeChannelNames.count), (unsigned long)completeChannelList.count);
                            }
                            
                            // Verify remaining channels are in complete list
                            NSUInteger missingCount = 0;
                            for (NSDictionary *info in remainingChannels) {
                                NSString *ch = info[@"channel"];
                                if (ch) {
                                    if (![completeChannelNames containsObject:ch]) {
                                        IRCLog(@"IRCClient: ERROR - remaining channel '%@' not found in complete list!", ch);
                                        missingCount++;
                                    }
                                }
                            }
                            
                            if (missingCount > 0) {
                                IRCLog(@"IRCClient: ERROR - %lu remaining channels are missing from complete list!", (unsigned long)missingCount);
                            }
                        }
                        
                        // Additional verification: check for duplicates in allChannelsList
                        NSMutableSet *allChannelNames = [NSMutableSet setWithCapacity:completeChannelList.count];
                        NSUInteger duplicateCount = 0;
                        for (NSDictionary *info in completeChannelList) {
                            NSString *ch = info[@"channel"];
                            if (ch) {
                                if ([allChannelNames containsObject:ch]) {
                                    duplicateCount++;
                                    IRCLog(@"IRCClient: WARNING - Duplicate channel found: '%@'", ch);
                                } else {
                                    [allChannelNames addObject:ch];
                                }
                            }
                        }
                        
                        if (duplicateCount > 0) {
                            IRCLog(@"IRCClient: WARNING - Found %lu duplicate channels in complete list!", (unsigned long)duplicateCount);
                        }
                        
                        // Log summary before clearing
                        IRCLog(@"IRCClient: 323 - About to clear allChannelsList. Final count: %lu channels", (unsigned long)self.allChannelsList.count);
                        
                        [self.allChannelsList removeAllObjects];
                    } else {
                        IRCLog(@"IRCClient: ERROR - allChannelsList is empty! This should not happen if 322 messages were received.");
                        IRCLog(@"IRCClient: ERROR - 322 count was %lu, but allChannelsList is empty!", (unsigned long)self.channelList322Count);
                    }
                }
            }
            
            IRCLog(@"IRCClient: 323 Processing Summary - 322 count: %lu, remaining: %lu, complete: %lu, total received: %lu", 
                  (unsigned long)self.channelList322Count,
                  (unsigned long)(remainingChannels ? remainingChannels.count : 0),
                  (unsigned long)(completeChannelList ? completeChannelList.count : 0),
                  (unsigned long)totalChannelsReceived);
            
            // CRITICAL VERIFICATION: The number of 322 messages should match the number of channels in allChannelsList
            if (self.channelList322Count != totalChannelsReceived) {
                IRCLog(@"IRCClient: ERROR - Mismatch! Received %lu 322 messages but allChannelsList has %lu channels!", 
                      (unsigned long)self.channelList322Count, (unsigned long)totalChannelsReceived);
            } else {
                IRCLog(@"IRCClient: Verification PASSED - 322 count (%lu) matches allChannelsList count (%lu)", 
                      (unsigned long)self.channelList322Count, (unsigned long)totalChannelsReceived);
            }
            
            // Reset counter for next LIST command
            self.channelList322Count = 0;
            
            id<IRCClientDelegate> delegate = self.delegate;
            IRCLog(@"IRCClient: Received 323 RPL_LISTEND - remaining: %lu, total cached: %lu channels, current thread: %@, delegate: %@", 
                  (unsigned long)(remainingChannels ? remainingChannels.count : 0),
                  (unsigned long)(completeChannelList ? completeChannelList.count : 0),
                  [NSThread isMainThread] ? @"main" : @"background", delegate ? @"set" : @"nil");
            
            dispatch_async(dispatch_get_main_queue(), ^{
                IRCLog(@"IRCClient: Dispatching 323 to main thread - remaining: %lu, total: %lu channels, delegate: %@", 
                      (unsigned long)(remainingChannels ? remainingChannels.count : 0),
                      (unsigned long)(completeChannelList ? completeChannelList.count : 0),
                      delegate ? @"set" : @"nil");
                
                // CRITICAL: Always send completeChannelList to ensure ALL channels are displayed
                // This replaces all channels in the window and triggers a full redraw
                // This is the authoritative source - it contains ALL channels received, regardless of interruptions
                // IMPORTANT: We ONLY send completeChannelList, NOT remainingChannels, because:
                // 1. completeChannelList already contains ALL channels (including remainingChannels)
                // 2. setChannelList: will clear and replace all channels anyway
                // 3. Sending remainingChannels would be redundant and could cause confusion
                if (completeChannelList && completeChannelList.count > 0) {
                    if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveChannelList:)]) {
                        IRCLog(@"IRCClient: Sending complete channel list with %lu channels - this will replace ALL channels and trigger window redraw", (unsigned long)completeChannelList.count);
                        
                        // Log first few and last few channels for debugging
                        if (completeChannelList.count > 0) {
                            NSInteger logCount = MIN(3, completeChannelList.count);
                            IRCLog(@"IRCClient: First %ld channels in complete list:", (long)logCount);
                            for (NSInteger i = 0; i < logCount; i++) {
                                NSDictionary *info = completeChannelList[i];
                                IRCLog(@"IRCClient:   [%ld] %@ (%ld users)", 
                                      (long)i, info[@"channel"], (long)[info[@"userCount"] integerValue]);
                            }
                            if (completeChannelList.count > 6) {
                                IRCLog(@"IRCClient: ... (total %lu channels, showing first 3)", (unsigned long)completeChannelList.count);
                                IRCLog(@"IRCClient: Last 3 channels in complete list:");
                                for (NSInteger i = completeChannelList.count - 3; i < completeChannelList.count; i++) {
                                    NSDictionary *info = completeChannelList[i];
                                    IRCLog(@"IRCClient:   [%ld] %@ (%ld users)", 
                                          (long)i, info[@"channel"], (long)[info[@"userCount"] integerValue]);
                                }
                            } else {
                                IRCLog(@"IRCClient: All %lu channels shown above", (unsigned long)completeChannelList.count);
                            }
                        }
                        
                        // Send complete list - this is the ONLY source of truth
                        [delegate ircClient:self didReceiveChannelList:completeChannelList];
                    } else {
                        IRCLog(@"IRCClient: ERROR - delegate doesn't respond to didReceiveChannelList:");
                    }
                } else {
                    IRCLog(@"IRCClient: ERROR - completeChannelList is empty or nil! This should not happen!");
                    IRCLog(@"IRCClient: ERROR - 322 count was %lu, but allChannelsList is empty", (unsigned long)self.channelList322Count);
                    
                    // Fallback: try to send remaining channels if complete list is empty
                    // This should never happen, but we provide a fallback for safety
                    if (remainingChannels && remainingChannels.count > 0) {
                        IRCLog(@"IRCClient: FALLBACK - sending %lu remaining channels as complete list (this indicates a bug!)", (unsigned long)remainingChannels.count);
                        if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveChannelList:)]) {
                            [delegate ircClient:self didReceiveChannelList:remainingChannels];
                        }
                    } else {
                        IRCLog(@"IRCClient: FATAL ERROR - Both completeChannelList and remainingChannels are empty!");
                    }
                }
                
                // Step 2: Notify end of channel list (for finalization/sorting)
                // NOTE: We do NOT send remainingChannels here because:
                // 1. completeChannelList already contains ALL channels (including remainingChannels)
                // 2. setChannelList: will clear and replace all channels anyway
                // 3. Sending remainingChannels would be redundant and could cause issues
                // This ensures the window is properly finalized and sorted
                if (delegate && [delegate respondsToSelector:@selector(ircClientDidReceiveChannelListEnd:)]) {
                    IRCLog(@"IRCClient: Calling ircClientDidReceiveChannelListEnd to finalize");
                    [delegate ircClientDidReceiveChannelListEnd:self];
                }
            });
        }
        else if ([code isEqualToString:@"364"]) {
            // RPL_LINKS - Server links list item
            // Format (RFC 2812): ":server 364 nick <mask> <server> :<hopcount> <info>"
            NSString *mask = @"";
            NSString *serverName = @"";
            if (parts.count >= 5) {
                mask = parts[3] ?: @"";
                serverName = parts[4] ?: @"";
            } else if (parts.count >= 4) {
                serverName = parts[3] ?: @"";
            }

            NSInteger trailingIndex = 5;
            if (parts.count >= 5 && [parts[4] hasPrefix:@":"]) {
                serverName = @"";
                trailingIndex = 4;
            }

            NSString *trailingText = @"";
            if (parts.count > trailingIndex) {
                trailingText = [[parts subarrayWithRange:NSMakeRange(trailingIndex, parts.count - trailingIndex)] componentsJoinedByString:@" "];
            }
            trailingText = [trailingText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([trailingText hasPrefix:@":"]) {
                trailingText = [trailingText substringFromIndex:1];
            }

            NSInteger hopCount = -1;
            NSString *info = @"";
            if (trailingText.length > 0) {
                NSScanner *scanner = [NSScanner scannerWithString:trailingText];
                if ([scanner scanInteger:&hopCount]) {
                    NSString *rest = [trailingText substringFromIndex:scanner.scanLocation];
                    info = [rest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                } else {
                    info = trailingText;
                }
            }

            id<IRCClientDelegate> delegate = self.delegate;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveLinksItemWithServer:mask:hopCount:info:)]) {
                    [delegate ircClient:self didReceiveLinksItemWithServer:serverName mask:mask hopCount:hopCount info:info];
                }
            });
        }
        else if ([code isEqualToString:@"365"]) {
            // RPL_ENDOFLINKS - End of server links list
            id<IRCClientDelegate> delegate = self.delegate;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (delegate && [delegate respondsToSelector:@selector(ircClientDidReceiveLinksEnd:)]) {
                    [delegate ircClientDidReceiveLinksEnd:self];
                }
            });
        }
        else if ([code isEqualToString:@"433"]) {
            // ERR_NICKNAMEINUSE - Nickname already in use (duplicate handler, but with retry logic)
            IRCLog(@"🔴 [LOGIN ERROR] 433 ERR_NICKNAMEINUSE - Attempting to retry with modified nickname");
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(ircClient:nicknameInUse:)]) {
                    [self.delegate ircClient:self nicknameInUse:self.config.nick];
                }
            });
            self.config.nick = [self.config.nick stringByAppendingString:@"_"];
            IRCLog(@"🔐 [LOGIN RETRY] Retrying with new nickname: %@", self.config.nick);
            [self sendRawCommand:[NSString stringWithFormat:@"NICK %@", self.config.nick]];
        }
        else if ([code isEqualToString:@"ERROR"]) {
            NSArray *errorParts = [parts subarrayWithRange:NSMakeRange(2, parts.count - 2)];
            NSString *errorMsg = [errorParts componentsJoinedByString:@" "];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(ircClient:didReceiveSystemMessage:)]) {
                    [self.delegate ircClient:self didReceiveSystemMessage:[NSString stringWithFormat:@"Server error: %@", errorMsg]];
                }
            });
        }
    }
    } @catch (NSException *exception) {
        // Log error but don't rethrow - ensure message processing continues
        // This is critical for LIST command processing where we receive many messages
        IRCLog(@"🔴 [HANDLE MESSAGE ERROR] Exception while handling message: %@", exception);
        IRCLog(@"🔴 [HANDLE MESSAGE ERROR] Message was: %@", line);
        IRCLog(@"🔴 [HANDLE MESSAGE ERROR] Stack trace: %@", [exception callStackSymbols]);
        // Don't rethrow - continue processing other messages
        // This ensures LIST command processing isn't interrupted by other messages
    }
}

- (void)authenticate {
    IRCLog(@"🔐🔐🔐 [LOGIN START] Starting login process to server: %@", self.config.server);
    IRCLog(@"🔐 [LOGIN INFO] Nick: %@, User: %@, RealName: %@", 
          self.config.nick, self.config.user, self.config.realName);
    
    if (self.config.password.length > 0) {
        IRCLog(@"🔐🔐🔐 [LOGIN COMMAND] → Sending PASS command to server");
        [self sendRawCommand:[NSString stringWithFormat:@"PASS %@", self.config.password]];
    } else {
        IRCLog(@"🔐 [LOGIN INFO] No password configured, skipping PASS command");
    }
    
    IRCLog(@"🔐🔐🔐 [LOGIN COMMAND] → Sending NICK command: %@", self.config.nick);
    [self sendRawCommand:[NSString stringWithFormat:@"NICK %@", self.config.nick]];
    
    NSString *userCommand = [NSString stringWithFormat:@"USER %@ 0 * :%@", self.config.user, self.config.realName];
    IRCLog(@"🔐🔐🔐 [LOGIN COMMAND] → Sending USER command: %@", userCommand);
    [self sendRawCommand:userCommand];
    
    IRCLog(@"🔐 [LOGIN INFO] All login commands sent, waiting for server response...");
}

- (void)joinChannel:(NSString *)channel {
    if (![channel hasPrefix:@"#"]) {
        channel = [@"#" stringByAppendingString:channel];
    }
    [self sendRawCommand:[NSString stringWithFormat:@"JOIN %@", channel]];
    // Request NAMES list after joining (some servers don't send it automatically)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), self.messageQueue, ^{
        [self sendRawCommand:[NSString stringWithFormat:@"NAMES %@", channel]];
    });
}

- (void)sendMessage:(NSString *)message toTarget:(NSString *)target {
    [self sendRawCommand:[NSString stringWithFormat:@"PRIVMSG %@ :%@", target, message]];
}

- (void)sendRawCommand:(NSString *)command {
    IRCLog(@"🟢 [CLIENT COMMAND] %@", command);
    
    // Check if streams are actually open (even if connected flag is not set)
    BOOL inputOpen = (self.inputStream && self.inputStream.streamStatus == NSStreamStatusOpen);
    BOOL outputOpen = (self.outputStream && self.outputStream.streamStatus == NSStreamStatusOpen);
    
    IRCLog(@"IRCClient: sendRawCommand called with: %@, connected=%d, inputStreamOpen=%d, outputStreamOpen=%d, outputStream=%@", 
          command, self.connected, inputOpen, outputOpen, self.outputStream ? @"set" : @"nil");
    
    if ((!self.connected && !outputOpen) || !self.outputStream) {
        IRCLog(@"🔴 [CLIENT ERROR] sendRawCommand ABORTED - connected=%d, outputOpen=%d, outputStream=%@", 
              self.connected, outputOpen, self.outputStream ? @"set" : @"nil");
        return;
    }
    
    // Update connected flag if streams are actually open
    if (!self.connected && inputOpen && outputOpen) {
        IRCLog(@"✅ [STREAM] Updating connected flag - streams are actually open");
        self.connected = YES;
        self.inputStreamOpen = YES;
        self.outputStreamOpen = YES;
    }
    
    // Log message on main thread
    id<IRCClientDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveLogMessage:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate ircClient:self didReceiveLogMessage:[NSString stringWithFormat:@"→ %@", command]];
        });
    } else {
        IRCLog(@"IRCClient: sendRawCommand - delegate is nil or doesn't respond to selector");
    }
    
    // Prepare data and write on stream thread
    NSString *commandWithNewline = [command stringByAppendingString:@"\r\n"];
    NSData *data = [commandWithNewline dataUsingEncoding:NSUTF8StringEncoding];
    
    // Write to stream on stream thread
    IRCLog(@"IRCClient: sendRawCommand - streamThread=%@, isExecuting=%d", 
          self.streamThread, self.streamThread.isExecuting);
    
    if (self.streamThread && self.streamThread.isExecuting) {
        IRCLog(@"IRCClient: Using performSelector to write on stream thread");
        [self performSelector:@selector(writeDataToStream:) onThread:self.streamThread withObject:data waitUntilDone:NO];
    } else {
        // Fallback if stream thread is not available
        IRCLog(@"IRCClient: Using fallback - writing directly to stream");
        if (self.outputStream && self.connected) {
            NSInteger bytesWritten = [self.outputStream write:data.bytes maxLength:data.length];
            if (bytesWritten < 0) {
                IRCLog(@"🔴 [CLIENT ERROR] Error writing to stream: %@", [self.outputStream streamError]);
            } else {
                IRCLog(@"✅ [CLIENT SUCCESS] Successfully wrote %ld bytes (fallback)", (long)bytesWritten);
            }
        } else {
            IRCLog(@"🔴 [CLIENT ERROR] Fallback ABORTED - outputStream=%@, connected=%d", 
                  self.outputStream ? @"set" : @"nil", self.connected);
        }
    }
}

- (void)writeDataToStream:(NSData *)data {
    NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    IRCLog(@"🟢 [CLIENT WRITE] Writing %lu bytes: %@", (unsigned long)data.length, 
          [dataStr stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\\r\\n"]);
    IRCLog(@"IRCClient: writeDataToStream called, data.length=%lu, connected=%d, outputStream=%@", 
          (unsigned long)data.length, self.connected, self.outputStream ? @"set" : @"nil");
    
    if (self.outputStream && self.connected) {
        NSInteger bytesWritten = [self.outputStream write:data.bytes maxLength:data.length];
        if (bytesWritten < 0) {
            IRCLog(@"🔴 [CLIENT ERROR] Error writing to stream: %@", [self.outputStream streamError]);
        } else {
            IRCLog(@"✅ [CLIENT SUCCESS] Successfully wrote %ld bytes to stream", (long)bytesWritten);
        }
    } else {
        IRCLog(@"🔴 [CLIENT ERROR] writeDataToStream ABORTED - connected=%d, outputStream=%@", 
              self.connected, self.outputStream ? @"set" : @"nil");
    }
}

- (void)run {
    // Message processing is handled by NSStream delegate methods
    // Streams are scheduled on the main run loop, so no need to run a separate loop
}

- (void)startPingTimer {
    // Ensure timer is created on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startPingTimer];
        });
        return;
    }
    
    if (self.pingTimer) {
        [self.pingTimer invalidate];
    }
    
    self.pingTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                      target:self
                                                    selector:@selector(sendPing)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)sendPing {
    [self sendRawCommand:[NSString stringWithFormat:@"PING %@", self.config.server]];
}

- (NSMutableDictionary *)pendingWhoisInfoForNick:(NSString *)nick {
    if (!nick || nick.length == 0) {
        return [[NSMutableDictionary alloc] init];
    }
    NSMutableDictionary *info = self.pendingWhoisInfo[nick];
    if (!info) {
        info = [[NSMutableDictionary alloc] init];
        info[@"nick"] = nick;
        self.pendingWhoisInfo[nick] = info;
    }
    return info;
}

- (NSString *)trailingTextFromParts:(NSArray<NSString *> *)parts startIndex:(NSInteger)startIndex {
    if (startIndex < 0 || startIndex >= parts.count) {
        return @"";
    }
    NSString *text = [[parts subarrayWithRange:NSMakeRange(startIndex, parts.count - startIndex)] componentsJoinedByString:@" "];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text hasPrefix:@":"]) {
        text = [text substringFromIndex:1];
    }
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)dispatchSystemMessage:(NSString *)message {
    if (!message || message.length == 0) {
        return;
    }
    id<IRCClientDelegate> delegate = self.delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (delegate && [delegate respondsToSelector:@selector(ircClient:didReceiveSystemMessage:)]) {
            [delegate ircClient:self didReceiveSystemMessage:message];
        }
    });
}

- (NSString *)extractNickFromPrefix:(NSString *)prefix {
    prefix = [prefix stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
    NSRange range = [prefix rangeOfString:@"!"];
    if (range.location != NSNotFound) {
        return [prefix substringToIndex:range.location];
    }
    return prefix;
}

// Extract message text from IRC numeric reply
// Format: :server 001 nick :Welcome message or :server 001 nick param1 param2 :message
// In IRC protocol, parameters starting with colon represent text messages that may contain spaces
- (NSString *)extractNumericReplyMessage:(NSArray<NSString *> *)parts {
    if (parts.count < 4) {
        return @"";
    }
    // Start from index 3 (skip :server, code, nick)
    // Find the part starting with colon (indicates start of text message)
    for (NSInteger i = 3; i < parts.count; i++) {
        NSString *part = parts[i];
        if ([part hasPrefix:@":"]) {
            // Extract content after colon and merge subsequent parts (may contain spaces)
            NSString *msg = [part substringFromIndex:1];
            if (i < parts.count - 1) {
                // If there are more parts, merge them (join with spaces)
                NSArray *remainingParts = [parts subarrayWithRange:NSMakeRange(i + 1, parts.count - i - 1)];
                msg = [msg stringByAppendingString:@" "];
                msg = [msg stringByAppendingString:[remainingParts componentsJoinedByString:@" "]];
            }
            return msg;
        }
    }
    // If no colon-prefixed part found, try returning the last parameter (some servers may not use colon)
    if (parts.count > 3) {
        NSString *lastPart = parts[parts.count - 1];
        // Remove colon if present
        if ([lastPart hasPrefix:@":"]) {
            return [lastPart substringFromIndex:1];
        }
        return lastPart;
    }
    return @"";
}

- (BOOL)isConnected {
    return _connected;
}

- (BOOL)isRegistered {
    return _registered;
}

- (BOOL)isJoined {
    return _joined;
}

@end
