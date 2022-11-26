#import "SLFixture.h"
#import "SLBytes.h"
#import "SLJSON.h"
#import "SLError.h"
@implementation SLFixture
@synthesize request = _request;
@synthesize response = _response;
- (SLMessage *)request {
    return [_request copy];
}
- (SLMessage *)response {
    return [_response copy];
}
- (instancetype)initWithDocument:(NSDictionary *)document {
    if ((self = [super init])) {
        document = SLObject(SLJSONRead(SLJSONData(document)), @"fixture");
        SLKeys(document, @[ @"version", @"id", @"createdMs", @"privacy", @"request", @"response" ],
               @[ @"version", @"id", @"createdMs", @"privacy", @"request", @"response" ],
               @"fixture");
        SLInteger(document[@"version"], 1, 1, @"fixture.version");
        _identifier = [SLString(document[@"id"], 64, @"fixture.id") copy];
        SLRequire([[NSUUID alloc] initWithUUIDString:_identifier] != nil, @"fixture.id",
                  @"Fixture id must be a UUID");
        SLInteger(document[@"createdMs"], 0, INT64_MAX, @"createdMs");
        NSString *privacy = SLString(document[@"privacy"], 64, @"privacy");
        SLRequire(
            privacy.length == 64 &&
                [privacy rangeOfCharacterFromSet:
                             [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]
                                 .invertedSet]
                        .location == NSNotFound,
            @"fixture.privacy", @"Invalid privacy digest");
        _request = SLMessageFromDocument(document[@"request"], YES);
        _response = SLMessageFromDocument(document[@"response"], NO);
        _identity = SLRequestIdentity(document[@"request"]);
        _replayable = ![document[@"request"][@"bodyState"] isEqual:@"omitted"] &&
                      ![document[@"response"][@"bodyState"] isEqual:@"omitted"];
        _document = document;
        // Fixture content identity excludes its observation id and timestamp.
        _digest = SLSHA256(SLJSONData(@{
            @"privacy" : privacy,
            @"request" : document[@"request"],
            @"response" : document[@"response"]
        }));
    }
    return self;
}
+ (instancetype)captureRequest:(SLMessage *)request
                      response:(SLMessage *)response
                       privacy:(SLPrivacy *)privacy {
    NSDictionary *document = @{
        @"version" : @1,
        @"id" : NSUUID.UUID.UUIDString.lowercaseString,
        @"createdMs" : @((int64_t)(NSDate.date.timeIntervalSince1970 * 1000)),
        @"privacy" : privacy.digest,
        @"request" : [privacy message:request],
        @"response" : [privacy message:response]
    };
    return [[self alloc] initWithDocument:document];
}
@end
