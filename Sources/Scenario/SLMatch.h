#import "SLMessage.h"
NS_ASSUME_NONNULL_BEGIN
/// Matchers see the privacy-filtered request in both live and offline modes.
@interface SLMatch : NSObject
@property(nonatomic, readonly) NSDictionary *document;
- (instancetype)initWithDocument:(NSDictionary *)document;
- (BOOL)matches:(SLMessage *)request;
@end
NS_ASSUME_NONNULL_END
