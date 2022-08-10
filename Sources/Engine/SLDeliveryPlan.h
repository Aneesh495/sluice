#import "SLScenario.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLDeliveryPlan : NSObject
@property(nonatomic, readonly) NSData *wire;
@property(nonatomic, readonly) NSDictionary *summary;
@property(nonatomic, readonly) NSUInteger segmentCount;
@property(nonatomic, readonly) uint64_t delayUS;
@property(nonatomic, readonly) uint64_t durationUS;
@property(nonatomic, readonly) SLMessage *response;
- (instancetype)initResponse:(SLMessage *)response request:(SLMessage *)request rule:(nullable SLRule *)rule scenario:(SLScenario *)scenario identity:(NSString *)identity occurrence:(uint64_t)occurrence;
- (NSRange)rangeAt:(NSUInteger)index;
- (uint64_t)dueUSAt:(NSUInteger)index;
@end
NS_ASSUME_NONNULL_END
