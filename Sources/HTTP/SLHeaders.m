#import "SLHeaders.h"
#import "SLBytes.h"
#import "SLError.h"
@implementation SLHeaders
- (instancetype)initWithPairs:(NSArray *)pairs {
    if ((self=[super init])) {
        SLArray(pairs,128,@"headers"); NSMutableArray *copy=[NSMutableArray array];
        for (id p in pairs) {
            NSArray *pair=SLArray(p,2,@"header pair");
            SLRequire(pair.count==2,@"http.header",@"Header pair must have two strings");
            NSString *name=SLString(pair[0],256,@"header name");
            NSString *value=SLString(pair[1],8192,@"header value");
            SLRequire(SLToken(name) && SLFieldValue(value),@"http.header",@"Invalid header name or field value");
            [copy addObject:@[[name copy],[value copy]]];
        }
        _pairs=[copy copy];
    } return self;
}
- (NSArray *)values:(NSString *)name {
    NSMutableArray *result=[NSMutableArray array];
    for (NSArray *p in self.pairs) if ([p[0] caseInsensitiveCompare:name]==NSOrderedSame) [result addObject:p[1]];
    return result;
}
- (NSString *)first:(NSString *)name { return [self values:name].firstObject; }
- (SLHeaders *)without:(NSSet *)names {
    NSMutableArray *result=[NSMutableArray array];
    for (NSArray *p in self.pairs) if (![names containsObject:[p[0] lowercaseString]]) [result addObject:p];
    return [[SLHeaders alloc] initWithPairs:result];
}
- (SLHeaders *)setting:(NSString *)name value:(NSString *)value {
    NSMutableArray *result=[[[self without:[NSSet setWithObject:name.lowercaseString]] pairs] mutableCopy];
    [result addObject:@[name,value]]; return [[SLHeaders alloc] initWithPairs:result];
}
- (SLHeaders *)endToEnd {
    NSMutableSet *hop=[NSMutableSet setWithArray:@[@"connection",@"keep-alive",@"proxy-authenticate",@"proxy-authorization",@"te",@"trailer",@"transfer-encoding",@"upgrade",@"proxy-connection"]];
    for (NSString *line in [self values:@"connection"]) {
        for (NSString *token in [line componentsSeparatedByString:@","]) {
            NSString *name=[[token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
            if (name.length) [hop addObject:name];
        }
    }
    return [self without:hop];
}
@end
