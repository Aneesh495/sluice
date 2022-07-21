#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *SLValidateTarget(NSString *target);
FOUNDATION_EXPORT NSString *SLTargetPath(NSString *target);
@interface SLEndpoint : NSObject
@property(nonatomic, readonly) NSString *host;
@property(nonatomic, readonly) uint16_t port;
@property(nonatomic, readonly) NSString *authority;
+ (instancetype)parse:(NSString *)url;
@end
NS_ASSUME_NONNULL_END
