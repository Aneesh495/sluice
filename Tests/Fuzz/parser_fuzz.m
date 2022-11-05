#import <Foundation/Foundation.h>
#import "SLHTTPParser.h"
#import "SLJSON.h"
#import "SLScenario.h"
#import "SLBytes.h"
#import "SLError.h"

static NSDictionary *Parse(NSData *data, NSUInteger stride) {
    BOOL request = !(data.length >= 5 && !memcmp(data.bytes, "HTTP/", 5));
    SLHTTPParser *parser = [[SLHTTPParser alloc] initRequest:request responseToHEAD:NO];
    @try {
        for (NSUInteger at = 0; at < data.length; at += stride)
            [parser feed:[data subdataWithRange:NSMakeRange(at, MIN(stride, data.length - at))]];
        [parser endOfFile];
        SLMessage *m = parser.message;
        return @{
            @"request" : @(m.request),
            @"method" : m.method,
            @"target" : m.target,
            @"status" : @(m.status),
            @"headers" : m.headers.pairs,
            @"body" : SLSHA256(m.body)
        };
    } @catch (SLError *error) {
        return nil;
    }
}
int LLVMFuzzerTestOneInput(const uint8_t *bytes, size_t count) {
    if (!count || count > 131072)
        return 0;
    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:bytes length:count];
        NSDictionary *whole = Parse(data, count);
        NSDictionary *fragmented = Parse(data, 1 + bytes[count - 1] % 64);
        if ((whole != nil) != (fragmented != nil) || (whole && ![whole isEqual:fragmented]))
            abort();
        @try {
            id value = SLJSONRead(data);
            if ([value isKindOfClass:NSDictionary.class] && value[@"rules"])
                (void)[[SLScenario alloc] initWithDocument:value];
        } @catch (SLError *error) {
        }
    }
    return 0;
}
