#import "LocalizationManager.h"
#import "MessageStorage.h"
#import "StorageConstants.h"

NSString * const LocalizationDidChangeNotification = @"LocalizationDidChangeNotification";

// Legacy key for migration from NSUserDefaults
static NSString * const LocalizationLanguageDefaultsKey = @"LocalizationLanguageCode";

@interface LocalizationManager ()
@property (nonatomic, strong) NSBundle *languageBundle;
@property (nonatomic, assign) BOOL migrationChecked;
@end

@implementation LocalizationManager

+ (instancetype)sharedManager {
    static LocalizationManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[LocalizationManager alloc] init];
    });
    return manager;
}

- (NSArray<NSString *> *)supportedLanguageCodes {
    return @[@"en", @"zh-Hans"];
}

- (NSString *)normalizedLanguageCode:(NSString *)languageCode {
    if (languageCode.length == 0) {
        return @"en";
    }
    if ([languageCode hasPrefix:@"zh"]) {
        return @"zh-Hans";
    }
    return @"en";
}

- (void)migrateFromUserDefaultsIfNeeded {
    if (self.migrationChecked) {
        return;
    }
    self.migrationChecked = YES;
    
    // Check if already have data in SQLite
    NSString *sqliteValue = [[MessageStorage sharedStorage] getSettingForKey:kSettingLanguageCode];
    if (sqliteValue.length > 0) {
        return; // Already migrated
    }
    
    // Migrate from NSUserDefaults if exists
    NSString *legacyValue = [[NSUserDefaults standardUserDefaults] stringForKey:LocalizationLanguageDefaultsKey];
    if (legacyValue.length > 0) {
        [[MessageStorage sharedStorage] setSettingForKey:kSettingLanguageCode value:legacyValue];
        // Remove legacy value
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:LocalizationLanguageDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (NSString *)currentLanguageCode {
    [self migrateFromUserDefaultsIfNeeded];
    
    NSString *stored = [[MessageStorage sharedStorage] getSettingForKey:kSettingLanguageCode];
    if (stored.length > 0) {
        return [self normalizedLanguageCode:stored];
    }
    NSString *preferred = [[NSLocale preferredLanguages] firstObject] ?: @"en";
    return [self normalizedLanguageCode:preferred];
}

- (void)setLanguageCode:(NSString *)languageCode {
    NSString *normalized = [self normalizedLanguageCode:languageCode];
    if (![[self supportedLanguageCodes] containsObject:normalized]) {
        normalized = @"en";
    }
    if ([[self currentLanguageCode] isEqualToString:normalized]) {
        return;
    }
    [[MessageStorage sharedStorage] setSettingForKey:kSettingLanguageCode value:normalized];
    self.languageBundle = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:LocalizationDidChangeNotification object:nil];
}

- (NSBundle *)bundleForCurrentLanguage {
    if (self.languageBundle) {
        return self.languageBundle;
    }
    NSString *languageCode = [self currentLanguageCode];
    NSString *path = [[NSBundle mainBundle] pathForResource:languageCode ofType:@"lproj"];
    if (!path && ![languageCode isEqualToString:@"en"]) {
        path = [[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"];
    }
    if (path) {
        self.languageBundle = [NSBundle bundleWithPath:path];
        return self.languageBundle ?: [NSBundle mainBundle];
    }
    return [NSBundle mainBundle];
}

- (NSString *)localizedStringForKey:(NSString *)key defaultValue:(NSString *)defaultValue {
    NSBundle *bundle = [self bundleForCurrentLanguage];
    NSString *value = [bundle localizedStringForKey:key value:defaultValue table:@"Localizable"];
    if (value.length > 0) {
        return value;
    }
    return defaultValue.length > 0 ? defaultValue : key;
}

@end
