#import "SLRandom.h"
#import "SLJSON.h"
#import "SLBytes.h"
uint64_t SLDraw(uint64_t seed, NSString *rule, NSString *identity, uint64_t occurrence, NSString *purpose) {
    NSString *digest=SLSHA256(SLJSONData(@[@"sluice.draw.v1",@(seed),rule,identity,@(occurrence),purpose]));
    uint64_t result=0;
    for (NSUInteger i=0;i<16;i++) { unichar c=[digest characterAtIndex:i]; result=(result<<4)|(c<='9'?c-'0':c-'a'+10); }
    return result;
}
