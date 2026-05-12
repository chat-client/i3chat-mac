#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const LocalizationDidChangeNotification;

@interface LocalizationManager : NSObject

+ (instancetype)sharedManager;

- (NSString *)currentLanguageCode;
- (NSArray<NSString *> *)supportedLanguageCodes;
- (void)setLanguageCode:(NSString *)languageCode;
- (NSString *)localizedStringForKey:(NSString *)key defaultValue:(NSString *)defaultValue;

@end

static inline NSString *L(NSString *key, NSString *defaultValue) {
    return [[LocalizationManager sharedManager] localizedStringForKey:key defaultValue:defaultValue];
}

NS_ASSUME_NONNULL_END
