#import "SLTest.h"
#import "SLArguments.h"
#import "SLDeliveryPlan.h"
#import "SLReceipt.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLPrivacy.h"
static SLDeliveryPlan *SmallPlan(void) {
    SLMessage *request=[SLMessage new]; request.request=YES;
    SLMessage *response=[SLMessage response:200 body:SLUTF8(@"{}") contentType:@"application/json"];
    return [[SLDeliveryPlan alloc] initResponse:response request:request rule:nil scenario:SLScenario.passthrough identity:@"id" occurrence:1];
}
void SLTestBoundaries(void) {
    SLTest(@"CLI integer overflow is rejected instead of saturated", ^{
        for (NSString *text in @[@"99999999999999999999999999999",@"-99999999999999999999999999999"]) {
            SLArguments *args=[[SLArguments alloc] initWithArguments:@[@"--n",text] values:@[@"n"] flags:@[]];
            SLThrows(@"cli.integer", ^{ [args integer:@"n" fallback:0 minimum:INT64_MIN maximum:INT64_MAX]; });
        }
        SLArguments *args=[[SLArguments alloc] initWithArguments:@[@"--n",@"9223372036854775807"] values:@[@"n"] flags:@[]];
        CHECK([args integer:@"n" fallback:0 minimum:0 maximum:INT64_MAX]==INT64_MAX);
    });
    SLTest(@"plan truth values retain JSON boolean types", ^{
        NSDictionary *summary=SLJSONRead(SLJSONData(SmallPlan().summary));
        CHECK(CFGetTypeID((__bridge CFTypeRef)summary[@"truncated"])==CFBooleanGetTypeID());
    });
    SLTest(@"receipt validation covers the complete embedded plan schema", ^{
        SLDeliveryPlan *plan=SmallPlan();
        NSMutableDictionary *receipt=[SLMakeReceipt(NSUUID.UUID.UUIDString,@"replay",@"id",1,nil,plan.summary,0,10,@"client-closed",nil) mutableCopy];
        NSMutableDictionary *broken=[plan.summary mutableCopy]; broken[@"status"]=@"bad"; receipt[@"plan"]=broken;
        SLThrows(@"schema.type", ^{ SLValidateReceipt(receipt); });
        broken=[plan.summary mutableCopy]; broken[@"unknown"]=@1; receipt[@"plan"]=broken;
        SLThrows(@"schema.unknown", ^{ SLValidateReceipt(receipt); });
    });
    SLTest(@"canonical JSON expansion cannot exceed the captured body budget", ^{
        NSString *slashes=[@"/" stringByPaddingToLength:4*1024*1024 withString:@"/" startingAtIndex:0];
        SLMessage *response=[SLMessage response:200 body:SLUTF8([NSString stringWithFormat:@"\"%@\"",slashes]) contentType:@"application/json"];
        SLPrivacy *privacy=[[SLPrivacy alloc] initWithDocument:@{@"version":@1,@"bodies":@"json"}];
        NSDictionary *filtered=[privacy message:response];
        EQUAL(filtered[@"bodyState"],@"omitted");
        CHECK(SLMessageFromDocument(filtered,NO).body.length==0);
    });
}
