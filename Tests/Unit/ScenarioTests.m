#import "SLTest.h"
#import "SLScenario.h"
#import "SLDeliveryPlan.h"
#import "SLBytes.h"
#import "SLRandom.h"
static SLScenario *Scenario(NSDictionary *action) {
    return [[SLScenario alloc] initWithDocument:@{@"version":@1,@"name":@"test",@"seed":@7,@"rules":@[@{@"id":@"failure",@"match":@{@"pathPrefix":@"/api"},@"after":@1,@"every":@2,@"limit":@2,@"action":action}]}];
}
void SLTestScenario(void) {
    SLTest(@"occurrence selection is per identity with exact boundaries", ^{
        SLScenario *s=Scenario(@{@"status":@503}); SLMessage *r=[SLMessage new]; r.request=YES; r.target=@"/api/item";
        for (uint64_t i=1;i<=8;i++) CHECK(([s ruleFor:r identity:@"abc" occurrence:i]!=nil)==(i==2 || i==4));
        CHECK(SLDraw(1,@"r",@"id",2,@"chance")==SLDraw(1,@"r",@"id",2,@"chance"));
        CHECK(SLDraw(1,@"r",@"id",2,@"chance")!=SLDraw(1,@"r",@"id",2,@"jitter"));
    });
    SLTest(@"delivery plan preserves advertised length on real truncation", ^{
        SLScenario *s=Scenario(@{@"truncateAfter":@3,@"delayMs":@20,@"jitterMs":@10,@"chunkBytes":@2,@"bytesPerSecond":@2});
        SLMessage *request=[SLMessage new]; request.request=YES;
        SLMessage *response=[SLMessage response:200 body:SLUTF8(@"abcdef") contentType:@"text/plain"];
        SLDeliveryPlan *p=[[SLDeliveryPlan alloc] initResponse:response request:request rule:s.rules[0] scenario:s identity:@"id" occurrence:2];
        CHECK(p.delayUS>=20000 && p.delayUS<=30000); CHECK(p.segmentCount==3);
        EQUAL(p.summary[@"advertisedBodyBytes"],@6); EQUAL(p.summary[@"deliveredBodyBytes"],@3);
        CHECK([SLDecodeUTF8(p.wire) containsString:@"Content-Length: 6\r\n"]);
        CHECK([SLDecodeUTF8(p.wire) hasSuffix:@"abc"]);
        CHECK([p dueUSAt:2]==p.delayUS+1000000);
        CHECK(NSMaxRange([p rangeAt:2])==p.wire.length);
    });
    SLTest(@"HEAD and disconnect plans do not emit entity bytes", ^{
        SLMessage *request=[SLMessage new]; request.method=@"HEAD";
        SLMessage *response=[SLMessage response:200 body:SLUTF8(@"abc") contentType:@"text/plain"];
        SLDeliveryPlan *p=[[SLDeliveryPlan alloc] initResponse:response request:request rule:nil scenario:SLScenario.passthrough identity:@"id" occurrence:1];
        CHECK(p.segmentCount==1); CHECK([SLDecodeUTF8(p.wire) hasSuffix:@"\r\n\r\n"]);
        SLScenario *s=Scenario(@{@"disconnect":@YES});
        p=[[SLDeliveryPlan alloc] initResponse:response request:request rule:s.rules[0] scenario:s identity:@"id" occurrence:2];
        CHECK(p.wire.length==0 && p.segmentCount==0);
    });
    SLTest(@"scenario rejects misspellings invalid rates and duplicate ids", ^{
        SLThrows(@"schema.unknown", ^{ Scenario(@{@"delaiMs":@20}); });
        SLThrows(@"schema.range", ^{ Scenario(@{@"chunkBytes":@0}); });
        SLThrows(@"schema.type", ^{ Scenario(@{@"disconnect":@1}); });
        SLThrows(@"scenario.action", ^{ Scenario(@{@"bodyText":@"x",@"bodyJSON":@{}}); });
    });
}
