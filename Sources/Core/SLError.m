#import "SLError.h"
#import <CoreFoundation/CoreFoundation.h>

@implementation SLError
+ (instancetype)code:(NSString *)code message:(NSString *)message {
    return (SLError *)[self exceptionWithName:code reason:message userInfo:@{@"code" : code}];
}
- (NSString *)code {
    return self.name;
}
@end
void SLFail(NSString *code, NSString *message) {
    @throw [SLError code:code message:message];
}
BOOL SLIsInteger(id value) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
        return NO;
    const char *type = [value objCType];
    return strchr("cislqCISLQ", type[0]) != NULL;
}
int64_t SLInteger(id value, int64_t minimum, int64_t maximum, NSString *field) {
    SLRequire(SLIsInteger(value), @"schema.type",
              [field stringByAppendingString:@" must be an integer"]);
    // Compare before conversion so an unsigned value above INT64_MAX cannot wrap.
    NSDecimalNumber *n = [NSDecimalNumber decimalNumberWithString:[value stringValue]];
    SLRequire([n compare:[NSDecimalNumber decimalNumberWithString:@(minimum).stringValue]] !=
                      NSOrderedAscending &&
                  [n compare:[NSDecimalNumber decimalNumberWithString:@(maximum).stringValue]] !=
                      NSOrderedDescending,
              @"schema.range", [field stringByAppendingString:@" is outside its allowed range"]);
    return [value longLongValue];
}
NSString *SLString(id value, NSUInteger maximum, NSString *field) {
    SLRequire([value isKindOfClass:NSString.class] && [value length] <= maximum, @"schema.type",
              [field stringByAppendingString:@" must be a bounded string"]);
    return value;
}
NSDictionary *SLObject(id value, NSString *field) {
    SLRequire([value isKindOfClass:NSDictionary.class], @"schema.type",
              [field stringByAppendingString:@" must be an object"]);
    return value;
}
NSArray *SLArray(id value, NSUInteger maximum, NSString *field) {
    SLRequire([value isKindOfClass:NSArray.class] && [value count] <= maximum, @"schema.type",
              [field stringByAppendingString:@" must be a bounded array"]);
    return value;
}
void SLKeys(NSDictionary *object, NSArray *allowed, NSArray *required, NSString *field) {
    for (id key in object) {
        SLRequire([key isKindOfClass:NSString.class] && [allowed containsObject:key],
                  @"schema.unknown", [NSString stringWithFormat:@"%@ has an unknown field", field]);
    }
    for (NSString *key in required)
        SLRequire(object[key] != nil, @"schema.missing",
                  [NSString stringWithFormat:@"%@.%@ is required", field, key]);
}
