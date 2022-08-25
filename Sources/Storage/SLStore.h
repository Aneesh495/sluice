#import "SLFixture.h"
NS_ASSUME_NONNULL_BEGIN
/// A store owns one serialized SQLite connection. Separate readers may open the
/// same workspace. WAL and a bounded busy timeout arbitrate concurrent processes.
@interface SLStore : NSObject
@property(nonatomic, readonly) NSString *directory;
- (instancetype)initWithDirectory:(NSString *)directory;
- (NSString *)saveFixture:(SLFixture *)fixture;
- (NSArray<SLFixture *> *)fixtures;
- (nullable SLFixture *)fixture:(NSString *)identifier;
- (NSArray<SLFixture *> *)matching:(NSString *)identity;
- (void)saveReceipt:(NSDictionary *)receipt;
- (NSArray<NSDictionary *> *)receipts:(NSUInteger)limit;
- (NSDictionary *)statistics;
- (void)importFixtures:(NSArray<SLFixture *> *)fixtures;
- (void)checkIntegrity;
@end
NS_ASSUME_NONNULL_END
