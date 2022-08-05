#import "SLMessage.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLAction : NSObject
@property(nonatomic, readonly) NSDictionary *document;
@property(nonatomic, readonly) NSUInteger delayMS;
@property(nonatomic, readonly) NSUInteger jitterMS;
@property(nonatomic, readonly) NSUInteger bytesPerSecond;
@property(nonatomic, readonly) NSUInteger chunkBytes;
@property(nonatomic, readonly, nullable) NSNumber *truncateAfter;
@property(nonatomic, readonly) BOOL disconnect;
- (instancetype)initWithDocument:(NSDictionary *)document;
- (SLMessage *)apply:(SLMessage *)response;
@end
NS_ASSUME_NONNULL_END
