#import "SLHead.h"
#import "SLBytes.h"
#import "SLTarget.h"
#import "SLError.h"
NSUInteger SLContentLength(SLHeaders *headers, BOOL *present) {
    NSArray *values = [headers values:@"Content-Length"];
    *present = values.count > 0;
    SLRequire(values.count <= 1, @"http.framing", @"Repeated Content-Length is rejected");
    if (!values.count)
        return 0;
    NSString *s = values[0];
    NSData *d = [s dataUsingEncoding:NSASCIIStringEncoding];
    SLRequire(d.length > 0, @"http.framing", @"Empty Content-Length");
    const uint8_t *p = d.bytes;
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < d.length; i++) {
        SLRequire(p[i] >= '0' && p[i] <= '9', @"http.framing",
                  @"Content-Length must contain only decimal digits");
        SLRequire(n <= (8 * 1024 * 1024 - (p[i] - '0')) / 10, @"http.body-limit",
                  @"Content-Length exceeds 8 MiB");
        n = n * 10 + p[i] - '0';
    }
    return n;
}
SLMessage *SLParseHead(NSData *head, BOOL request) {
    SLRequire(head.length <= 65536, @"http.head-limit", @"HTTP head exceeds 64 KiB");
    NSString *text = [[NSString alloc] initWithData:head encoding:NSISOLatin1StringEncoding];
    SLRequire(text && [text hasSuffix:@"\r\n\r\n"], @"http.syntax",
              @"HTTP head must end with CRLF CRLF");
    NSArray *lines = [text componentsSeparatedByString:@"\r\n"];
    SLRequire(lines.count >= 3 && lines.count <= 131, @"http.head-limit",
              @"HTTP header count exceeded");
    SLMessage *m = [SLMessage new];
    m.request = request;
    NSString *first = lines[0];
    SLRequire(SLFieldValue(first), @"http.syntax", @"Control byte in start line");
    if (request) {
        NSArray *parts = [first componentsSeparatedByString:@" "];
        SLRequire(parts.count == 3 && SLToken(parts[0]) && [parts[0] length] <= 32, @"http.syntax",
                  @"Malformed request line");
        m.method = parts[0];
        m.target = SLValidateTarget(parts[1]);
        m.version = parts[2];
    } else {
        SLRequire(first.length >= 12 && [first characterAtIndex:8] == ' ', @"http.syntax",
                  @"Malformed response line");
        m.version = [first substringToIndex:8];
        NSString *code = [first substringWithRange:NSMakeRange(9, 3)];
        SLRequire([code rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet]
                              .location == NSNotFound &&
                      code.length == 3,
                  @"http.syntax", @"Malformed status code");
        m.status = code.integerValue;
        SLRequire(m.status >= 200 && m.status <= 599, @"http.status",
                  @"Informational and upgraded upstream responses are unsupported");
        SLRequire(first.length == 12 || [first characterAtIndex:12] == ' ', @"http.syntax",
                  @"Malformed response reason");
        m.reason = first.length > 13 ? [first substringFromIndex:13] : @"";
    }
    SLRequire([@[ @"HTTP/1.0", @"HTTP/1.1" ] containsObject:m.version], @"http.version",
              @"Only HTTP/1.0 and HTTP/1.1 are supported");
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSUInteger i = 1; i + 2 < lines.count; i++) {
        NSString *line = lines[i];
        NSRange colon = [line rangeOfString:@":"];
        SLRequire(colon.location != NSNotFound && colon.location > 0, @"http.header",
                  @"Malformed header line");
        NSString *name = [line substringToIndex:colon.location];
        NSString *value = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet
                                                characterSetWithCharactersInString:@" \t"]];
        [pairs addObject:@[ name, value ]];
    }
    m.headers = [[SLHeaders alloc] initWithPairs:pairs];
    if (request && [m.version isEqual:@"HTTP/1.1"]) {
        NSArray *hosts = [m.headers values:@"Host"];
        SLRequire(hosts.count == 1 && [hosts[0] length] > 0, @"http.host",
                  @"HTTP/1.1 requires exactly one nonempty Host field");
    }
    BOOL present = NO;
    (void)SLContentLength(m.headers, &present);
    NSArray *encoding = [m.headers values:@"Transfer-Encoding"];
    SLRequire(!(encoding.count && present), @"http.framing",
              @"Transfer-Encoding with Content-Length is rejected");
    SLRequire(!encoding.count ||
                  (encoding.count == 1 && [[encoding[0] lowercaseString] isEqual:@"chunked"]),
              @"http.framing", @"Unsupported transfer coding");
    return m;
}
