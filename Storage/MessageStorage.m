//
//  MessageStorage.m
//  i3Chat
//
//  Central storage for all application data using SQLite
//  Database location: ~/.i3chat/i3chat.db
//

#import "MessageStorage.h"
#import "StorageConstants.h"
#import <sqlite3.h>
#import <Foundation/Foundation.h>
#import "DebugLog.h"

@interface MessageStorage ()

@property (nonatomic, assign) sqlite3 *database;
@property (nonatomic, strong) dispatch_queue_t databaseQueue;

@end

@implementation MessageStorage

+ (instancetype)sharedStorage {
    static MessageStorage *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @try {
            instance = [[MessageStorage alloc] init];
        } @catch (NSException *exception) {
            SLog(@"Error creating MessageStorage: %@", exception);
        }
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _databaseQueue = dispatch_queue_create([kStorageQueueName UTF8String], DISPATCH_QUEUE_SERIAL);
        // Initialize database synchronously to ensure it's ready when LocalizationManager uses it
        dispatch_sync(_databaseQueue, ^{ [self initializeDatabase]; });
    }
    return self;
}

- (BOOL)initializeDatabase {
    @try {
        NSString *dbDir = StorageGetStorageDirectory();
        if (!dbDir) {
            SLog(@"Failed to get storage directory");
            return NO;
        }
        
        if (!StorageEnsureDirectoryExists(dbDir)) {
            SLog(@"Failed to create storage directory");
            return NO;
        }
        
        NSString *dbPath = StorageGetDatabasePath();
        SLog(@"Database path: %@", dbPath);
        
        const char *queueLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
        const char *dbQueueLabel = dispatch_queue_get_label(self.databaseQueue);
        BOOL isOnDatabaseQueue = (queueLabel && dbQueueLabel && strcmp(queueLabel, dbQueueLabel) == 0);
        
        __block BOOL success = NO;
        if (isOnDatabaseQueue) {
            @try {
                int result = sqlite3_open([dbPath UTF8String], &self->_database);
                if (result == SQLITE_OK) {
                    success = [self createTables];
                } else {
                    SLog(@"Failed to open database: %s", sqlite3_errmsg(self->_database));
                }
            } @catch (NSException *exception) {
                SLog(@"Exception in database initialization: %@", exception);
            }
        } else {
            dispatch_sync(self.databaseQueue, ^{
                @try {
                    int result = sqlite3_open([dbPath UTF8String], &self->_database);
                    if (result == SQLITE_OK) {
                        success = [self createTables];
                    } else {
                        SLog(@"Failed to open database: %s", sqlite3_errmsg(self->_database));
                    }
                } @catch (NSException *exception) {
                    SLog(@"Exception in database initialization: %@", exception);
                }
            });
        }
        
        return success;
    } @catch (NSException *exception) {
        SLog(@"Exception in initializeDatabase: %@", exception);
        return NO;
    }
}

- (BOOL)createTables {
    // Messages table
    const char *messagesSql = 
        "CREATE TABLE IF NOT EXISTS messages ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "window_key TEXT NOT NULL,"
        "sender TEXT NOT NULL,"
        "content TEXT NOT NULL,"
        "msg_type TEXT NOT NULL,"
        "timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,"
        "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_window_key ON messages(window_key);"
        "CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp);"
        "CREATE INDEX IF NOT EXISTS idx_window_timestamp ON messages(window_key, timestamp);";
    
    // Server history table
    const char *serverHistorySql =
        "CREATE TABLE IF NOT EXISTS server_history ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "server_address TEXT NOT NULL UNIQUE,"
        "nick TEXT,"
        "channel TEXT,"
        "realname TEXT,"
        "password TEXT,"
        "save_password INTEGER DEFAULT 0,"
        "use_tls INTEGER DEFAULT 0,"
        "last_connected DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,"
        "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_server_address ON server_history(server_address);"
        "CREATE INDEX IF NOT EXISTS idx_last_connected ON server_history(last_connected);";
    
    // Favorites table
    const char *favoritesSql =
        "CREATE TABLE IF NOT EXISTS favorites ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "type TEXT NOT NULL,"
        "content TEXT NOT NULL,"
        "server TEXT,"
        "channel TEXT,"
        "sender TEXT,"
        "timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,"
        "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_favorites_type ON favorites(type);"
        "CREATE INDEX IF NOT EXISTS idx_favorites_timestamp ON favorites(timestamp);";
    
    // Servers and channels configuration table (stores JSON blob)
    const char *serversChannelsSql =
        "CREATE TABLE IF NOT EXISTS servers_channels ("
        "id INTEGER PRIMARY KEY CHECK (id = 1),"
        "config_data TEXT NOT NULL,"
        "updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"
        ");";
    
    // Settings table (key-value store for app settings)
    const char *settingsSql =
        "CREATE TABLE IF NOT EXISTS settings ("
        "key TEXT PRIMARY KEY NOT NULL,"
        "value TEXT NOT NULL,"
        "updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"
        ");";
    
    char *errorMsg = NULL;
    
    // Create messages table
    int result = sqlite3_exec(self.database, messagesSql, NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        SLog(@"Failed to create messages table: %s", errorMsg);
        sqlite3_free(errorMsg);
        return NO;
    }
    
    // Create server history table
    result = sqlite3_exec(self.database, serverHistorySql, NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        SLog(@"Failed to create server_history table: %s", errorMsg);
        sqlite3_free(errorMsg);
        return NO;
    }
    
    // Create favorites table
    result = sqlite3_exec(self.database, favoritesSql, NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        SLog(@"Failed to create favorites table: %s", errorMsg);
        sqlite3_free(errorMsg);
        return NO;
    }
    
    // Create servers_channels table
    result = sqlite3_exec(self.database, serversChannelsSql, NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        SLog(@"Failed to create servers_channels table: %s", errorMsg);
        sqlite3_free(errorMsg);
        return NO;
    }
    
    // Create settings table
    result = sqlite3_exec(self.database, settingsSql, NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        SLog(@"Failed to create settings table: %s", errorMsg);
        sqlite3_free(errorMsg);
        return NO;
    }
    
    SLog(@"All database tables created successfully");
    return YES;
}

