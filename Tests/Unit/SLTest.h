#import <Foundation/Foundation.h>
#import "SLError.h"
FOUNDATION_EXPORT NSUInteger SLTestsRun;
FOUNDATION_EXPORT NSUInteger SLTestsFailed;
FOUNDATION_EXPORT void SLTest(NSString *name, void (^body)(void));
FOUNDATION_EXPORT void SLThrows(NSString *code, void (^body)(void));
#define CHECK(x)                                                                                   \
    SLRequire((x), @"test.assert", [NSString stringWithFormat:@"%s:%d: %s", __FILE__, __LINE__, #x])
#define EQUAL(a, b) CHECK([(a) isEqual:(b)])
