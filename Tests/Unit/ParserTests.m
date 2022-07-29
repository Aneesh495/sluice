#import "SLTest.h"
#import "SLHTTPParser.h"
#import "SLBytes.h"
#import "SLTarget.h"
static SLHTTPParser *Parse(NSString *wire, BOOL request) {
    SLHTTPParser *p=[[SLHTTPParser alloc] initRequest:request responseToHEAD:NO];
    [p feed:SLUTF8(wire)]; return p;
}
void SLTestParser(void) {
    SLTest(@"request parser is invariant under every two-way split", ^{
        NSData *d=SLUTF8(@"POST /v1/items?q=a%20b HTTP/1.1\r\nHost: local\r\nContent-Length: 5\r\nX-Test: yes\r\n\r\nhello");
        for (NSUInteger i=0;i<=d.length;i++) {
            SLHTTPParser *p=[[SLHTTPParser alloc] initRequest:YES responseToHEAD:NO];
            [p feed:[d subdataWithRange:NSMakeRange(0,i)]];
            [p feed:[d subdataWithRange:NSMakeRange(i,d.length-i)]];
            CHECK(p.complete); EQUAL(p.message.body,SLUTF8(@"hello"));
            EQUAL(p.message.target,@"/v1/items?q=a%20b");
        }
    });
    SLTest(@"chunk parser works byte by byte and across all splits", ^{
        NSData *d=SLUTF8(@"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n");
        for (NSUInteger stride=1;stride<=d.length;stride++) {
            SLHTTPParser *p=[[SLHTTPParser alloc] initRequest:NO responseToHEAD:NO];
            for (NSUInteger at=0;at<d.length;at+=stride) [p feed:[d subdataWithRange:NSMakeRange(at,MIN(stride,d.length-at))]];
            CHECK(p.complete); EQUAL(p.message.body,SLUTF8(@"abcde"));
        }
    });
    SLTest(@"EOF framing and incomplete messages", ^{
        SLHTTPParser *p=Parse(@"HTTP/1.0 200 OK\r\n\r\nabc",NO);
        CHECK(!p.complete); [p endOfFile]; EQUAL(p.message.body,SLUTF8(@"abc"));
        SLThrows(@"http.incomplete", ^{ [Parse(@"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabc",NO) endOfFile]; });
        SLThrows(@"http.incomplete", ^{ [Parse(@"GET /",YES) endOfFile]; });
    });
    SLTest(@"framing ambiguities and unsupported protocols fail closed", ^{
        NSArray *heads=@[
            @"Content-Length: 1\r\nContent-Length: 1\r\n",
            @"Transfer-Encoding: chunked\r\nContent-Length: 0\r\n",
            @"Content-Length: +1\r\n", @"Content-Length: 1,1\r\n",
            @"Transfer-Encoding: gzip, chunked\r\n"];
        for (NSString *head in heads) SLThrows(@"http.framing", ^{
            Parse([NSString stringWithFormat:@"POST / HTTP/1.1\r\nHost: x\r\n%@\r\n",head],YES);
        });
        SLThrows(@"http.trailing", ^{ Parse(@"GET / HTTP/1.1\r\nHost: x\r\n\r\nextra",YES); });
        SLThrows(@"http.host", ^{ Parse(@"GET / HTTP/1.1\r\n\r\n",YES); });
        SLThrows(@"http.header", ^{ Parse(@"GET / HTTP/1.1\r\nHost: x\r\n folded: no\r\n\r\n",YES); });
        SLThrows(@"http.chunk", ^{ Parse(@"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1;x=y\r\na\r\n0\r\n\r\n",NO); });
    });
    SLTest(@"origin target and endpoint restrictions", ^{
        EQUAL(SLValidateTarget(@"/hello%20world?a=b"),@"/hello%20world?a=b");
        EQUAL([SLEndpoint parse:@"http://localhost:1234"].authority,@"localhost:1234");
        EQUAL([SLEndpoint parse:@"http://[::1]:8080"].host,@"::1");
        for (NSString *s in @[@"http://host/",@"/bad%",@"/bad%GG",@"/x#fragment",@"/a b",@"/x\\y"]) SLThrows(@"http.target", ^{ SLValidateTarget(s); });
        for (NSString *s in @[@"https://localhost",@"http://user@localhost",@"http://localhost/base",@"http://localhost:0"]) {
            @try { [SLEndpoint parse:s]; SLFail(@"test.accepted",@"Bad endpoint accepted"); }
            @catch (SLError *e) { CHECK(![e.code isEqual:@"test.accepted"]); }
        }
    });
}
