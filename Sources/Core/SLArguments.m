#import "SLArguments.h"
#import "SLError.h"
@implementation SLArguments
- (instancetype)initWithArguments:(NSArray *)arguments
                           values:(NSArray *)values
                            flags:(NSArray *)flags {
    if ((self = [super init])) {
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        NSMutableArray *operands = [NSMutableArray array];
        BOOL literal = NO;
        for (NSUInteger i = 0; i < arguments.count; i++) {
            NSString *arg = arguments[i];
            if (!literal && [arg isEqual:@"--"]) {
                literal = YES;
                continue;
            }
            if (literal || ![arg hasPrefix:@"-"] || [arg isEqual:@"-"]) {
                [operands addObject:arg];
                continue;
            }
            SLRequire([arg hasPrefix:@"--"] && arg.length > 2, @"cli.option",
                      @"Expected a long option beginning with --");
            NSString *key = [arg substringFromIndex:2];
            SLRequire([values containsObject:key] || [flags containsObject:key], @"cli.option",
                      [NSString stringWithFormat:@"Unknown option --%@", key]);
            SLRequire(!options[key], @"cli.duplicate",
                      [NSString stringWithFormat:@"Repeated option --%@", key]);
            if ([values containsObject:key]) {
                SLRequire(i + 1 < arguments.count && ![arguments[i + 1] hasPrefix:@"--"],
                          @"cli.value", [NSString stringWithFormat:@"Missing value for --%@", key]);
                NSString *value = arguments[++i];
                SLRequire(value.length > 0, @"cli.value", @"Option values cannot be empty");
                options[key] = value;
            } else
                options[key] = @"true";
        }
        _options = [options copy];
        _operands = [operands copy];
    }
    return self;
}
- (NSString *)required:(NSString *)name {
    NSString *value = self.options[name];
    SLRequire(value != nil, @"cli.required", [NSString stringWithFormat:@"--%@ is required", name]);
    return value;
}
- (NSString *)value:(NSString *)name {
    return self.options[name];
}
- (BOOL)has:(NSString *)name {
    return self.options[name] != nil;
}
- (int64_t)integer:(NSString *)name
          fallback:(int64_t)fallback
           minimum:(int64_t)minimum
           maximum:(int64_t)maximum {
    NSString *s = self.options[name];
    if (!s)
        return fallback;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    scanner.charactersToBeSkipped = nil;
    long long n = 0;
    SLRequire([scanner scanLongLong:&n] && scanner.isAtEnd && ![s hasPrefix:@"+"] &&
                  [s rangeOfCharacterFromSet:[NSCharacterSet
                                                 characterSetWithCharactersInString:@"-0123456789"]
                                                 .invertedSet]
                          .location == NSNotFound,
              @"cli.integer", [name stringByAppendingString:@" must be a decimal integer"]);
    return SLInteger(@(n), minimum, maximum, name);
}
@end
