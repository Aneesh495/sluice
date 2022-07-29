#import "SLTest.h"
NSUInteger SLTestsRun = 0;
NSUInteger SLTestsFailed = 0;
void SLTest(NSString *name, void (^body)(void)) {
    SLTestsRun++;
    @autoreleasepool {
        @try { body(); printf("ok %lu - %s\n",(unsigned long)SLTestsRun,name.UTF8String); }
        @catch (NSException *e) { SLTestsFailed++; printf("not ok %lu - %s: %s\n",(unsigned long)SLTestsRun,name.UTF8String,e.description.UTF8String); }
    }
}
void SLThrows(NSString *code, void (^body)(void)) {
    @try { body(); } @catch (SLError *e) { EQUAL(e.code,code); return; }
    SLFail(@"test.missing-failure",[code stringByAppendingString:@" was not raised"]);
}
void SLTestCore(void);
void SLTestParser(void);
void SLTestHTTP(void);
void SLTestJSON(void);
int main(void) {
    @autoreleasepool {
        SLTestCore();
        SLTestParser();
        SLTestHTTP();
        SLTestJSON();
        printf("# %lu tests, %lu failed\n",(unsigned long)SLTestsRun,(unsigned long)SLTestsFailed);
        return SLTestsFailed ? 1 : 0;
    }
}
