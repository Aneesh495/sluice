#import <Foundation/Foundation.h>
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLHTTPParser.h"
#import "SLError.h"
int main(void) {
    @autoreleasepool {
        @try {
            NSMutableData *input = [NSMutableData data];
            while (YES) {
                NSData *chunk = [NSFileHandle.fileHandleWithStandardInput availableData];
                if (!chunk.length)
                    break;
                SLRequire(input.length + chunk.length <= 16 * 1024 * 1024, @"driver.limit",
                          @"Input exceeds budget");
                [input appendData:chunk];
            }
            NSMutableArray *results = [NSMutableArray array];
            for (NSDictionary *item in SLArray(SLJSONRead(input), 10000, @"cases")) {
                @try {
                    NSData *wire = [[NSData alloc] initWithBase64EncodedString:item[@"wire"]
                                                                       options:0];
                    SLRequire(wire != nil, @"driver.base64", @"Invalid base64");
                    SLHTTPParser *parser =
                        [[SLHTTPParser alloc] initRequest:[item[@"request"] boolValue]
                                           responseToHEAD:[item[@"head"] boolValue]];
                    NSUInteger stride = (NSUInteger)SLInteger(item[@"stride"], 1, 65536, @"stride");
                    for (NSUInteger at = 0; at < wire.length; at += stride)
                        [parser
                            feed:[wire subdataWithRange:NSMakeRange(
                                                            at, MIN(stride, wire.length - at))]];
                    [parser endOfFile];
                    [results addObject:@{
                        @"accepted" : @YES,
                        @"status" : @(parser.message.status),
                        @"method" : parser.message.method,
                        @"target" : parser.message.target,
                        @"bodySHA256" : SLSHA256(parser.message.body),
                        @"bodyBytes" : @(parser.message.body.length)
                    }];
                } @catch (SLError *error) {
                    [results addObject:@{@"accepted" : @NO, @"error" : error.code}];
                }
            }
            puts(SLJSONString(results).UTF8String);
            return 0;
        } @catch (NSException *error) {
            fprintf(stderr, "%s\n", error.description.UTF8String);
            return 2;
        }
    }
}
