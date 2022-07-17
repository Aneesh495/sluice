#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Ordered pairs preserve repeated fields such as Set-Cookie. This type is
/// immutable so a validated header block cannot change beneath a delivery plan.
@interface SLHeaders : NSObject
@property(nonatomic, readonly) NSArray<NSArray<NSString *> *> *pairs;
- (instancetype)initWithPairs:(NSArray *)pairs;
- (NSArray<NSString *> *)values:(NSString *)name;
- (nullable NSString *)first:(NSString *)name;
- (SLHeaders *)without:(NSSet<NSString *> *)names;
- (SLHeaders *)setting:(NSString *)name value:(NSString *)value;
- (SLHeaders *)endToEnd;
@end
NS_ASSUME_NONNULL_END
