#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LinksListWindowController : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSWindowDelegate>

@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *links;

- (void)beginReceivingForServer:(NSString *)server;
- (void)addLinkWithServer:(NSString *)server mask:(NSString *)mask hopCount:(NSInteger)hopCount info:(NSString *)info;
- (void)finalizeLinks;
- (void)applyLocalization;

@end

NS_ASSUME_NONNULL_END
