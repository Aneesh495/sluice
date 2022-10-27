#import "SLMatch.h"
#import "SLTarget.h"
#import "SLBytes.h"
#import "SLError.h"
#import "SLJSON.h"
@implementation SLMatch
- (instancetype)initWithDocument:(NSDictionary *)document {
    if ((self = [super init])) {
        document = SLJSONRead(SLJSONData(document));
        SLObject(document, @"match");
        SLKeys(document, @[ @"method", @"path", @"pathPrefix", @"headers" ], @[], @"match");
        if (document[@"method"])
            SLRequire(SLToken(SLString(document[@"method"], 32, @"match.method")),
                      @"scenario.match", @"Method must be an HTTP token");
        SLRequire(!(document[@"path"] && document[@"pathPrefix"]), @"scenario.match",
                  @"path and pathPrefix are mutually exclusive");
        for (NSString *key in @[ @"path", @"pathPrefix" ])
            if (document[key]) {
                NSString *path = SLValidateTarget(SLString(document[key], 8192, key));
                SLRequire(![path containsString:@"?"], @"scenario.match",
                          @"Path matchers do not include a query");
            }
        if (document[@"headers"]) {
            NSDictionary *headers = SLObject(document[@"headers"], @"match.headers");
            SLRequire(headers.count <= 32, @"scenario.match", @"Too many header predicates");
            for (NSString *name in headers)
                SLRequire(SLToken(name) &&
                              SLFieldValue(SLString(headers[name], 8192, @"header predicate")),
                          @"scenario.match", @"Invalid header predicate");
        }
        _document = [document copy];
    }
    return self;
}
- (BOOL)matches:(SLMessage *)request {
    if (self.document[@"method"] && ![self.document[@"method"] isEqual:request.method])
        return NO;
    NSString *path = SLTargetPath(request.target);
    if (self.document[@"path"] && ![self.document[@"path"] isEqual:path])
        return NO;
    if (self.document[@"pathPrefix"] && ![path hasPrefix:self.document[@"pathPrefix"]])
        return NO;
    for (NSString *name in self.document[@"headers"])
        if (![[request.headers values:name] containsObject:self.document[@"headers"][name]])
            return NO;
    return YES;
}
@end
