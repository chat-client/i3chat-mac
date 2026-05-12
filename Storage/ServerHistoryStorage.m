//
//  ServerHistoryStorage.m
//  i3Chat
//

#import "ServerHistoryStorage.h"
#import "StorageConstants.h"
#import "MessageStorage.h"
#import <sqlite3.h>
#import <Foundation/Foundation.h>
#import "DebugLog.h"

NSString * const ServerHistoryDidUpdateNotification = @"ServerHistoryDidUpdateNotification";

@implementation LoginInfo
@end

@interface ServerHistoryStorage ()

@property (nonatomic, assign) sqlite3 *database;
@property (nonatomic, strong) dispatch_queue_t databaseQueue;

@end

@implementation ServerHistoryStorage

+ (instancetype)sharedStorage {
    static ServerHistoryStorage *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @try {
            instance = [[ServerHistoryStorage alloc] init];
        } @catch (NSException *exception) {
            SLog(@"Error creating ServerHistoryStorage: %@", exception);
        }
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Don't access MessageStorage here to avoid circular dependency
        _databaseQueue = dispatch_queue_create("com.i3chat.serverhistory", DISPATCH_QUEUE_SERIAL);
        // Don't initialize database immediately - wait until first use
        // This avoids crashes during app startup
        _database = NULL;
    }
    return self;
}

- (void)ensureDatabaseInitialized {
    if (_database == NULL) {
        SLog(@"ensureDatabaseInitialized: Database is NULL, initializing...");
        // Initialize database synchronously to ensure it's ready before use
        dispatch_sync(_databaseQueue, ^{
            if (self->_database == NULL) {
                [self initializeDatabaseSync];
            }
        });
        SLog(@"ensureDatabaseInitialized: After init, database is %@", self->_database ? @"valid" : @"NULL");
    }
}

- (void)initializeDatabaseSync {
    @try {
        // Ensure storage directory exists
        NSString *dbDir = StorageGetStorageDirectory();
        if (!dbDir) {
            SLog(@"ServerHistoryStorage: Failed to get storage directory");
            return;
        }
        
        if (!StorageEnsureDirectoryExists(dbDir)) {
            SLog(@"ServerHistoryStorage: Failed to create storage directory");
            return;
        }
        
        NSString *dbPath = StorageGetDatabasePath();
        if (!dbPath) {
            SLog(@"ServerHistoryStorage: Failed to get database path");
            return;
        }
        
        SLog(@"ServerHistoryStorage: Opening database at %@", dbPath);
        int result = sqlite3_open([dbPath UTF8String], &_database);
        if (result != SQLITE_OK) {
            SLog(@"ServerHistoryStorage: Failed to open database: %s", sqlite3_errmsg(_database));
            _database = NULL;
        } else {
            SLog(@"ServerHistoryStorage: Database opened successfully");
            // Ensure server_history table exists
            [self createServerHistoryTable];
        }
    } @catch (NSException *exception) {
        SLog(@"ServerHistoryStorage: Exception in initializeDatabaseSync: %@", exception);
    }
}

- (void)createServerHistoryTable {
    if (!_database) {
        return;
    }
    
    const char *sql = "CREATE TABLE IF NOT EXISTS server_history ("
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
    
    char *errorMsg = NULL;
    int result = sqlite3_exec(_database, sql, NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        SLog(@"ServerHistoryStorage: Failed to create server_history table: %s", errorMsg);
        sqlite3_free(errorMsg);
    } else {
        SLog(@"ServerHistoryStorage: server_history table created/verified");
    }
}

- (BOOL)initializeDatabase {
    @try {
        // Database is already initialized by MessageStorage
        // We just need to get a reference to it
        // For simplicity, we'll use the same database path
        NSString *dbPath = StorageGetDatabasePath();
        if (!dbPath) {
            SLog(@"Failed to get database path");
            return NO;
        }
        
        // Check if we're already on the database queue to avoid deadlock
        const char *queueLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
        const char *dbQueueLabel = dispatch_queue_get_label(self.databaseQueue);
        BOOL isOnDatabaseQueue = (queueLabel && dbQueueLabel && strcmp(queueLabel, dbQueueLabel) == 0);
        
        __block BOOL success = NO;
        if (isOnDatabaseQueue) {
            // Already on the queue, execute directly
            @try {
                int result = sqlite3_open([dbPath UTF8String], &self->_database);
                if (result == SQLITE_OK) {
                    success = YES;
                } else {
                    SLog(@"Failed to open database: %s", sqlite3_errmsg(self->_database));
                }
            } @catch (NSException *exception) {
                SLog(@"Exception in database open: %@", exception);
            }
        } else {
            // Use async dispatch to avoid deadlock
            dispatch_async(self.databaseQueue, ^{
                @try {
                    int result = sqlite3_open([dbPath UTF8String], &self->_database);
                    if (result != SQLITE_OK) {
                        SLog(@"Failed to open database: %s", sqlite3_errmsg(self->_database));
                    }
                } @catch (NSException *exception) {
                    SLog(@"Exception in database open: %@", exception);
                }
            });
            // Return YES immediately, database will be opened asynchronously
            success = YES;
        }
        
        return success;
    } @catch (NSException *exception) {
        SLog(@"Exception in initializeDatabase: %@", exception);
        return NO;
    }
}

