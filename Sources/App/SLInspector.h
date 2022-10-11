#import <AppKit/AppKit.h>
#import "SLFixture.h"
#import "SLScenario.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLInspector : NSView
- (void)showFixture:(SLFixture *)fixture scenario:(SLScenario *)scenario;
- (void)showReceipt:(NSDictionary *)receipt;
- (void)showOverview:(NSDictionary *)overview;
- (void)showEmpty;
@end
NS_ASSUME_NONNULL_END
