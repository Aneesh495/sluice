#import "SLTest.h"
#import "SLJSON.h"
#import "SLBytes.h"
void SLTestJSON(void) {
    SLTest(@"strict JSON roundtrip and sorted keys", ^{
        EQUAL(SLJSONString(@{@"z":@2,@"a":@1}),@"{\"a\":1,\"z\":2}");
        EQUAL(SLJSONRead(SLUTF8(@"[true,null,1,\"snow ☃\"]")),(@[@YES,NSNull.null,@1,@"snow ☃"]));
        EQUAL(SLSHA256(SLUTF8(@"abc")),@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    });
    SLTest(@"JSON rejects duplicate escaped keys", ^{
        SLThrows(@"json.duplicate", ^{ SLJSONRead(SLUTF8(@"{\"a\":1,\"\\u0061\":2}")); });
        for (NSString *s in @[@"[1,]",@"{} {}",@"{",@"\"bad\\x\"",@"01",@"trueX"]) {
            SLThrows(@"json.syntax", ^{ SLJSONRead(SLUTF8(s)); });
        }
    });
    SLTest(@"JSON nesting is bounded", ^{
        NSMutableString *s=[NSMutableString string]; for (int i=0;i<40;i++) [s appendString:@"["];
        [s appendString:@"0"]; for (int i=0;i<40;i++) [s appendString:@"]"];
        SLThrows(@"json.limit", ^{ SLJSONRead(SLUTF8(s)); });
    });
}
