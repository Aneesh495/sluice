#import "SLAction.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"
@implementation SLAction
- (instancetype)initWithDocument:(NSDictionary *)document {
    if ((self = [super init])) {
        document = SLJSONRead(SLJSONData(document));
        SLObject(document, @"action");
        SLKeys(document,
               @[
                   @"status", @"bodyText", @"bodyJSON", @"headers", @"removeHeaders", @"delayMs",
                   @"jitterMs", @"bytesPerSecond", @"chunkBytes", @"truncateAfter", @"disconnect"
               ],
               @[], @"action");
        if (document[@"status"])
            SLInteger(document[@"status"], 200, 599, @"status");
        SLRequire(!(document[@"bodyText"] && document[@"bodyJSON"]), @"scenario.action",
                  @"bodyText and bodyJSON are mutually exclusive");
        if (document[@"bodyText"])
            SLString(document[@"bodyText"], 1024 * 1024, @"bodyText");
        if (document[@"bodyJSON"])
            SLRequire(SLJSONData(document[@"bodyJSON"]).length <= 1024 * 1024, @"scenario.action",
                      @"bodyJSON exceeds 1 MiB");
        if (document[@"headers"])
            (void)[[SLHeaders alloc] initWithPairs:document[@"headers"]];
        if (document[@"removeHeaders"])
            for (id name in SLArray(document[@"removeHeaders"], 128, @"removeHeaders"))
                SLRequire(SLToken(SLString(name, 256, @"header name")), @"scenario.action",
                          @"Invalid removed header name");
        _delayMS = (NSUInteger)SLInteger(document[@"delayMs"] ?: @0, 0, 60000, @"delayMs");
        _jitterMS = (NSUInteger)SLInteger(document[@"jitterMs"] ?: @0, 0, 60000, @"jitterMs");
        _bytesPerSecond = (NSUInteger)SLInteger(document[@"bytesPerSecond"] ?: @0, 0, 1000000000,
                                                @"bytesPerSecond");
        _chunkBytes =
            (NSUInteger)SLInteger(document[@"chunkBytes"] ?: @16384, 1, 1048576, @"chunkBytes");
        if (document[@"truncateAfter"])
            _truncateAfter =
                @(SLInteger(document[@"truncateAfter"], 0, 8 * 1024 * 1024, @"truncateAfter"));
        if (document[@"disconnect"]) {
            SLRequire(CFGetTypeID((__bridge CFTypeRef)document[@"disconnect"]) ==
                          CFBooleanGetTypeID(),
                      @"schema.type", @"disconnect must be boolean");
            _disconnect = [document[@"disconnect"] boolValue];
        }
        _document = [document copy];
    }
    return self;
}
- (SLMessage *)apply:(SLMessage *)response {
    SLMessage *m = [response copy];
    if (self.document[@"status"]) {
        m.status = [self.document[@"status"] integerValue];
        m.reason = [SLMessage response:m.status body:NSData.data contentType:@"text/plain"].reason;
    }
    NSMutableSet *remove = [NSMutableSet set];
    for (NSString *name in self.document[@"removeHeaders"])
        [remove addObject:name.lowercaseString];
    m.headers = [m.headers without:remove];
    if (self.document[@"bodyText"] || self.document[@"bodyJSON"]) {
        m.body = self.document[@"bodyText"] ? SLUTF8(self.document[@"bodyText"])
                                            : SLJSONData(self.document[@"bodyJSON"]);
        m.headers = [[m.headers
            without:[NSSet
                        setWithArray:@[ @"content-encoding", @"etag", @"content-md5", @"digest" ]]]
            setting:@"Content-Type"
              value:self.document[@"bodyText"] ? @"text/plain; charset=utf-8"
                                               : @"application/json"];
    }
    for (NSArray *pair in self.document[@"headers"])
        m.headers = [m.headers setting:pair[0] value:pair[1]];
    if (m.status == 204 || m.status == 304)
        m.body = NSData.data;
    return m;
}
@end