- (BOOL)saveLoginHistoryWithServer:(NSString *)server
                               nick:(nullable NSString *)nick
                            channel:(nullable NSString *)channel
                           realName:(nullable NSString *)realName
                           password:(nullable NSString *)password
                       savePassword:(BOOL)savePassword
                             useTLS:(BOOL)useTLS {
    SLog(@"saveLoginHistoryWithServer: Saving server %@", server);
    // Ensure database is initialized before use
    [self ensureDatabaseInitialized];

    __block BOOL success = NO;
    
    dispatch_sync(self.databaseQueue, ^{
        if (!self.database) {
            SLog(@"saveLoginHistoryWithServer: Database is NULL");
            return;
        }
        
        const char *sql = "INSERT INTO server_history (server_address, nick, channel, realname, password, save_password, use_tls, last_connected) "
                          "VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
                          "ON CONFLICT(server_address) DO UPDATE SET "
                          "nick = excluded.nick, "
                          "channel = excluded.channel, "
                          "realname = excluded.realname, "
                          "password = excluded.password, "
                          "save_password = excluded.save_password, "
                          "use_tls = excluded.use_tls, "
                          "last_connected = excluded.last_connected";
        
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [server UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 2, nick ? [nick UTF8String] : NULL, -1, NULL);
            sqlite3_bind_text(stmt, 3, channel ? [channel UTF8String] : NULL, -1, NULL);
            sqlite3_bind_text(stmt, 4, realName ? [realName UTF8String] : NULL, -1, NULL);
            
            // Only save password if savePassword is YES and password is not empty
            if (savePassword && password.length > 0) {
                sqlite3_bind_text(stmt, 5, [password UTF8String], -1, NULL);
            } else {
                sqlite3_bind_null(stmt, 5);
            }
            
            sqlite3_bind_int(stmt, 6, savePassword ? 1 : 0);
            sqlite3_bind_int(stmt, 7, useTLS ? 1 : 0);
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            NSString *timestampStr = [formatter stringFromDate:[NSDate date]];
            sqlite3_bind_text(stmt, 8, [timestampStr UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
                SLog(@"saveLoginHistoryWithServer: Successfully saved server %@", server);
            } else {
                SLog(@"Failed to save login history: %s", sqlite3_errmsg(self.database));
            }
            
            sqlite3_finalize(stmt);
        } else {
            SLog(@"saveLoginHistoryWithServer: Failed to prepare statement: %s", sqlite3_errmsg(self.database));
        }
    });
    
    if (success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ServerHistoryDidUpdateNotification
                                                                object:self
                                                              userInfo:@{@"server": server ?: @""}];
        });
    }

    return success;
}

- (BOOL)touchLoginHistoryWithServer:(NSString *)server
                               nick:(nullable NSString *)nick
                            channel:(nullable NSString *)channel
                           realName:(nullable NSString *)realName
                             useTLS:(BOOL)useTLS {
    // Ensure database is initialized before use
    [self ensureDatabaseInitialized];

    __block BOOL success = NO;

    dispatch_sync(self.databaseQueue, ^{
        const char *sql = "INSERT INTO server_history (server_address, nick, channel, realname, password, save_password, use_tls, last_connected) "
                          "VALUES (?, ?, ?, ?, NULL, 0, ?, ?) "
                          "ON CONFLICT(server_address) DO UPDATE SET "
                          "nick = excluded.nick, "
                          "channel = excluded.channel, "
                          "realname = excluded.realname, "
                          "use_tls = excluded.use_tls, "
                          "last_connected = excluded.last_connected";

        sqlite3_stmt *stmt;

        if (!self.database) {
            SLog(@"touchLoginHistoryWithServer: Database is NULL");
            return;
        }
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [server UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 2, nick ? [nick UTF8String] : NULL, -1, NULL);
            sqlite3_bind_text(stmt, 3, channel ? [channel UTF8String] : NULL, -1, NULL);
            sqlite3_bind_text(stmt, 4, realName ? [realName UTF8String] : NULL, -1, NULL);
            sqlite3_bind_int(stmt, 5, useTLS ? 1 : 0);

            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            NSString *timestampStr = [formatter stringFromDate:[NSDate date]];
            sqlite3_bind_text(stmt, 6, [timestampStr UTF8String], -1, NULL);

            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
                SLog(@"touchLoginHistoryWithServer: Successfully saved server %@", server);
            } else {
                SLog(@"Failed to touch login history: %s", sqlite3_errmsg(self.database));
            }

            sqlite3_finalize(stmt);
        } else {
            SLog(@"Failed to prepare statement for touchLoginHistoryWithServer: %s", sqlite3_errmsg(self.database));
        }
    });

    if (success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ServerHistoryDidUpdateNotification
                                                                object:self
                                                              userInfo:@{@"server": server ?: @""}];
        });
    }

    return success;
}

