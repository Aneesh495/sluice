#import "SLFixture.h"
NS_ASSUME_NONNULL_BEGIN
@interface SLReplayIndex : NSObject
- (instancetype)initWithFixtures:(NSArray<SLFixture *> *)fixtures privacy:(SLPrivacy *)privacy;
- (SLFixture *)select:(NSString *)identity identifier:(nullable NSString *)identifier;
@end
NS_ASSUME_NONNULL_END
