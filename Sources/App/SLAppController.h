#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface SLAppController : NSObject <NSApplicationDelegate,
                                       NSWindowDelegate,
                                       NSTableViewDataSource,
                                       NSTableViewDelegate,
                                       NSSearchFieldDelegate>
@end
NS_ASSUME_NONNULL_END