#pragma mark - Messages

- (BOOL)saveMessage:(Message *)message {
    __block BOOL success = NO;
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "INSERT INTO messages (window_key, sender, content, msg_type, timestamp) VALUES (?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [message.windowKey UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 2, [message.sender UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 3, [message.content UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 4, [message.msgType UTF8String], -1, NULL);
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
            NSString *timestampStr = [formatter stringFromDate:message.timestamp ?: [NSDate date]];
            sqlite3_bind_text(stmt, 5, [timestampStr UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
            } else {
                SLog(@"Failed to save message: %s", sqlite3_errmsg(self.database));
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return success;
}

- (NSArray<Message *> *)loadMessagesForWindowKey:(NSString *)windowKey limit:(NSInteger)limit {
    __block NSMutableArray<Message *> *messages = [[NSMutableArray alloc] init];
    
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "SELECT window_key, sender, content, msg_type, timestamp FROM messages WHERE window_key = ? ORDER BY timestamp ASC LIMIT ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [windowKey UTF8String], -1, NULL);
            sqlite3_bind_int64(stmt, 2, (sqlite3_int64)limit);
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *windowKeyStr = (const char *)sqlite3_column_text(stmt, 0);
                const char *senderStr = (const char *)sqlite3_column_text(stmt, 1);
                const char *contentStr = (const char *)sqlite3_column_text(stmt, 2);
                const char *msgTypeStr = (const char *)sqlite3_column_text(stmt, 3);
                const char *timestampStr = (const char *)sqlite3_column_text(stmt, 4);
                
                NSString *wk = windowKeyStr ? [NSString stringWithUTF8String:windowKeyStr] : @"";
                NSString *sender = senderStr ? [NSString stringWithUTF8String:senderStr] : @"";
                NSString *content = contentStr ? [NSString stringWithUTF8String:contentStr] : @"";
                NSString *msgType = msgTypeStr ? [NSString stringWithUTF8String:msgTypeStr] : @"";
                NSDate *timestamp = [formatter dateFromString:timestampStr ? [NSString stringWithUTF8String:timestampStr] : @""];
                if (!timestamp) {
                    timestamp = [NSDate date];
                }
                
                Message *msg = [[Message alloc] initWithWindowKey:wk sender:sender content:content msgType:msgType timestamp:timestamp];
                [messages addObject:msg];
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return messages;
}

- (NSArray<Message *> *)loadRecentMessagesForWindowKey:(NSString *)windowKey limit:(NSInteger)limit {
    __block NSMutableArray<Message *> *messages = [[NSMutableArray alloc] init];
    
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "SELECT window_key, sender, content, msg_type, timestamp FROM messages WHERE window_key = ? ORDER BY timestamp DESC LIMIT ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [windowKey UTF8String], -1, NULL);
            sqlite3_bind_int64(stmt, 2, (sqlite3_int64)limit);
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *windowKeyStr = (const char *)sqlite3_column_text(stmt, 0);
                const char *senderStr = (const char *)sqlite3_column_text(stmt, 1);
                const char *contentStr = (const char *)sqlite3_column_text(stmt, 2);
                const char *msgTypeStr = (const char *)sqlite3_column_text(stmt, 3);
                const char *timestampStr = (const char *)sqlite3_column_text(stmt, 4);
                
                NSString *wk = windowKeyStr ? [NSString stringWithUTF8String:windowKeyStr] : @"";
                NSString *sender = senderStr ? [NSString stringWithUTF8String:senderStr] : @"";
                NSString *content = contentStr ? [NSString stringWithUTF8String:contentStr] : @"";
                NSString *msgType = msgTypeStr ? [NSString stringWithUTF8String:msgTypeStr] : @"";
                NSDate *timestamp = [formatter dateFromString:timestampStr ? [NSString stringWithUTF8String:timestampStr] : @""];
                if (!timestamp) {
                    timestamp = [NSDate date];
                }
                
                Message *msg = [[Message alloc] initWithWindowKey:wk sender:sender content:content msgType:msgType timestamp:timestamp];
                [messages addObject:msg];
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return [[messages reverseObjectEnumerator] allObjects];
}

- (NSArray<Message *> *)searchMessagesForWindowKey:(NSString *)windowKey keyword:(NSString *)keyword limit:(NSInteger)limit {
    return [self searchMessagesForWindowKey:windowKey keyword:keyword startDate:nil endDate:nil limit:limit];
}

- (NSArray<Message *> *)searchMessagesForWindowKey:(NSString *)windowKey
                                           keyword:(NSString *)keyword
                                         startDate:(NSDate *)startDate
                                           endDate:(NSDate *)endDate
                                             limit:(NSInteger)limit {
    if (!windowKey || windowKey.length == 0) {
        return @[];
    }

    __block NSMutableArray<Message *> *messages = [[NSMutableArray alloc] init];

    dispatch_sync(self.databaseQueue, ^{
        // Build dynamic SQL based on provided parameters
        NSMutableString *sqlString = [NSMutableString stringWithString:
            @"SELECT window_key, sender, content, msg_type, timestamp "
            @"FROM messages "
            @"WHERE window_key = ?"];
        
        NSMutableArray *bindValues = [[NSMutableArray alloc] init];
        [bindValues addObject:windowKey];
        
        // Add keyword filter if provided
        BOOL hasKeyword = (keyword && keyword.length > 0);
        if (hasKeyword) {
            [sqlString appendString:@" AND (content LIKE ? OR sender LIKE ?)"];
            NSString *pattern = [NSString stringWithFormat:@"%%%@%%", keyword];
            [bindValues addObject:pattern];
            [bindValues addObject:pattern];
        }
        
        // Add date range filter if provided
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        
        if (startDate) {
            [sqlString appendString:@" AND timestamp >= ?"];
            [bindValues addObject:[formatter stringFromDate:startDate]];
        }
        
        if (endDate) {
            // Add one day to end date to include the entire day
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSDate *nextDay = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:endDate options:0];
            [sqlString appendString:@" AND timestamp < ?"];
            [bindValues addObject:[formatter stringFromDate:nextDay]];
        }
        
        [sqlString appendString:@" ORDER BY timestamp DESC LIMIT ?"];
        
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(self.database, [sqlString UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            // Bind all values
            int bindIndex = 1;
            for (id value in bindValues) {
                sqlite3_bind_text(stmt, bindIndex++, [value UTF8String], -1, NULL);
            }
            sqlite3_bind_int64(stmt, bindIndex, (sqlite3_int64)limit);
            
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *windowKeyStr = (const char *)sqlite3_column_text(stmt, 0);
                const char *senderStr = (const char *)sqlite3_column_text(stmt, 1);
                const char *contentStr = (const char *)sqlite3_column_text(stmt, 2);
                const char *msgTypeStr = (const char *)sqlite3_column_text(stmt, 3);
                const char *timestampStr = (const char *)sqlite3_column_text(stmt, 4);

                NSString *wk = windowKeyStr ? [NSString stringWithUTF8String:windowKeyStr] : @"";
                NSString *sender = senderStr ? [NSString stringWithUTF8String:senderStr] : @"";
                NSString *content = contentStr ? [NSString stringWithUTF8String:contentStr] : @"";
                NSString *msgType = msgTypeStr ? [NSString stringWithUTF8String:msgTypeStr] : @"";
                NSDate *timestamp = [formatter dateFromString:timestampStr ? [NSString stringWithUTF8String:timestampStr] : @""];
                if (!timestamp) {
                    timestamp = [NSDate date];
                }

                Message *msg = [[Message alloc] initWithWindowKey:wk sender:sender content:content msgType:msgType timestamp:timestamp];
                [messages addObject:msg];
            }

            sqlite3_finalize(stmt);
        }
    });

    return messages;
}

- (BOOL)deleteMessagesForWindowKey:(NSString *)windowKey {
    __block BOOL success = NO;
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "DELETE FROM messages WHERE window_key = ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [windowKey UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return success;
}

- (NSArray<NSString *> *)getWindowList {
    __block NSMutableArray<NSString *> *windows = [[NSMutableArray alloc] init];
    
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "SELECT DISTINCT window_key FROM messages ORDER BY MAX(timestamp) DESC";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *windowKeyStr = (const char *)sqlite3_column_text(stmt, 0);
                if (windowKeyStr) {
                    [windows addObject:[NSString stringWithUTF8String:windowKeyStr]];
                }
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return windows;
}

- (NSInteger)getMessageCountForWindowKey:(NSString *)windowKey {
    __block NSInteger count = 0;
    
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "SELECT COUNT(*) FROM messages WHERE window_key = ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [windowKey UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                count = sqlite3_column_int(stmt, 0);
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return count;
}

#pragma mark - Favorites

- (BOOL)saveFavoriteItem:(NSDictionary *)item {
    if (!item) return NO;
    
    __block BOOL success = NO;
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "INSERT INTO favorites (type, content, server, channel, sender, timestamp) VALUES (?, ?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *type = item[@"type"] ?: @"message";
            NSString *content = item[@"content"] ?: @"";
            NSString *server = item[@"server"] ?: @"";
            NSString *channel = item[@"channel"] ?: @"";
            NSString *sender = item[@"sender"] ?: @"";
            
            sqlite3_bind_text(stmt, 1, [type UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 2, [content UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 3, [server UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 4, [channel UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 5, [sender UTF8String], -1, NULL);
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            NSDate *timestamp = item[@"timestamp"] ?: [NSDate date];
            if ([timestamp isKindOfClass:[NSString class]]) {
                timestamp = [formatter dateFromString:(NSString *)timestamp] ?: [NSDate date];
            }
            NSString *timestampStr = [formatter stringFromDate:timestamp];
            sqlite3_bind_text(stmt, 6, [timestampStr UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
                SLog(@"Favorite saved successfully: %@", content);
            } else {
                SLog(@"Failed to save favorite: %s", sqlite3_errmsg(self.database));
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return success;
}

- (NSArray<NSDictionary *> *)loadAllFavorites {
    __block NSMutableArray<NSDictionary *> *favorites = [[NSMutableArray alloc] init];
    
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "SELECT id, type, content, server, channel, sender, timestamp FROM favorites ORDER BY timestamp DESC";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                NSInteger itemId = sqlite3_column_int64(stmt, 0);
                const char *typeStr = (const char *)sqlite3_column_text(stmt, 1);
                const char *contentStr = (const char *)sqlite3_column_text(stmt, 2);
                const char *serverStr = (const char *)sqlite3_column_text(stmt, 3);
                const char *channelStr = (const char *)sqlite3_column_text(stmt, 4);
                const char *senderStr = (const char *)sqlite3_column_text(stmt, 5);
                const char *timestampStr = (const char *)sqlite3_column_text(stmt, 6);
                
                NSMutableDictionary *item = [NSMutableDictionary dictionary];
                item[@"id"] = @(itemId);
                item[@"type"] = typeStr ? [NSString stringWithUTF8String:typeStr] : @"message";
                item[@"content"] = contentStr ? [NSString stringWithUTF8String:contentStr] : @"";
                item[@"server"] = serverStr ? [NSString stringWithUTF8String:serverStr] : @"";
                item[@"channel"] = channelStr ? [NSString stringWithUTF8String:channelStr] : @"";
                item[@"sender"] = senderStr ? [NSString stringWithUTF8String:senderStr] : @"";
                
                NSDate *timestamp = nil;
                if (timestampStr) {
                    timestamp = [formatter dateFromString:[NSString stringWithUTF8String:timestampStr]];
                }
                item[@"timestamp"] = timestamp ?: [NSDate date];
                
                [favorites addObject:item];
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    SLog(@"Loaded %lu favorites from database", (unsigned long)favorites.count);
    return favorites;
}

- (BOOL)deleteFavoriteById:(NSInteger)favoriteId {
    if (favoriteId <= 0) {
        return NO;
    }
    
    __block BOOL success = NO;
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "DELETE FROM favorites WHERE id = ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, favoriteId);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
                SLog(@"Deleted favorite with id: %ld", (long)favoriteId);
            } else {
                SLog(@"Failed to delete favorite: %s", sqlite3_errmsg(self.database));
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return success;
}

- (BOOL)deleteAllFavorites {
    __block BOOL success = NO;
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "DELETE FROM favorites";
        char *errorMsg = NULL;
        
        if (sqlite3_exec(self.database, sql, NULL, NULL, &errorMsg) == SQLITE_OK) {
            success = YES;
        } else {
            SLog(@"Failed to delete all favorites: %s", errorMsg);
            sqlite3_free(errorMsg);
        }
    });
    
    return success;
}

#pragma mark - Servers and Channels Configuration

- (BOOL)saveServersChannelsConfig:(NSDictionary *)config {
    if (!config) return NO;
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config options:0 error:&error];
    if (!jsonData) {
        SLog(@"Failed to serialize servers/channels config: %@", error);
        return NO;
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    __block BOOL success = NO;
    dispatch_sync(self.databaseQueue, ^{
        // Use INSERT OR REPLACE to update the single row (id=1)
        const char *sql = "INSERT OR REPLACE INTO servers_channels (id, config_data, updated_at) VALUES (1, ?, datetime('now'))";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [jsonString UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
                SLog(@"Servers/channels config saved successfully");
            } else {
                SLog(@"Failed to save servers/channels config: %s", sqlite3_errmsg(self.database));
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return success;
}

- (NSDictionary *)loadServersChannelsConfig {
    __block NSDictionary *config = nil;
    
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "SELECT config_data FROM servers_channels WHERE id = 1";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *jsonStr = (const char *)sqlite3_column_text(stmt, 0);
                if (jsonStr) {
                    NSData *jsonData = [[NSString stringWithUTF8String:jsonStr] dataUsingEncoding:NSUTF8StringEncoding];
                    NSError *error = nil;
                    config = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
                    if (error) {
                        SLog(@"Failed to parse servers/channels config: %@", error);
                        config = nil;
                    }
                }
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return config;
}

#pragma mark - Settings

- (NSString *)getSettingForKey:(NSString *)key {
    if (!key || key.length == 0) {
        return nil;
    }
    
    SLog(@"getSettingForKey: %@", key);
    __block NSString *value = nil;
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "SELECT value FROM settings WHERE key = ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [key UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *valueStr = (const char *)sqlite3_column_text(stmt, 0);
                if (valueStr) {
                    value = [NSString stringWithUTF8String:valueStr];
                }
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return value;
}

- (BOOL)setSettingForKey:(NSString *)key value:(NSString *)value {
    if (!key || key.length == 0) {
        return NO;
    }
    
    __block BOOL success = NO;
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, datetime('now'))";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [key UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 2, [value ? value : @"" UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
            } else {
                SLog(@"Failed to set setting for key %@: %s", key, sqlite3_errmsg(self.database));
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return success;
}

- (BOOL)deleteSettingForKey:(NSString *)key {
    if (!key || key.length == 0) {
        return NO;
    }
    
    __block BOOL success = NO;
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "DELETE FROM settings WHERE key = ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [key UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
            } else {
                SLog(@"Failed to delete setting for key %@: %s", key, sqlite3_errmsg(self.database));
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return success;
}

- (NSDictionary *)getAllSettings {
    __block NSMutableDictionary *settings = [[NSMutableDictionary alloc] init];
    
    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "SELECT key, value FROM settings";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *keyStr = (const char *)sqlite3_column_text(stmt, 0);
                const char *valueStr = (const char *)sqlite3_column_text(stmt, 1);
                
                if (keyStr && valueStr) {
                    NSString *key = [NSString stringWithUTF8String:keyStr];
                    NSString *value = [NSString stringWithUTF8String:valueStr];
                    settings[key] = value;
                }
            }
            
            sqlite3_finalize(stmt);
        }
    });
    
    return settings;
}

- (void)dealloc {
    if (self.database) {
        sqlite3_close(self.database);
    }
}

@end

@implementation Message

- (instancetype)initWithWindowKey:(NSString *)windowKey
                            sender:(NSString *)sender
                           content:(NSString *)content
                           msgType:(NSString *)msgType
                         timestamp:(NSDate *)timestamp {
    self = [super init];
    if (self) {
        _windowKey = windowKey;
        _sender = sender;
        _content = content;
        _msgType = msgType;
        _timestamp = timestamp ?: [NSDate date];
    }
    return self;
}

@end