- (nullable LoginInfo *)getLastLoginInfo {
    // Ensure database is initialized before use
    [self ensureDatabaseInitialized];
    
    __block LoginInfo *info = nil;
    
    // Use async dispatch with semaphore to avoid deadlock
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(self.databaseQueue, ^{
        const char *sql = "SELECT server_address, nick, channel, realname, password, save_password, use_tls "
                          "FROM server_history "
                          "ORDER BY last_connected DESC LIMIT 1";
        
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                info = [[LoginInfo alloc] init];
                
                const char *serverStr = (const char *)sqlite3_column_text(stmt, 0);
                const char *nickStr = (const char *)sqlite3_column_text(stmt, 1);
                const char *channelStr = (const char *)sqlite3_column_text(stmt, 2);
                const char *realNameStr = (const char *)sqlite3_column_text(stmt, 3);
                const char *passwordStr = (const char *)sqlite3_column_text(stmt, 4);
                int savePasswordInt = sqlite3_column_int(stmt, 5);
                int useTLSInt = sqlite3_column_int(stmt, 6);
                
                info.server = serverStr ? [NSString stringWithUTF8String:serverStr] : @"";
                info.nick = nickStr ? [NSString stringWithUTF8String:nickStr] : nil;
                info.channel = channelStr ? [NSString stringWithUTF8String:channelStr] : nil;
                info.realName = realNameStr ? [NSString stringWithUTF8String:realNameStr] : nil;
                
                if (savePasswordInt == 1 && passwordStr) {
                    info.password = [NSString stringWithUTF8String:passwordStr];
                    info.savePassword = YES;
                } else {
                    info.password = nil;
                    info.savePassword = NO;
                }
                
                info.useTLS = (useTLSInt == 1);
            }
            
            sqlite3_finalize(stmt);
        }
        
        dispatch_semaphore_signal(semaphore);
    });
    
    // Wait for completion with timeout (5 seconds)
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        SLog(@"Timeout waiting for getLastLoginInfo");
        return nil;
    }
    
    return info;
}

- (NSArray<NSString *> *)getServerHistoryWithLimit:(NSInteger)limit {
    // Ensure database is initialized before use
    [self ensureDatabaseInitialized];

    __block NSMutableArray<NSString *> *servers = [[NSMutableArray alloc] init];
    
    dispatch_sync(self.databaseQueue, ^{
        if (!self.database) {
            SLog(@"getServerHistoryWithLimit: Database is NULL");
            return;
        }
        
        const char *sql = "SELECT server_address FROM server_history ORDER BY last_connected DESC LIMIT ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, (sqlite3_int64)limit);
            
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *serverStr = (const char *)sqlite3_column_text(stmt, 0);
                if (serverStr) {
                    [servers addObject:[NSString stringWithUTF8String:serverStr]];
                }
            }
            
            sqlite3_finalize(stmt);
            SLog(@"getServerHistoryWithLimit: Found %lu servers", (unsigned long)servers.count);
        } else {
            SLog(@"getServerHistoryWithLimit: Failed to prepare statement: %s", sqlite3_errmsg(self.database));
        }
    });
    
    return servers;
}

- (BOOL)deleteServerFromHistory:(NSString *)server {
    if (!server || server.length == 0) {
        return NO;
    }
    
    [self ensureDatabaseInitialized];
    
    __block BOOL success = NO;
    
    dispatch_sync(self.databaseQueue, ^{
        if (!self.database) {
            SLog(@"deleteServerFromHistory: Database is NULL");
            return;
        }
        
        const char *sql = "DELETE FROM server_history WHERE server_address = ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(self.database, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [server UTF8String], -1, NULL);
            
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                success = YES;
                SLog(@"deleteServerFromHistory: Successfully deleted server %@", server);
            } else {
                SLog(@"deleteServerFromHistory: Failed to delete: %s", sqlite3_errmsg(self.database));
            }
            
            sqlite3_finalize(stmt);
        } else {
            SLog(@"deleteServerFromHistory: Failed to prepare statement: %s", sqlite3_errmsg(self.database));
        }
    });
    
    if (success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ServerHistoryDidUpdateNotification
                                                                object:self
                                                              userInfo:@{@"server": server, @"action": @"delete"}];
        });
    }
    
    return success;
}

- (void)dealloc {
    if (self.database) {
        sqlite3_close(self.database);
    }
}

@end
