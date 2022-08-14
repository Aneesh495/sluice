#import "SLMessage.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLPrivacy : NSObject
@property(nonatomic, readonly) NSDictionary *document;
@property(nonatomic, readonly) NSString *digest;
@property(nonatomic, readonly) NSString *bodyMode;
- (instancetype)initWithDocument:(NSDictionary *)document;
+ (instancetype)metadataOnly;
- (NSString *)target:(NSString *)target;
- (SLHeaders *)headers:(SLHeaders *)headers;
- (NSDictionary *)message:(SLMessage *)message;
@end
FOUNDATION_EXPORT SLMessage *SLMessageFromDocument(NSDictionary *document, BOOL request);
FOUNDATION_EXPORT NSString *SLRequestIdentity(NSDictionary *request);
NS_ASSUME_NONNULL_END
