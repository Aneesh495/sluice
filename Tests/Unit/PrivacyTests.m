#import "SLTest.h"
#import "SLPrivacy.h"
#import "SLBytes.h"
#import "SLJSON.h"
void SLTestPrivacy(void) {
    SLTest(@"privacy removes credentials and decoded query secrets", ^{
        SLPrivacy *p = [SLPrivacy metadataOnly];
        EQUAL([p target:@"/api?to%6Ben=rawsecret&ok=yes&token=another"],
              @"/api?to%6Ben=%5Bredacted%5D&ok=yes&token=%5Bredacted%5D");
        SLMessage *m = [SLMessage new];
        m.request = YES;
        m.target = @"/api?token=rawsecret";
        m.headers = [[SLHeaders alloc] initWithPairs:@[
            @[ @"Authorization", @"Bearer rawsecret" ], @[ @"Cookie", @"session=rawsecret" ]
        ]];
        m.body = SLUTF8(@"private payload");
        NSDictionary *d = [p message:m];
        CHECK(![SLJSONString(d) containsString:@"rawsecret"]);
        EQUAL(d[@"bodyState"], @"omitted");
        CHECK([SLMessageFromDocument(d, YES).body length] == 0);
    });
    SLTest(@"nested JSON keys are redacted before canonical encoding", ^{
        SLPrivacy *p = [[SLPrivacy alloc] initWithDocument:@{
            @"version" : @1,
            @"bodies" : @"json",
            @"jsonKeys" : @[ @"email" ]
        }];
        SLMessage *m = [SLMessage
               response:200
                   body:SLUTF8(@"{\"data\":[{\"Password\":\"s1\",\"email\":\"s2\",\"id\":3}]}")
            contentType:@"application/problem+json; charset=utf-8"];
        NSDictionary *d = [p message:m];
        SLMessage *clean = SLMessageFromDocument(d, NO);
        CHECK(![SLDecodeUTF8(clean.body) containsString:@"s1"]);
        CHECK(![SLDecodeUTF8(clean.body) containsString:@"s2"]);
        EQUAL(d[@"bodyState"], @"json");
        m.body = SLUTF8(@"{broken");
        EQUAL([p message:m][@"bodyState"], @"omitted");
        m.body = SLUTF8(@"{}");
        m.headers = [m.headers setting:@"Content-Encoding" value:@"gzip"];
        EQUAL([p message:m][@"bodyState"], @"omitted");
    });
    SLTest(@"identity is stable across host replacement and secret rotation", ^{
        SLPrivacy *p = SLPrivacy.metadataOnly;
        SLMessage *m = [SLMessage new];
        m.request = YES;
        m.target = @"/x?token=a";
        NSDictionary *a = [p message:m];
        m.target = @"/x?token=b";
        m.headers = [m.headers setting:@"Host" value:@"another"];
        EQUAL(SLRequestIdentity(a), SLRequestIdentity([p message:m]));
        m.method = @"POST";
        CHECK(![SLRequestIdentity(a) isEqual:SLRequestIdentity([p message:m])]);
    });
}
