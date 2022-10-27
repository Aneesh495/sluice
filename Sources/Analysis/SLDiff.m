#import "SLDiff.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"
static NSString *Pointer(NSString *path, NSString *key) {
    return [path stringByAppendingFormat:@"/%@", [[key stringByReplacingOccurrencesOfString:@"~"
                                                                                 withString:@"~0"]
                                                     stringByReplacingOccurrencesOfString:@"/"
                                                                               withString:@"~1"]];
}
static id Preview(id value) {
    NSData *data = SLJSONData(value);
    return data.length <= 512 ? value : @{
        @"summary" : @"value omitted from diff preview",
        @"jsonBytes" : @(data.length),
        @"sha256" : SLSHA256(data)
    };
}
static void Walk(id before, id after, NSString *path, NSMutableArray *changes, NSUInteger budget) {
    if ([before isEqual:after] || changes.count >= budget)
        return;
    BOOL objects =
        [before isKindOfClass:NSDictionary.class] && [after isKindOfClass:NSDictionary.class];
    BOOL arrays = [before isKindOfClass:NSArray.class] && [after isKindOfClass:NSArray.class];
    if (objects) {
        NSMutableSet *set = [NSMutableSet setWithArray:[before allKeys]];
        [set addObjectsFromArray:[after allKeys]];
        for (NSString *key in [[set allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
            if (changes.count >= budget)
                break;
            id a = before[key], b = after[key];
            NSString *next = Pointer(path, key);
            if (!a || !b)
                [changes addObject:@{
                    @"op" : a ? @"remove" : @"add",
                    @"path" : next,
                    @"value" : Preview(a ?: b)
                }];
            else
                Walk(a, b, next, changes, budget);
        }
    } else if (arrays) {
        NSUInteger common = MIN([before count], [after count]);
        for (NSUInteger i = 0; i < common && changes.count < budget; i++)
            Walk(before[i], after[i], Pointer(path, @(i).stringValue), changes, budget);
        for (NSUInteger i = common;
             i < MAX([before count], [after count]) && changes.count < budget; i++) {
            BOOL removed = i < [before count];
            [changes addObject:@{
                @"op" : removed ? @"remove" : @"add",
                @"path" : Pointer(path, @(i).stringValue),
                @"value" : Preview(removed ? before[i] : after[i])
            }];
        }
    } else
        [changes addObject:@{
            @"op" : @"replace",
            @"path" : path,
            @"before" : Preview(before),
            @"after" : Preview(after)
        }];
}
NSArray *SLJSONDiff(id before, id after, NSUInteger budget) {
    SLRequire(budget > 0 && budget <= 1024, @"diff.budget", @"Diff budget must be 1 through 1024");
    // Validate depth at this public boundary even when callers supply objects.
    before = SLJSONRead(SLJSONData(before));
    after = SLJSONRead(SLJSONData(after));
    NSMutableArray *changes = [NSMutableArray array];
    Walk(before, after, @"", changes, budget);
    return changes;
}
static NSDictionary *HeaderMap(SLHeaders *headers) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSArray *pair in [headers endToEnd].pairs) {
        NSString *name = [pair[0] lowercaseString];
        if (!result[name])
            result[name] = [NSMutableArray array];
        [result[name] addObject:pair[1]];
    }
    return result;
}
NSDictionary *SLFixtureDiff(SLFixture *before, SLFixture *after) {
    NSMutableDictionary *result = [@{
        @"before" : before.identifier,
        @"after" : after.identifier,
        @"sameIdentity" : @([before.identity isEqual:after.identity]),
        @"request" : SLJSONDiff(before.document[@"request"], after.document[@"request"], 128),
        @"status" : @[ @(before.response.status), @(after.response.status) ],
        @"headers" :
            SLJSONDiff(HeaderMap(before.response.headers), HeaderMap(after.response.headers), 128)
    } mutableCopy];
    BOOL json = [before.document[@"response"][@"bodyState"] isEqual:@"json"] &&
                [after.document[@"response"][@"bodyState"] isEqual:@"json"];
    if (json)
        result[@"body"] = @{
            @"kind" : @"json",
            @"changes" :
                SLJSONDiff(SLJSONRead(before.response.body), SLJSONRead(after.response.body), 256),
            @"limit" : @256
        };
    else
        result[@"body"] = @{
            @"kind" : @"digest",
            @"beforeSHA256" : SLSHA256(before.response.body),
            @"afterSHA256" : SLSHA256(after.response.body),
            @"beforeState" : before.document[@"response"][@"bodyState"],
            @"afterState" : after.document[@"response"][@"bodyState"]
        };
    return result;
}
