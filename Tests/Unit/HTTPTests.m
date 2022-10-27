#import "SLTest.h"
#import "SLHeaders.h"
void SLTestHTTP(void) {
    SLTest(@"headers preserve repeats and remove named hop fields", ^{
        SLHeaders *h = [[SLHeaders alloc] initWithPairs:@[
            @[ @"Set-Cookie", @"a=1" ], @[ @"set-cookie", @"b=2" ],
            @[ @"Connection", @"x-private, keep-alive" ], @[ @"X-Private", @"secret" ]
        ]];
        CHECK([h values:@"SET-COOKIE"].count == 2);
        CHECK(![[h endToEnd] first:@"X-Private"]);
        CHECK([[h endToEnd] values:@"Set-Cookie"].count == 2);
        SLThrows(@"http.header", ^{
            (void)[[SLHeaders alloc] initWithPairs:@[ @[ @"x", @"ok\r\nInjected: yes" ] ]];
        });
    });
}
