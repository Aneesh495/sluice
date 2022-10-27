#import "SLMessage.h"
@implementation SLMessage
- (instancetype)init {
    if ((self = [super init])) {
        _method = @"GET";
        _target = @"/";
        _status = 200;
        _reason = @"OK";
        _version = @"HTTP/1.1";
        _headers = [[SLHeaders alloc] initWithPairs:@[]];
        _body = NSData.data;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    SLMessage *m = [SLMessage new];
    m.request = self.request;
    m.method = self.method;
    m.target = self.target;
    m.status = self.status;
    m.reason = self.reason;
    m.version = self.version;
    m.headers = self.headers;
    m.body = self.body;
    return m;
}
+ (instancetype)response:(NSInteger)status body:(NSData *)body contentType:(NSString *)contentType {
    SLMessage *m = [self new];
    m.status = status;
    m.body = body;
    m.reason = @{
        @200 : @"OK",
        @201 : @"Created",
        @204 : @"No Content",
        @400 : @"Bad Request",
        @404 : @"Not Found",
        @409 : @"Conflict",
        @413 : @"Content Too Large",
        @429 : @"Too Many Requests",
        @500 : @"Internal Server Error",
        @502 : @"Bad Gateway",
        @503 : @"Service Unavailable",
        @504 : @"Gateway Timeout"
    }[@(status)]
                   ?: @"Response";
    m.headers = [[SLHeaders alloc] initWithPairs:@[ @[ @"Content-Type", contentType ] ]];
    return m;
}
@end
