#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Domain-separated hash sampling avoids global PRNG state and scheduling
/// dependencies. The same identity and occurrence always select the same draw.
FOUNDATION_EXPORT uint64_t SLDraw(uint64_t seed, NSString *rule, NSString *identity,
                                  uint64_t occurrence, NSString *purpose);
NS_ASSUME_NONNULL_END
