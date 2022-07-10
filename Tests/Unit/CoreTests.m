#import "SLTest.h"
void SLTestCore(void) {
    SLTest(@"strict integer validation", ^{
        CHECK(SLInteger(@42,0,100,@"n")==42);
        SLThrows(@"schema.type", ^{ SLInteger(@YES,0,100,@"n"); });
        SLThrows(@"schema.type", ^{ SLInteger(@1.2,0,100,@"n"); });
        SLThrows(@"schema.range", ^{ SLInteger(@(-1),0,100,@"n"); });
        SLThrows(@"schema.range", ^{ SLInteger(@(UINT64_MAX),0,INT64_MAX,@"n"); });
    });
    SLTest(@"unknown and missing fields are rejected", ^{
        SLThrows(@"schema.unknown", ^{ SLKeys(@{@"typo":@1},@[@"name"],@[],@"rule"); });
        SLThrows(@"schema.missing", ^{ SLKeys(@{},@[@"name"],@[@"name"],@"rule"); });
    });
}
