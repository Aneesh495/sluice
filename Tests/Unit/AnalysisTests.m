#import "SLTest.h"
#import "SLDiff.h"
#import "SLReport.h"
#import "SLHAR.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLReceipt.h"
void SLTestAnalysis(void) {
    SLTest(@"JSON diff escapes pointer components and bounds output", ^{
        NSArray *changes = SLJSONDiff(@{@"a/b" : @{@"x~y" : @1}}, @{@"a/b" : @{@"x~y" : @2}}, 8);
        EQUAL(changes[0][@"path"], @"/a~1b/x~0y");
        CHECK(SLJSONDiff(@[ @1, @2, @3 ], @[ @4, @5, @6 ], 2).count == 2);
        CHECK(!SLJSONDiff(@{@"a" : @1}, @{@"a" : @1}, 1).count);
    });
    SLTest(@"delivery report uses nearest-rank percentiles and distinct outcomes", ^{
        NSString *session = NSUUID.UUID.UUIDString;
        NSArray *receipts = @[
            SLMakeReceipt(session, @"record", @"", 1, nil, nil, 0, 10, @"client-closed", nil),
            SLMakeReceipt(session, @"record", @"", 2, nil, nil, 0, 20, @"timeout", @"net.timeout"),
            SLMakeReceipt(session, @"record", @"", 3, nil, nil, 0, 30, @"complete", nil)
        ];
        NSDictionary *report = SLReceiptReport(receipts);
        EQUAL(report[@"elapsedUs"][@"p50"], @20);
        EQUAL(report[@"elapsedUs"][@"p95"], @30);
        EQUAL(report[@"errors"][@"net.timeout"], @1);
        EQUAL(SLReceiptReport(@[])[@"elapsedUs"][@"max"], @0);
    });
    SLTest(@"HAR passes decoded entities through privacy and strips stale compression", ^{
        NSDictionary *entry = @{
            @"request" : @{
                @"method" : @"GET",
                @"url" : @"https://example.test/api?token=private",
                @"headers" : @[],
                @"bodySize" : @0
            },
            @"response" : @{
                @"status" : @200,
                @"statusText" : @"OK",
                @"headers" : @[ @{@"name" : @"Content-Encoding", @"value" : @"gzip"} ],
                @"content" : @{
                    @"size" : @20,
                    @"mimeType" : @"application/json",
                    @"text" : @"{\"token\":\"private\"}"
                }
            }
        };
        NSData *har = SLJSONData(@{@"log" : @{@"version" : @"1.2", @"entries" : @[ entry ]}});
        SLPrivacy *privacy = [[SLPrivacy alloc] initWithDocument:@{
            @"version" : @1,
            @"bodies" : @"json"
        }];
        SLFixture *fixture = SLHARImport(har, privacy).firstObject;
        CHECK(fixture.replayable);
        CHECK(![SLJSONString(fixture.document) containsString:@"private"]);
        CHECK(![fixture.response.headers first:@"Content-Encoding"]);
        EQUAL(fixture.request.target, @"/api?token=%5Bredacted%5D");
    });
    SLTest(@"HAR unavailable response body is rejected", ^{
        NSDictionary *entry = @{
            @"request" : @{@"method" : @"GET", @"url" : @"http://example.test/", @"headers" : @[]},
            @"response" : @{
                @"status" : @200,
                @"headers" : @[],
                @"content" : @{@"size" : @20, @"mimeType" : @"application/json"}
            }
        };
        SLThrows(@"har.body", ^{
            SLHARImport(SLJSONData(
                            @{@"log" : @{@"version" : @"1.2", @"entries" : @[ entry ]}}),
                        SLPrivacy.metadataOnly);
        });
    });
}
