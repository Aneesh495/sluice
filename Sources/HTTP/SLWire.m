#import "SLWire.h"
#import "SLBytes.h"
#import "SLError.h"
static NSData *Encode(NSString *start, SLHeaders *headers) {
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@\r\n", start];
    for (NSArray *pair in headers.pairs)
        [text appendFormat:@"%@: %@\r\n", pair[0], pair[1]];
    [text appendString:@"\r\n"];
    NSData *data = [text dataUsingEncoding:NSISOLatin1StringEncoding];
    SLRequire(data && data.length <= 65536, @"http.head-limit",
              @"Serialized HTTP head exceeds budget");
    return data;
}
NSData *SLWireResponseHead(SLMessage *message, NSUInteger advertisedLength) {
    SLRequire(!message.request && message.status >= 200 && message.status <= 599 &&
                  SLFieldValue(message.reason),
              @"http.response", @"Invalid response metadata");
    SLHeaders *h = [[message.headers endToEnd] without:[NSSet setWithArray:@[ @"content-length" ]]];
    if (message.status != 204)
        h = [h setting:@"Content-Length" value:@(advertisedLength).stringValue];
    h = [h setting:@"Connection" value:@"close"];
    return Encode(
        [NSString stringWithFormat:@"HTTP/1.1 %ld %@", (long)message.status, message.reason], h);
}
NSData *SLWireRequest(SLMessage *message, SLEndpoint *endpoint) {
    SLRequire(message.request && SLToken(message.method), @"http.request",
              @"Invalid request metadata");
    SLValidateTarget(message.target);
    SLHeaders *h = [[[message.headers endToEnd]
        without:[NSSet setWithArray:@[ @"host", @"content-length", @"expect" ]]]
        setting:@"Host"
          value:endpoint.authority];
    h = [h setting:@"Content-Length" value:@(message.body.length).stringValue];
    h = [h setting:@"Connection" value:@"close"];
    NSMutableData *wire =
        [Encode([NSString stringWithFormat:@"%@ %@ HTTP/1.1", message.method, message.target], h)
            mutableCopy];
    [wire appendData:message.body];
    return wire;
}
