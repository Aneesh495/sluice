#import "SLFixture.h"
NS_ASSUME_NONNULL_BEGIN
/// A tape is an explicit baseline sequence per request identity. Unlike a fault
/// rule, it selects the recorded state that exists before any fault is applied.
@interface SLTape : NSObject
@property(nonatomic, readonly) NSDictionary *document;
@property(nonatomic, readonly) NSString *digest;
- (instancetype)initWithDocument:(NSDictionary *)document;
+ (instancetype)fromReceipts:(NSArray<NSDictionary *> *)receipts
                     session:(NSString *)session
                  repeatLast:(BOOL)repeatLast;
- (NSString *)fixtureForIdentity:(NSString *)identity occurrence:(uint64_t)occurrence;
- (void)validateFixtures:(NSArray<SLFixture *> *)fixtures;
@end
NS_ASSUME_NONNULL_END
