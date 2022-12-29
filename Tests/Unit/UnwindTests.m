#import "SLTest.h"

// Recovered input failures unwind strong locals. Without ARC exception cleanup,
// every rejected message can retain parser or schema objects until process exit.
static NSUInteger destroyedProbes;
@interface SLUnwindProbe : NSObject
@end
@implementation SLUnwindProbe
- (void)dealloc {
    destroyedProbes++;
}
@end
static void RejectWithOwnedLocal(void) {
    SLUnwindProbe *probe __attribute__((objc_precise_lifetime)) = [SLUnwindProbe new];
    CHECK([probe isKindOfClass:SLUnwindProbe.class]);
    SLFail(@"test.expected-rejection", @"Exercise recoverable exception cleanup");
}
void SLTestUnwind(void) {
    SLTest(@"recovered rejection releases strong locals during stack unwinding", ^{
        NSUInteger before = destroyedProbes;
        @autoreleasepool {
            SLThrows(@"test.expected-rejection", ^{
                RejectWithOwnedLocal();
            });
        }
        CHECK(destroyedProbes == before + 1);
    });
}
