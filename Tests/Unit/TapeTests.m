#import "SLTest.h"
#import "SLTape.h"
#import "SLReceipt.h"
#import "SLBytes.h"
static SLFixture *MakeFixture(NSInteger revision) {
    SLMessage *request = [SLMessage new];
    request.request = YES;
    request.target = @"/job";
    SLMessage *response = [SLMessage
           response:200
               body:SLUTF8([NSString stringWithFormat:@"{\"revision\":%ld}", (long)revision])
        contentType:@"application/json"];
    return [SLFixture captureRequest:request
                            response:response
                             privacy:[[SLPrivacy alloc] initWithDocument:@{
                                 @"version" : @1,
                                 @"bodies" : @"json"
                             }]];
}
void SLTestTape(void) {
    SLTest(@"tape preserves per-identity order and explicit exhaustion", ^{
        SLFixture *a = MakeFixture(1), *b = MakeFixture(2);
        NSString *session = NSUUID.UUID.UUIDString;
        NSDictionary *first = SLMakeReceipt(session, @"record", a.identity, 1, a.identifier, nil, 0,
                                            10, @"complete", nil);
        NSDictionary *second = SLMakeReceipt(session, @"record", b.identity, 2, b.identifier, nil,
                                             0, 10, @"complete", nil);
        SLTape *tape = [SLTape fromReceipts:@[ second, first ] session:session repeatLast:NO];
        [tape validateFixtures:@[ a, b ]];
        EQUAL([tape fixtureForIdentity:a.identity occurrence:1], a.identifier);
        EQUAL([tape fixtureForIdentity:a.identity occurrence:2], b.identifier);
        SLThrows(@"tape.exhausted", ^{
            [tape fixtureForIdentity:a.identity occurrence:3];
        });
        tape = [SLTape fromReceipts:@[ first, second ] session:session repeatLast:YES];
        EQUAL([tape fixtureForIdentity:a.identity occurrence:100], b.identifier);
    });
    SLTest(@"tape rejects gaps duplicate occurrences and missing references", ^{
        SLFixture *a = MakeFixture(1);
        NSString *session = NSUUID.UUID.UUIDString;
        NSDictionary *gap = SLMakeReceipt(session, @"record", a.identity, 2, a.identifier, nil, 0,
                                          10, @"complete", nil);
        SLThrows(@"tape.incomplete", ^{
            [SLTape fromReceipts:@[ gap ] session:session repeatLast:NO];
        });
        NSDictionary *first = SLMakeReceipt(session, @"record", a.identity, 1, a.identifier, nil, 0,
                                            10, @"complete", nil);
        SLThrows(@"tape.incomplete", ^{
            [SLTape fromReceipts:@[ first, first ] session:session repeatLast:NO];
        });
        SLTape *tape = [SLTape fromReceipts:@[ first ] session:session repeatLast:NO];
        SLThrows(@"tape.fixture", ^{
            [tape validateFixtures:@[]];
        });
        SLThrows(@"tape.miss", ^{
            [tape fixtureForIdentity:@"missing" occurrence:1];
        });
    });
}
