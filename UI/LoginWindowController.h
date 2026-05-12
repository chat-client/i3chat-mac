//
//  LoginWindowController.h
//  i3Chat
//

#import <Cocoa/Cocoa.h>

@class IRCConfig;
@class LoginWindowController;

@protocol LoginWindowControllerDelegate <NSObject>

- (void)loginWindowController:(LoginWindowController *)controller didLoginWithConfigs:(NSArray<IRCConfig *> *)configs;

@end

@interface LoginWindowController : NSWindowController

@property (nonatomic, weak) id<LoginWindowControllerDelegate> delegate;
@property (nonatomic, strong, readonly) NSTextField *serverField;
@property (nonatomic, strong, readonly) NSTextField *nickField;
@property (nonatomic, strong, readonly) NSTextField *channelField;
@property (nonatomic, strong, readonly) NSTextField *realNameField;
@property (nonatomic, strong, readonly) NSSecureTextField *passwordField;
@property (nonatomic, strong, readonly) NSButton *savePasswordCheckbox;
@property (nonatomic, strong, readonly) NSButton *useTLSCheckbox;

- (instancetype)init;
- (instancetype)initWithServer:(NSString *)server
                          nick:(NSString *)nick
                       channel:(NSString *)channel
                      realName:(NSString *)realName
                      password:(NSString *)password
                  savePassword:(BOOL)savePassword
                        useTLS:(BOOL)useTLS;
- (void)applyLocalization;

@end
