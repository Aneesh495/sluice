#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Public failures have stable codes. Messages give context without echoing
/// request bodies, credentials, or full URLs into logs.
@interface SLError : NSException
@property(nonatomic, readonly) NSString *code;
+ (instancetype)code:(NSString *)code message:(NSString *)message;
@end
FOUNDATION_EXPORT void SLFail(NSString *code, NSString *message) __attribute__((noreturn));
FOUNDATION_EXPORT void SLRequire(BOOL condition, NSString *code, NSString *message);
FOUNDATION_EXPORT BOOL SLIsInteger(id _Nullable value);
FOUNDATION_EXPORT int64_t SLInteger(id value, int64_t minimum, int64_t maximum, NSString *field);
FOUNDATION_EXPORT NSString *SLString(id value, NSUInteger maximum, NSString *field);
FOUNDATION_EXPORT NSDictionary *SLObject(id value, NSString *field);
FOUNDATION_EXPORT NSArray *SLArray(id value, NSUInteger maximum, NSString *field);
FOUNDATION_EXPORT void SLKeys(NSDictionary *object, NSArray<NSString *> *allowed,
                              NSArray<NSString *> *required, NSString *field);
NS_ASSUME_NONNULL_END
