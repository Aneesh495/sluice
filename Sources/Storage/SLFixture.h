#import "SLPrivacy.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLFixture : NSObject
@property(nonatomic, readonly) NSDictionary *document;
@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) NSString *identity;
@property(nonatomic, readonly) NSString *digest;
@property(nonatomic, readonly) BOOL replayable;
@property(nonatomic, readonly) SLMessage *request;
@property(nonatomic, readonly) SLMessage *response;
- (instancetype)initWithDocument:(NSDictionary *)document;
+ (instancetype)captureRequest:(SLMessage *)request response:(SLMessage *)response privacy:(SLPrivacy *)privacy;
@end
NS_ASSUME_NONNULL_END
